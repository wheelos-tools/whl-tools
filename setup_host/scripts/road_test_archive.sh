#!/bin/bash

# ------------------------------------------------------------------------------
# Description: Archive data when device is plugged in; intended for systemd
# Author: daohu527
# Date: 2025-04-17
# Version: 2.1 (Refined)
# ------------------------------------------------------------------------------

set -euo pipefail
IFS=$'\n\t '

check_env_vars() {
    # WORKSPACE is expected to be set as an environment variable
    if [[ ! -v WORKSPACE || -z "${WORKSPACE}" ]]; then
        echo "Error: WORKSPACE environment variable is missing or empty."
        exit 1
    fi
    # DEVICE_UUID is passed via udev environment variables when the device is plugged in
    if [[ ! -v DEVICE_UUID || -z "${DEVICE_UUID}" ]]; then
        echo "Error: DEVICE_UUID environment variable is missing or empty."
        exit 1
    fi
    # WEBHOOK_URL is passed via service environment variables
    if [[ ! -v WEBHOOK_URL || -z "${WEBHOOK_URL}" ]]; then
        echo "Error: WEBHOOK_URL environment variable is missing or empty."
        exit 1
    fi

    : "${ARCHIVE_BASE_DIR:=${WORKSPACE}/mnt}"

    echo "WORKSPACE: ${WORKSPACE}"
    echo "DEVICE_UUID: ${DEVICE_UUID}"
    echo "ARCHIVE_BASE_DIR: ${ARCHIVE_BASE_DIR}"
}

readonly LOG_TAG="road-test-archive"
readonly ARCHIVE_DIRECTORIES=("log" "bag" "core")
readonly LOCK_FILE="/var/lock/$(basename "$0").lock"

readonly MOUNT_POINT="${ARCHIVE_BASE_DIR}/road_test"
readonly DEVICE_PATH="/dev/disk/by-uuid/${DEVICE_UUID}"
readonly ARCHIVE_BASE="${WORKSPACE}/data"

DID_MOUNT=false
START_TS=""
END_TS=""
LOCAL_LOG_FILE=""

log() {
    local msg="$1"
    local log_type="${2:-}"
    local timestamp
    timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    local log_line="[${timestamp}] [${LOG_TAG}] ${msg}"

    echo "${log_line}"
    logger -t "${LOG_TAG}" "${msg}"

    if [[ "${log_type}" == "local" && -n "${LOCAL_LOG_FILE:-}" ]]; then
        echo "${log_line}" >> "${LOCAL_LOG_FILE}"
    fi
}

cleanup() {
    local code=$?
    if [[ $code -ne 0 ]]; then
        log "Script failed with exit code ${code}"
    else
        log "Script completed successfully"
    fi
    flock -u 200
    rm -f "${LOCK_FILE}" 2>/dev/null
}
trap cleanup EXIT

acquire_lock() {
    exec 200>"${LOCK_FILE}"
    flock -n 200 || { log "Another instance is already running (lock: ${LOCK_FILE})"; exit 1; }
    log "Lock acquired"
}

ensure_mount_point() {
    if [[ ! -d "${MOUNT_POINT}" ]]; then
        log "Creating mount point: ${MOUNT_POINT}"
        mkdir -p "${MOUNT_POINT}" || {
            log "Failed to create mount point: ${MOUNT_POINT}"
            exit 1
        }
    fi
}

mount_device() {
    if [[ ! -b "${DEVICE_PATH}" ]]; then
        log "Device not found: ${DEVICE_PATH}"
        exit 1
    fi

    if ! mountpoint -q "${MOUNT_POINT}"; then
        log "Mounting ${DEVICE_PATH} to ${MOUNT_POINT}"
        if mount "${DEVICE_PATH}" "${MOUNT_POINT}"; then
            DID_MOUNT=true
        else
            log "Mount failed"
            exit 1
        fi
    else
        log "Device already mounted"
    fi
}

unmount_device() {
    if [[ "${DID_MOUNT}" == true ]]; then
        log "Unmounting device"
        if umount "$MOUNT_POINT"; then
            log "Device unmounted"
        else
            log "Failed to unmount device"
        fi
    else
        log "Device was not mounted by this script"
    fi
}

archive_data() {
    START_TS=$(date +'%Y-%m-%dT%H:%M:%S')
    local ts target_dir failed=0
    ts=$(date +'%Y-%m-%d_%H-%M-%S')
    target_dir="${MOUNT_POINT}/${ts}"
    LOCAL_LOG_FILE="${target_dir}/archive.log"

    log "Creating archive directory: ${target_dir}" "local"
    mkdir -p "${target_dir}" || return 1

    log "Archiving data to: ${target_dir}" "local"

    for d in "${ARCHIVE_DIRECTORIES[@]}"; do
        local src="${ARCHIVE_BASE}/${d}"
        if [[ -d "${src}" ]]; then
            log "Syncing ${src} → ${target_dir}/${d}" "local"
            rsync -rpt --copy-links --no-o --no-g --no-p \
                  --delete --progress --stats "${src}/" "${target_dir}/${d}/" | while IFS= read -r line; do
                log "    ${line}" "local"
            done || failed=1
        else
            log "Source missing: ${src}" "local"
        fi
    done

    sync
    END_TS=$(date +'%Y-%m-%dT%H:%M:%S')
    log "Archive completed: ${target_dir}" "local"
    return $failed
}

send_notification() {
    local status="$1"
    local text="Archive Status: ${status}\nStart Time: ${START_TS}\nEnd Time: ${END_TS}"
    local payload

    payload=$(jq -n \
        --arg msg_type "text" \
        --arg text "$text" \
        '{msg_type: $msg_type, content: {text: $text}}'
    )

    if ! curl -s -X POST -H "Content-Type: application/json" -d "${payload}" "${WEBHOOK_URL}"; then
        log "Failed to send notification"
    else
        log "Notification sent: ${status}"
    fi
}

main() {
    check_env_vars
    acquire_lock
    ensure_mount_point
    mount_device

    if archive_data; then
        log "Archive succeeded"
        send_notification "success"
    else
        log "Archive failed"
        send_notification "fail"
        exit 1
    fi

    unmount_device
}

main
