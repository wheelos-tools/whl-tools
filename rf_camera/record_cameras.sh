#!/usr/bin/env bash
# Record the vehicle cameras (/dev/video0-8) simultaneously with GStreamer on
# the host (outside the Apollo container), using the Apollo camera config
# settings: yuyv, IO_METHOD_MMAP, trigger_fps 10.
#
# Made for long unattended drives: output is split into rolling segments,
# memory per camera is bounded (frames are dropped and counted if the encoder
# or disk falls behind), and recording stops cleanly before the disk fills.
#
# These cameras (basa / FPD-Link) only stream when the adv trigger is on, so
# the script starts streaming first and then enables the trigger, the same
# order as Apollo's CameraDevice::Init().
#
# Usage:
#   ./record_cameras.sh [-C LIST] [-d SECONDS] [-s SECONDS] [-r GB]
#                       [-o OUT_DIR] [-c jpeg|raw] [-q QUALITY] [-f FPS] [-g]
#     -C  cameras to record, e.g. 0,1,6 or 0-5 (default: 1,2,3,4,5,8)
#     -d  stop after SECONDS (default: run until Ctrl-C / SIGTERM)
#     -s  segment length in seconds (default: 300)
#     -r  stop cleanly when free disk space drops below GB (default: 5)
#     -o  output root dir (default: ./camera_records)
#     -c  jpeg (default, MJPEG ~2-4 MB/s per cam at 10 fps) or
#         raw (YUY2, ~42 MB/s per cam at 10 fps)
#     -q  JPEG quality 1-100 (default: 85)
#     -f  trigger fps 1-30 (default: 10)
#     -g  use GPS PPS for the trigger (trigger_internal 0). Default is the
#         FPGA internal PPS (trigger_internal 1); GPS PPS gives no frames
#         while the GPS has no fix.
#
# Output: OUT_DIR/<timestamp>/
#   videoN/videoN_00000.mkv ...  rolling segments per camera
#   timestamps.csv               camera,frame,pts_ns,wall_time per frame
#   record.log                   settings, status lines, warnings
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

WIDTH, HEIGHT = 1920, 1084  # basa driver reports 1920x1084 for 1080p sensors
RAW_FRAME_BYTES = WIDTH * HEIGHT * 2  # YUY2
JPEG_MBPS_PER_CAM_10FPS = 3.7  # measured on the vehicle at quality 85
QUEUE_FRAMES = 10  # per-camera buffer before frames are dropped
TRIGGER_DELAY_S = 2
FIRST_CHECK_S = 5
STATUS_S = 30
DISK_CHECK_S = 10
STOP_TIMEOUT_S = 15
ADV_TRIGGER_LIB = os.environ.get(
    "ADV_TRIGGER_LIB", "/opt/apollo/pkgs/pkgs/adv_plat/lib/libadv_trigger.so")
DEFAULT_CAMS = [1, 2, 3, 4, 5, 8]


def parse_cams(text):
    cams = set()
    for part in text.split(","):
        lo, _, hi = part.partition("-")
        cams.update(range(int(lo), int(hi or lo) + 1))
    if not cams or min(cams) < 0 or max(cams) > 8:
        raise argparse.ArgumentTypeError("cameras must be in 0-8")
    return sorted(cams)


parser = argparse.ArgumentParser(prog="record_cameras.sh")
parser.add_argument("-C", type=parse_cams, default=DEFAULT_CAMS,
                    help="cameras, e.g. 0,1,6 or 0-5")
parser.add_argument("-d", type=float, help="stop after SECONDS")
parser.add_argument("-s", type=float, default=300, help="segment SECONDS")
parser.add_argument("-r", type=float, default=5, help="free space floor GB")
parser.add_argument("-o", default="./camera_records", help="output root dir")
parser.add_argument("-c", choices=["jpeg", "raw"], default="jpeg")
parser.add_argument("-q", type=int, default=85, help="JPEG quality")
parser.add_argument("-f", type=int, default=10, help="trigger fps (1-30)")
parser.add_argument("-g", action="store_true", help="use GPS PPS")
args = parser.parse_args()
if not 1 <= args.f <= 30:
    sys.exit("-f must be 1-30")
if not 1 <= args.q <= 100:
    sys.exit("-q must be 1-100")
trigger_internal = 0 if args.g else 1
DEVICES = ["/dev/video%d" % i for i in args.C]
NAMES = [os.path.basename(dev) for dev in DEVICES]

for dev in DEVICES:
    if not os.access(dev, os.R_OK):
        sys.exit("cannot read %s (run list_camera_formats.sh?)" % dev)
if not os.path.isfile(ADV_TRIGGER_LIB):
    sys.exit("libadv_trigger.so not found: " + ADV_TRIGGER_LIB)
trigger_lib = ctypes.CDLL(ADV_TRIGGER_LIB)

os.makedirs(args.o, exist_ok=True)


def free_gb():
    st = os.statvfs(args.o)
    return st.f_bavail * st.f_frsize / 1e9


