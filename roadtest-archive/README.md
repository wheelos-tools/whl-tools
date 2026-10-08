Roadtest Archive (moved from setup_host)

This folder contains the installer, systemd template, udev rule and runtime
script for automatically archiving data to removable devices.

Key files
- `road_test_env.sh` - interactive installer (creates `/etc/road_test_archive/<UUID>.env`, installs unit and udev rule)
- `scripts/road_test_archive.sh` - runtime archival script (invoked by systemd)
- `etc/systemd/system/road_test_archive@.service` - systemd template
- `etc/udev/rules.d/99-roadtest.rules` - udev rule that triggers on device add

Smoke test
- A smoke-test helper is provided under `test/smoke_test.sh`. Run as root from
  the repository root (it will create a temporary workspace and mock required
  system binaries to exercise the archive script without real mounts):

```bash
sudo bash roadtest-archive/test/smoke_test.sh
```

Installation
- Run the interactive installer as root:

```bash
sudo bash roadtest-archive/road_test_env.sh
```
