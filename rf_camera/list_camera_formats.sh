#!/usr/bin/env bash
# Open up permissions on /dev/video0-8 and list each camera's formats.

for i in {0..8}; do
  dev="/dev/video${i}"
  echo "===== ${dev} ====="
  if [[ ! -e "${dev}" ]]; then
    echo "missing"
    continue
  fi
  sudo chmod 777 "${dev}"
  v4l2-ctl --device="${dev}" --list-formats-ext
done
