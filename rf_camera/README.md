# rf_camera

Record the 8 vehicle cameras (`/dev/video0-7`, basa / FPD-Link driver) at
the same time with GStreamer, on the host outside the Apollo container.

Tested on `apollo@192.168.10.6` (Ubuntu 18.04 x86_64, GStreamer 1.14).

| File | Purpose |
|---|---|
| `record_cameras.sh` | Record all 8 cameras (GStreamer, MJPEG or raw) |
| `trigger.sh` | Start / stop the camera trigger, check GPS / PPS status |
| `list_camera_formats.sh` | Open `/dev/video0-7` permissions and list formats |

## Requirements

On the vehicle host:

- `gstreamer1.0-plugins-good`, `python3-gi`, `gir1.2-gstreamer-1.0`
- `v4l-utils` (for `list_camera_formats.sh`)
- `libadv_trigger.so`, default
  `/opt/apollo/pkgs/pkgs/adv_plat/lib/libadv_trigger.so`.
  Override with `ADV_TRIGGER_LIB=/path/to/libadv_trigger.so`.

Copy the scripts over:

```bash
scp rf_camera/*.sh apollo@192.168.10.6:/home/apollo/01code/camera_test/
```

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

The script turns the trigger on by itself and turns it off when it stops.
Stop it with **Ctrl-C** (or `-d`). The files are closed properly and the
trigger is disabled. Don't use `kill -9`: the trigger stays on
(see `trigger.sh stop` below).

Output `./camera_records/<YYYYmmdd_HHMMSS>/`:

- `video0.mkv` ... `video7.mkv`: one file per camera, 10 fps
- `timestamps.csv`: `camera,frame,pts_ns,wall_time` for every frame

The driver doesn't provide frame timestamps. Each frame is stamped with
its arrival time on a pipeline clock shared by all 8 cameras, so `pts_ns` /
`wall_time` can be compared across cameras (they match within ~3.5 ms).
The first ~2 s have no frames: streaming starts first and the trigger is
enabled after it.

Disk use (the vehicle had 24 GB free):

| Codec | Per camera | All 8 | 24 GB lasts |
|---|---|---|---|
| `jpeg` (default) | ~1.5-3 MB/s | ~17 MB/s | ~23 min |
| `raw` | ~42 MB/s | ~330 MB/s | ~70 s |

Copy a recording to your machine:

```bash
scp -r apollo@192.168.10.6:/home/apollo/01code/camera_test/camera_records/<dir> .
```

## 3. Trigger and GPS

The cameras only send frames while the FPGA trigger is on. The trigger
must be enabled **after** the video stream is opened (`STREAMON`). Turning
it on first gives no frames. `record_cameras.sh` already does this.

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

The trigger is paced by a PPS (pulse-per-second) source:

- **FPGA internal PPS** (default, `trigger_internal 1`): always works.
- **GPS PPS** (`-g`, `trigger_internal 0`, the Apollo config default):
  gives **no frames** while the GPS has no fix. Check first:

  ```bash
  ./trigger.sh status
  # device basa0-...  GPS time: NOT valid  PPS: valid
  ```

  Use `-g` only when `GPS time` shows `valid`. "PPS: valid" alone was
  not enough in testing. The kernel log shows the same:
  `dmesg | grep basa` prints `zynq_get_gps_time: GPS time is not valid`
  without a fix, and `zvideo_trigger_enable/disable` for each change.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `WARN: no frames from /dev/videoN` | Trigger not running: check `-g` / GPS fix, `dmesg \| grep basa` |
| `cannot read /dev/videoN` | Run `./list_camera_formats.sh` |
| Cameras busy | Apollo camera driver may be running: stop it first |
| Trigger left on after crash | `./trigger.sh stop` |
