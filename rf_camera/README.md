# rf_camera

| File | Purpose |
|---|---|
| `record_cameras.sh` | Record all 8 cameras (GStreamer, MJPEG or raw) |
| `trigger.sh` | Start / stop the camera trigger, check GPS / PPS status |
| `list_camera_formats.sh` | Open `/dev/video0-7` permissions and list formats |

## 1. Check the cameras

```bash
./list_camera_formats.sh
```

This runs `sudo chmod 777` on `/dev/video0-7` (lost on reboot) and prints
each camera's formats. Expect `YUYV`; the driver reports 1920x1084.

## 2. Record

```bash
./record_cameras.sh                # record until Ctrl-C
./record_cameras.sh -d 60          # record 60 seconds
./record_cameras.sh -c raw         # uncompressed YUY2 instead of MJPEG
./record_cameras.sh -g             # trigger from GPS PPS (needs a GPS fix)
./record_cameras.sh -o /data/rec   # output root (default ./camera_records)
```

## 3. Trigger and GPS

Use `trigger.sh` to control it by hand, e.g. with another capture tool or
to clean up after a crash:

```bash
./trigger.sh status                # GPS time / PPS valid?
./trigger.sh start                 # all 8 cameras, 10 fps, FPGA PPS
./trigger.sh start -g              # use GPS PPS
./trigger.sh start /dev/video0     # one camera
./trigger.sh stop                  # all 8 cameras
TRIGGER_FPS=20 ./trigger.sh start  # other frame rate (1-30)
```
