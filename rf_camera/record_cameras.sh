#!/usr/bin/env bash
# Record /dev/video0-7 simultaneously with GStreamer on the host (outside the
# Apollo container), using the Apollo camera config settings:
#   yuyv, IO_METHOD_MMAP, trigger_fps 10
#
# These cameras (basa / FPD-Link) only stream when the adv trigger is on, so
# the script starts streaming first and then enables the trigger, the same
# order as Apollo's CameraDevice::Init().
#
# Usage:
#   ./record_cameras.sh [-d SECONDS] [-o OUT_DIR] [-c jpeg|raw] [-g]
#     -d  stop after SECONDS (default: run until Ctrl-C)
#     -o  output root dir (default: ./camera_records)
#     -c  jpeg (default, MJPEG ~2-3 MB/s per cam) or
#         raw (YUY2, ~42 MB/s per cam)
#     -g  use GPS PPS for the trigger (trigger_internal 0). Default is the
#         FPGA internal PPS (trigger_internal 1); GPS PPS gives no frames
#         while the GPS has no fix.
#
# Output: OUT_DIR/<timestamp>/
#   videoN.mkv      one file per camera
#   timestamps.csv  camera,frame,pts_ns,wall_time per frame
# The basa driver leaves PTS at 0, so each frame is stamped with the time it
# arrived on the shared pipeline clock; PTS is comparable across cameras.
#
# Requires: gstreamer1.0-plugins-good, python3-gi, gir1.2-gstreamer-1.0,
#           libadv_trigger.so (override with ADV_TRIGGER_LIB=...)

exec python3 - "$@" <<'EOF'
import argparse
import ctypes
import os
import signal
import sys
import time

import gi
gi.require_version("Gst", "1.0")
from gi.repository import GLib, Gst

DEVICES = ["/dev/video%d" % i for i in range(8)]
WIDTH, HEIGHT = 1920, 1084  # basa driver reports 1920x1084 for 1080p sensors
TRIGGER_FPS = 10
JPEG_QUALITY = 85
TRIGGER_DELAY_S = 2
HEALTH_CHECK_S = 5
ADV_TRIGGER_LIB = os.environ.get(
    "ADV_TRIGGER_LIB", "/opt/apollo/pkgs/pkgs/adv_plat/lib/libadv_trigger.so")

parser = argparse.ArgumentParser(prog="record_cameras.sh")
parser.add_argument("-d", type=float, help="stop after SECONDS")
parser.add_argument("-o", default="./camera_records", help="output root dir")
parser.add_argument("-c", choices=["jpeg", "raw"], default="jpeg")
parser.add_argument("-g", action="store_true", help="use GPS PPS")
args = parser.parse_args()
trigger_internal = 0 if args.g else 1

for dev in DEVICES:
    if not os.access(dev, os.R_OK):
        sys.exit("cannot read %s (run list_camera_formats.sh?)" % dev)
if not os.path.isfile(ADV_TRIGGER_LIB):
    sys.exit("libadv_trigger.so not found: " + ADV_TRIGGER_LIB)
trigger_lib = ctypes.CDLL(ADV_TRIGGER_LIB)

out_dir = os.path.join(args.o, time.strftime("%Y%m%d_%H%M%S"))
os.makedirs(out_dir)


def set_triggers(enable):
    for dev in DEVICES:
        if enable:
            ret = trigger_lib.adv_trigger_enable(
                dev.encode(), ctypes.c_ubyte(TRIGGER_FPS),
                ctypes.c_ubyte(trigger_internal))
        else:
            ret = trigger_lib.adv_trigger_disable(dev.encode())
        print("adv_trigger_%s(%s) -> %d"
              % ("enable" if enable else "disable", dev, ret))


Gst.init(None)
encode = "jpegenc quality=%d" % JPEG_QUALITY if args.c == "jpeg" else "identity"
branches = []
for i, dev in enumerate(DEVICES):
    name = os.path.basename(dev)
    branches.append(
        "v4l2src name=src%d device=%s io-mode=mmap do-timestamp=true "
        "! video/x-raw,format=YUY2,width=%d,height=%d "
        "! queue max-size-buffers=30 max-size-bytes=0 max-size-time=0 "
        "! %s ! matroskamux ! filesink location=%s"
        % (i, dev, WIDTH, HEIGHT, encode, os.path.join(out_dir, name + ".mkv")))
pipeline = Gst.parse_launch(" ".join(branches))

csv = open(os.path.join(out_dir, "timestamps.csv"), "w")
csv.write("camera,frame,pts_ns,wall_time\n")
frame_counts = [0] * len(DEVICES)
wall_offset = None  # wall clock (s) at pipeline running time 0


def on_buffer(pad, info, cam):
    global wall_offset
    if wall_offset is None:
        running_ns = pipeline.get_clock().get_time() - pipeline.get_base_time()
        wall_offset = time.time() - running_ns / 1e9
    buf = info.get_buffer()
    # do-timestamp puts the capture time in DTS; the driver's PTS is 0.
    buf.pts = buf.dts
    csv.write("%s,%d,%d,%.6f\n" % (os.path.basename(DEVICES[cam]),
                                   frame_counts[cam], buf.pts,
                                   wall_offset + buf.pts / 1e9))
    frame_counts[cam] += 1
    return Gst.PadProbeReturn.OK


for i in range(len(DEVICES)):
    pipeline.get_by_name("src%d" % i).get_static_pad("src").add_probe(
        Gst.PadProbeType.BUFFER, on_buffer, i)

loop = GLib.MainLoop()
stopping = False


def stop(*_):
    global stopping
    if not stopping:
        stopping = True
        print("Stopping (sending EOS)...")
        pipeline.send_event(Gst.Event.new_eos())
    return GLib.SOURCE_REMOVE


def on_message(_, msg):
    if msg.type == Gst.MessageType.EOS:
        loop.quit()
    elif msg.type == Gst.MessageType.ERROR:
        err, dbg = msg.parse_error()
        print("ERROR from %s: %s\n%s" % (msg.src.get_name(), err.message, dbg))
        loop.quit()


def health_check():
    for dev, n in zip(DEVICES, frame_counts):
        if n == 0:
            print("WARN: no frames from %s yet" % dev)
    print("frames so far: %s" % frame_counts)
    return GLib.SOURCE_REMOVE


def start_triggers():
    set_triggers(True)
    GLib.timeout_add_seconds(HEALTH_CHECK_S, health_check)
    if args.d:
        GLib.timeout_add(int(args.d * 1000), stop)
    return GLib.SOURCE_REMOVE


bus = pipeline.get_bus()
bus.add_signal_watch()
bus.connect("message", on_message)
GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGINT, stop)
GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGTERM, stop)

# Don't wait for PLAYING: the sinks only finish the state change once frames
# arrive, which needs the trigger.
pipeline.set_state(Gst.State.PLAYING)
GLib.timeout_add_seconds(TRIGGER_DELAY_S, start_triggers)

print("Recording %d cameras -> %s (codec %s, trigger %d fps, PPS %s). "
      "Ctrl-C to stop." % (len(DEVICES), out_dir, args.c, TRIGGER_FPS,
                           "FPGA" if trigger_internal else "GPS"))
try:
    loop.run()
finally:
    set_triggers(False)
    pipeline.set_state(Gst.State.NULL)
    csv.close()
    print("frames per camera: %s" % frame_counts)
    for f in sorted(os.listdir(out_dir)):
        size = os.path.getsize(os.path.join(out_dir, f))
        print("  %-16s %8.1f MB" % (f, size / 1e6))
EOF
