# rf_camera

| File | Purpose |
|---|---|
| `record_cameras.sh` | Record selected cameras in rolling segments (GStreamer, MJPEG or raw) |
| `trigger.sh` | Start / stop the camera trigger, check GPS / PPS status |
| `list_camera_formats.sh` | Open `/dev/video0-8` permissions and list formats |

## 1. Check the cameras

```bash
./list_camera_formats.sh
```

This runs `sudo chmod 777` on `/dev/video0-8` (lost on reboot) and prints
each camera's formats. Expect `YUYV`; the driver reports 1920x1084.

## 2. Record

```bash
./record_cameras.sh                # cameras 1,2,3,4,5,8 until Ctrl-C
./record_cameras.sh -C 0-8         # pick cameras, e.g. 0,1,6 or 0-5
./record_cameras.sh -d 60          # record 60 seconds
./record_cameras.sh -s 600 -r 10   # 10 min segments, stop at 10 GB free
./record_cameras.sh -c raw         # uncompressed YUY2 instead of MJPEG
./record_cameras.sh -g             # trigger from GPS PPS (needs a GPS fix)
./record_cameras.sh -o /data/rec   # output root (default ./camera_records)
```

| Opt | Default | Meaning |
|---|---|---|
| `-C` | `1,2,3,4,5,8` | cameras to record; only these are opened and triggered |
| `-s` | `300` | segment length in seconds |
| `-r` | `5` | stop cleanly when free disk space falls below N GB |
| `-f` | `10` | trigger fps (1-30) |
| `-q` | `85` | JPEG quality |

Output `<root>/<YYYYmmdd_HHMMSS>/`: `videoN/videoN_00000.mkv ...`,
`timestamps.csv`, `record.log`. A status line (fps, drops, write rate,
free space) is printed every 30 s.

Stop with **Ctrl-C** or `kill -INT`: the last segments are finalized and
the trigger is turned off. For long drives run it inside `tmux` so an SSH
drop doesn't kill it. Don't use `kill -9` (the trigger stays on; run
`./trigger.sh stop`).

## 3. Trigger and GPS

Use `trigger.sh` to control it by hand, e.g. with another capture tool or
to clean up after a crash:

```bash
./trigger.sh status                # GPS time / PPS valid?
./trigger.sh start                 # all 9 cameras, 10 fps, FPGA PPS
./trigger.sh start -g              # use GPS PPS
./trigger.sh start /dev/video0     # one camera
./trigger.sh stop                  # all 9 cameras
TRIGGER_FPS=20 ./trigger.sh start  # other frame rate (1-30)
```
