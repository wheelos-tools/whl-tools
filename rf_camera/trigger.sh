#!/usr/bin/env bash
# Manually control the camera adv trigger (FPGA, basa driver).
#
# Usage:
#   ./trigger.sh start [-g] [DEV...]   enable trigger (default /dev/video0-8)
#                                      -g: use GPS PPS instead of FPGA PPS
#   ./trigger.sh stop [DEV...]         disable trigger
#   ./trigger.sh status                show GPS / PPS status of the FPGA
#
# Env: TRIGGER_FPS (default 10), ADV_TRIGGER_LIB (libadv_trigger.so path)

exec python3 - "$@" <<'EOF'
import ctypes
import os
import sys

FLAG_GPS_VALID = 1 << 0
FLAG_PPS_VALID = 1 << 1
lib = ctypes.CDLL(os.environ.get(
    "ADV_TRIGGER_LIB", "/opt/apollo/pkgs/pkgs/adv_plat/lib/libadv_trigger.so"))
fps = int(os.environ.get("TRIGGER_FPS", "10"))

args = sys.argv[1:]
if not args or args[0] not in ("start", "stop", "status"):
    sys.exit("usage: trigger.sh start [-g] [DEV...] | stop [DEV...] | status")
cmd, args = args[0], args[1:]

if cmd == "status":
    buf = ctypes.create_string_buffer(65536)  # struct adv_trigger_status
    ret = lib.adv_trigger_get_status(buf)
    flags = ctypes.c_int.from_buffer(buf).value
    name = buf.raw[4:36].split(b"\0")[0].decode(errors="replace")
    lib.adv_trigger_version.restype = ctypes.c_char_p
    print("adv_trigger_get_status -> %d (lib %s)"
          % (ret, lib.adv_trigger_version().decode()))
    print("device %s  GPS time: %s  PPS: %s" % (
        name, "valid" if flags & FLAG_GPS_VALID else "NOT valid",
        "valid" if flags & FLAG_PPS_VALID else "NOT valid"))
    sys.exit(ret)

internal = 1
if "-g" in args:
    args.remove("-g")
    internal = 0
devs = args or ["/dev/video%d" % i for i in range(9)]
failed = False
for dev in devs:
    if cmd == "start":
        ret = lib.adv_trigger_enable(dev.encode(), ctypes.c_ubyte(fps),
                                     ctypes.c_ubyte(internal))
    else:
        ret = lib.adv_trigger_disable(dev.encode())
    print("%s %s -> %d" % (cmd, dev, ret))
    failed |= ret != 0
if cmd == "start":
    print("fps %d, PPS source: %s" % (fps, "FPGA" if internal else "GPS"))
sys.exit(1 if failed else 0)
EOF
