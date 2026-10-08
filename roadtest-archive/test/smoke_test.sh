#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "This smoke test must be run as root: sudo $0"
  exit 1
fi

WORKDIR=$(mktemp -d /tmp/roadtest-smoketest.XXXX)
echo "Working dir: $WORKDIR"

# prepare mockbin to intercept mount/umount/mountpoint/rsync/curl/logger/flock
MOCKBIN=$WORKDIR/mockbin
mkdir -p "$MOCKBIN"

cat > "$MOCKBIN/mount" <<'SH'
#!/bin/sh
echo "[mock] mount $@" >&2
exit 0
SH
chmod +x "$MOCKBIN/mount"

cat > "$MOCKBIN/umount" <<'SH'
#!/bin/sh
echo "[mock] umount $@" >&2
exit 0
SH
chmod +x "$MOCKBIN/umount"

cat > "$MOCKBIN/mountpoint" <<'SH'
#!/bin/sh
# Always return "not mounted" (exit 1) so archive script proceeds to mount
exit 1
SH
chmod +x "$MOCKBIN/mountpoint"

cat > "$MOCKBIN/logger" <<'SH'
#!/bin/sh
echo "[mock logger] $@" >&2
exit 0
SH
chmod +x "$MOCKBIN/logger"

cat > "$MOCKBIN/flock" <<'SH'
#!/bin/sh
# Very small mock: accept -n, -u and fd args, no-op
exit 0
SH
chmod +x "$MOCKBIN/flock"

cat > "$MOCKBIN/rsync" <<'SH'
#!/usr/bin/env bash
# Simple rsync mock: copy last-2 => last-1 (source -> dest)
set -e
args=("$@")
len=${#args[@]}
if (( len < 2 )); then exit 1; fi
src="${args[$((len-2))]}"
dst="${args[$((len-1))]}"
# remove trailing slashes
src=${src%/}
dst=${dst%/}
mkdir -p "$dst"
cp -a "$src" "$dst/" || true
echo "[mock rsync] copied $src -> $dst"
exit 0
SH
chmod +x "$MOCKBIN/rsync"

cat > "$MOCKBIN/curl" <<'SH'
#!/bin/sh
echo "[mock] curl $@" >&2
exit 0
SH
chmod +x "$MOCKBIN/curl"

export PATH="$MOCKBIN:$PATH"

# prepare fake workspace
APOLLO_WS="$WORKDIR/apollo_ws"
mkdir -p "$APOLLO_WS/data/log" "$APOLLO_WS/data/bag" "$APOLLO_WS/data/core"
echo "test-log" > "$APOLLO_WS/data/log/sample.txt"
echo "test-bag" > "$APOLLO_WS/data/bag/sample.bag"

DEVICE_UUID="SMOKE-TEST-UUID"
DEVICE_PATH="/dev/disk/by-uuid/${DEVICE_UUID}"
mkdir -p "$(dirname "$DEVICE_PATH")"
touch "$DEVICE_PATH"

export APOLLO_WORKSPACE="$APOLLO_WS"
export DEVICE_UUID="$DEVICE_UUID"
export WEBHOOK_URL="http://127.0.0.1/dummy"

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$SCRIPT_DIR/scripts/road_test_archive.sh"

echo "Running runtime script (mocked) against APOLLO_WORKSPACE=$APOLLO_WS"
bash -x "$SCRIPT" || { echo "smoke test failed"; exit 1; }

echo "Smoke test completed. Cleaning up..."
rm -f "$DEVICE_PATH"
rm -rf "$WORKDIR"

echo "OK"
