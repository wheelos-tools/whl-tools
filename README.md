# whl-tools Collection

This repository includes the following tools:

- [http-server](#http-server)
- [Automated Data Copy Tool (roadtest-archive)](#automated-data-copy-tool-roadtest-archive)

---

## Http Server

Provides a simple HTTP server used by developer tooling and local testing.

### Quick Start

From the repository root:

```bash
cd http-server
./manage.sh up
```

See `http-server/README.md` for more details about the server and docker
options.

---

## Automated Data Copy Tool (roadtest-archive)

This component (now in `roadtest-archive/`) installs a udev rule and a
systemd template to automatically archive data from an Apollo workspace to a
removable device when it is plugged in. It creates a per-instance environment
file under `/etc/road_test_archive/<UUID>.env` so each device instance gets the
correct configuration.

### Quick Start (install)

Run the interactive installer as root:

```bash
sudo bash roadtest-archive/road_test_env.sh
```

The installer will:

- check required commands (`rsync`, `curl`, `logger`, `flock`, `mountpoint`, `mount`, `udevadm`, `systemctl`)
- install the runtime script to `/usr/local/bin/road_test_archive.sh`
- install the systemd unit to `/etc/systemd/system/road_test_archive@.service`
- install the udev rule to `/etc/udev/rules.d/99-roadtest.rules`
- create `/etc/road_test_archive/<UUID>.env` and enable the per-UUID unit

### Runtime/example

Run the installer and follow prompts. Example interactive output:

```shell
$ sudo bash roadtest-archive/road_test_env.sh
Enter Apollo workspace path [/home/zero/01code/apollo]:
Enter notification Webhook URL [https://www.feishu.cn/flow/api/trigger-webhook/xxx]:
[INFO]    Available filesystems:
  1) /dev/sdb1 (UUID: 0123-ABCD)
  2) /dev/sdc1 (UUID: 9f8e7d6c-...)
Select an entry [1]:
[INFO]    Configuration complete.
Apollo Workspace : /home/zero/01code/apollo
Webhook URL      : https://www.feishu.cn/flow/api/trigger-webhook/xxx
Disk UUID        : 0123-ABCD
```

🔗 [How to Create a Feishu Webhook](https://www.feishu.cn/hc/zh-CN/articles/807992406756-webhook-%E8%A7%A6%E5%8F%91%E5%99%A8)