if free_gb() < args.r:
    sys.exit("only %.1f GB free on %s, below the -r floor of %.1f GB"
             % (free_gb(), args.o, args.r))

out_dir = os.path.join(args.o, time.strftime("%Y%m%d_%H%M%S"))
for name in NAMES:
    os.makedirs(os.path.join(out_dir, name))
log_file = open(os.path.join(out_dir, "record.log"), "w")


def log(msg):
    line = "%s %s" % (time.strftime("%H:%M:%S"), msg)
    print(line, flush=True)
    log_file.write(line + "\n")
    log_file.flush()


# Expected load, so overload is visible before driving off.
n = len(DEVICES)
capture_mbps = n * RAW_FRAME_BYTES * args.f / 1e6
if args.c == "jpeg":
    disk_mbps = n * JPEG_MBPS_PER_CAM_10FPS * args.f / 10
else:
    disk_mbps = capture_mbps
log("capture %.0f MB/s from %d cameras (%s @ %d fps), "
    "expected disk write ~%.0f MB/s" % (capture_mbps, n, args.c, args.f,
                                         disk_mbps))
log("%.1f GB free, floor %.1f GB -> ~%.0f min of recording"
    % (free_gb(), args.r, (free_gb() - args.r) * 1e3 / disk_mbps / 60))
if args.c == "raw" and disk_mbps > 100:
    log("WARN: raw at %.0f MB/s may exceed the disk write speed; expect "
        "dropped frames. Use fewer cameras (-C), lower fps (-f) or -c jpeg."
        % disk_mbps)


def set_triggers(enable):
    for dev in DEVICES:
        if enable:
            ret = trigger_lib.adv_trigger_enable(
                dev.encode(), ctypes.c_ubyte(args.f),
                ctypes.c_ubyte(trigger_internal))
        else:
            ret = trigger_lib.adv_trigger_disable(dev.encode())
        log("adv_trigger_%s(%s) -> %d"
            % ("enable" if enable else "disable", dev, ret))


def make(factory, **props):
    elem = Gst.ElementFactory.make(factory, None)
    if elem is None:
        sys.exit("GStreamer element not found: " + factory)
    for key, value in props.items():
        elem.set_property(key.replace("_", "-"), value)
    pipeline.add(elem)
    return elem


Gst.init(None)
pipeline = Gst.Pipeline.new("record")
frame_counts = [0] * n
drop_counts = [0] * n
sources = []


def on_overrun(_queue, cam):
    # The queue is full; leaky=downstream drops its oldest frame.
    drop_counts[cam] += 1


for i, (dev, name) in enumerate(zip(DEVICES, NAMES)):
    src = make("v4l2src", device=dev, io_mode=2, do_timestamp=True)  # mmap
    caps = make("capsfilter", caps=Gst.Caps.from_string(
        "video/x-raw,format=YUY2,width=%d,height=%d" % (WIDTH, HEIGHT)))
    # The driver advertises a bogus 120/1; label the stream with the real
    # trigger rate so players show the right fps and duration.
    rate = make("capssetter", caps=Gst.Caps.from_string(
        "video/x-raw,framerate=%d/1" % args.f))
    queue = make("queue", max_size_buffers=QUEUE_FRAMES, max_size_bytes=0,
                 max_size_time=0, leaky=2)  # 2 = downstream (drop oldest)
    queue.connect("overrun", on_overrun, i)
    chain = [src, caps, rate, queue]
    if args.c == "jpeg":
        chain.append(make("jpegenc", quality=args.q))
    # Every JPEG / raw frame is a keyframe, so segments split exactly.
    # MKV stays readable if a segment is cut off by a crash or power loss.
    split = make("splitmuxsink",
                 location=os.path.join(out_dir, name, name + "_%05d.mkv"),
                 max_size_time=int(args.s * Gst.SECOND),
                 muxer=Gst.ElementFactory.make("matroskamux", None))
    for a, b in zip(chain, chain[1:]):
        if not a.link(b):
            sys.exit("cannot link %s -> %s" % (a.get_name(), b.get_name()))
    if chain[-1].get_static_pad("src").link(
            split.get_request_pad("video")) != Gst.PadLinkReturn.OK:
        sys.exit("cannot link to splitmuxsink for " + dev)
    sources.append(src)

csv = open(os.path.join(out_dir, "timestamps.csv"), "w", buffering=1)
csv.write("camera,frame,pts_ns,wall_time\n")
wall_offset = None  # wall clock (s) at pipeline running time 0


def on_buffer(pad, info, cam):
    global wall_offset
    if wall_offset is None:
        running_ns = pipeline.get_clock().get_time() - pipeline.get_base_time()
        wall_offset = time.time() - running_ns / 1e9
    buf = info.get_buffer()
    # do-timestamp puts the capture time in DTS; the driver's PTS is 0.
    buf.pts = buf.dts
    csv.write("%s,%d,%d,%.6f\n" % (NAMES[cam], frame_counts[cam], buf.pts,
                                   wall_offset + buf.pts / 1e9))
    frame_counts[cam] += 1
    return Gst.PadProbeReturn.OK


for i, src in enumerate(sources):
    src.get_static_pad("src").add_probe(Gst.PadProbeType.BUFFER, on_buffer, i)

loop = GLib.MainLoop()
# PyGObject (3.26) adds its own SIGINT handler to every MainLoop that quits
# the loop at once and raises KeyboardInterrupt, before EOS reaches the
# muxers, leaving the last segments unfinalized. Remove it so Ctrl-C goes
# only through stop() below.
if hasattr(loop, "_signal_source"):
    GLib.source_remove(loop._signal_source)
    del loop._signal_source
stopping = False


def stop(reason="signal"):
    global stopping
    if not stopping:
        stopping = True
        log("Stopping (%s), sending EOS..." % reason)
        pipeline.send_event(Gst.Event.new_eos())
        GLib.timeout_add_seconds(STOP_TIMEOUT_S, force_quit)
    return GLib.SOURCE_REMOVE


def force_quit():
    log("WARN: EOS not finished after %d s, forcing stop" % STOP_TIMEOUT_S)
    loop.quit()
    return GLib.SOURCE_REMOVE


def on_message(_, msg):
    if msg.type == Gst.MessageType.EOS:
        loop.quit()
    elif msg.type == Gst.MessageType.ERROR:
        err, dbg = msg.parse_error()
        log("ERROR from %s: %s\n%s" % (msg.src.get_name(), err.message, dbg))
        loop.quit()


def written_bytes():
    total = 0
    for name in NAMES:
        for entry in os.scandir(os.path.join(out_dir, name)):
            total += entry.stat().st_size
    return total


last = {"time": time.time(), "frames": list(frame_counts), "bytes": 0}


def status():
    now = time.time()
    dt = max(now - last["time"], 1e-3)
    written = written_bytes()
    rate = (written - last["bytes"]) / dt / 1e6
    fps = [(c - p) / dt for c, p in zip(frame_counts, last["frames"])]
    free = free_gb()
    eta = "%.0f min" % ((free - args.r) * 1e3 / rate / 60) if rate > 0 else "-"
    log("fps %s | drops %d | written %.2f GB @ %.1f MB/s | free %.1f GB, "
        "floor in %s" % (" ".join("%s=%.1f" % (nm[5:], f)
                                  for nm, f in zip(NAMES, fps)),
                         sum(drop_counts), written / 1e9, rate, free, eta))
    for name, f, d in zip(NAMES, fps, drop_counts):
        if f == 0:
            log("WARN: no frames from %s in the last %.0f s" % (name, dt))
        if d:
            log("WARN: %s dropped %d frames so far (encoder/disk too slow)"
                % (name, d))
    last.update(time=now, frames=list(frame_counts), bytes=written)
    csv.flush()
    return GLib.SOURCE_CONTINUE


def first_check():
    status()
    return GLib.SOURCE_REMOVE


def disk_check():
    free = free_gb()
    if free < args.r:
        log("free space %.1f GB below floor %.1f GB" % (free, args.r))
        stop("disk floor")
        return GLib.SOURCE_REMOVE
    return GLib.SOURCE_CONTINUE


def start_triggers():
    set_triggers(True)
    GLib.timeout_add_seconds(FIRST_CHECK_S, first_check)
    GLib.timeout_add_seconds(STATUS_S, status)
    GLib.timeout_add_seconds(DISK_CHECK_S, disk_check)
    if args.d:
        GLib.timeout_add(int(args.d * 1000), stop, "duration reached")
    return GLib.SOURCE_REMOVE


bus = pipeline.get_bus()
bus.add_signal_watch()
bus.connect("message", on_message)
GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGINT, stop, "SIGINT")
GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGTERM, stop, "SIGTERM")

# Don't wait for PLAYING: the sinks only finish the state change once frames
# arrive, which needs the trigger.
pipeline.set_state(Gst.State.PLAYING)
GLib.timeout_add_seconds(TRIGGER_DELAY_S, start_triggers)

log("Recording %s -> %s (segments %.0f s, trigger %d fps, PPS %s). "
    "Ctrl-C to stop." % (",".join(NAMES), out_dir, args.s, args.f,
                         "FPGA" if trigger_internal else "GPS"))
try:
    loop.run()
finally:
    set_triggers(False)
    pipeline.set_state(Gst.State.NULL)
    csv.close()
    log("frames per camera: %s, dropped: %s" % (frame_counts, drop_counts))
    for name in NAMES:
        segs = sorted(os.listdir(os.path.join(out_dir, name)))
        size = sum(os.path.getsize(os.path.join(out_dir, name, s))
                   for s in segs)
        log("  %-8s %3d segments %9.1f MB" % (name, len(segs), size / 1e6))
    log_file.close()
EOF
