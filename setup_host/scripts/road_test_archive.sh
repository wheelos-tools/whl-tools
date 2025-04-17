#!/bin/bash

# ------------------------------------------------------------------------------
# Description: Archive data when device plugged; designed to be run via systemd
# Author: daohu527
# Date: 2025-04-17
# Version: 2.0 (Optimized)
# ------------------------------------------------------------------------------

set -euo pipefail

# Set the internal field separator to handle filenames containing spaces, tabs, or newlines.
IFS=$'\n\t '

check_env_vars() {
    if [[ ! -v WORKSPACE || -z "${WORKSPACE}" ]]; then
        echo "Error: WORKSPACE environment variable missing or empty."
        exit 1
    fi

    if [[ ! -v DEVICE_UUID || -z "${DEVICE_UUID}" ]]; then
        echo "Error: DEVICE_UUID environment variable missing or empty."
        exit 1
    fi

    echo "WORKSPACE : ${WORKSPACE}"
    echo "DEVICE_UUID : ${DEVICE_UUID}"
}

# Define readonly constants
readonly MOUNT_POINT="${ARCHIVE_BASE_DIR}/road_test"
readonly DEVICE_PATH="/dev/disk/by-uuid/${DEVICE_UUID}"
readonly ARCHIVE_BASE="${WORKSPACE}/data"
readonly LOG_TAG="road-test-archive"
readonly ARCHIVE_DIRECTORIES=("log" "bag" "core")
readonly LOCK_FILE="/var/lock/$(basename "$0").lock" # More explicit lock file path definition

# Define the log function to output to stdout, syslog, and a local file, including a timestamp.
log() {
    local msg="$1"
    local log_type="${2:-}" # Optional log type (e.g., "local")
    local timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    local log_line="[${timestamp}] [${LOG_TAG}] ${msg}"

    echo "${log_line}" # Output to stdout
    logger -t "${LOG_TAG}" "${msg}" # Output to syslog

    if [[ "${log_type}" == "local" && -v LOCAL_LOG_FILE ]]; then
        echo "${log_line}" >> "${LOCAL_LOG_FILE}"
    fi
}

# Define the cleanup function to be executed upon script exit, recording success or failure.
cleanup() {
    local code=$?
    if [[ $code -ne 0 ]]; then
        log "⚠️ Script failed with exit code ${code}"
    else
        log "✅ Script completed successfully"
    fi
    # Attempt to release the lock regardless of success or failure.
    flock -u 200
    rm -f "${LOCK_FILE}" 2>/dev/null # Remove the lock file
}
# Use the trap command to call the cleanup function upon script exit (including abnormal exits).
trap cleanup EXIT

# Acquire an exclusive lock to prevent concurrent execution of the script.
acquire_lock() {
    # Open the lock file with file descriptor 200; create it if it doesn't exist.
    exec 200>"${LOCK_FILE}"
    # Attempt to acquire the lock; if it cannot be acquired immediately (-n), output an error message and exit.
    flock -n 200 || { log "❌ Another run is in progress (lock file: ${LOCK_FILE})"; exit 1; }
    log "🔒 Lock acquired (lock file: ${LOCK_FILE})"
}

# Ensure the mount point directory exists.
ensure_mount_point() {
    if [[ ! -d "${MOUNT_POINT}" ]]; then
        log "📂 Mount point directory '${MOUNT_POINT}' does not exist, creating it."
        mkdir -p "${MOUNT_POINT}"
        if [[ $? -ne 0 ]]; then
            log "❌ Failed to create mount point directory '${MOUNT_POINT}'"
            exit 1
        fi
    fi
}

# Mount the device.
mount_device() {
    # Check if the device path exists.
    if [[ ! -b "${DEVICE_PATH}" ]]; then
        log "⚠️ Device path '${DEVICE_PATH}' does not exist. Please check the device UUID."
        exit 1
    fi

    # Check if the device is already mounted.
    if ! mountpoint -q "${MOUNT_POINT}"; then
        log "🔗 Mounting device '${DEVICE_PATH}' to '${MOUNT_POINT}'"
        mount "${DEVICE_PATH}" "${MOUNT_POINT}"
        if [[ $? -ne 0 ]]; then
            log "❌ Failed to mount device '${DEVICE_PATH}' to '${MOUNT_POINT}'"
            exit 1
        fi
    else
        log "ℹ️ Device '${DEVICE_PATH}' is already mounted on '${MOUNT_POINT}'"
    fi
}

# Archive data.
archive_data() {
    local ts target_dir
    ts=$(date +'%Y-%m-%d_%H-%M-%S')
    target_dir="${MOUNT_POINT}/${ts}"
    readonly LOCAL_LOG_FILE="${target_dir}/archive.log"

    log "📂 Creating archive directory: '${target_dir}'" "local"
    mkdir -p "${target_dir}"
    if [[ $? -ne 0 ]]; then
        log "❌ Failed to create archive directory: '${target_dir}'"
        exit 1
    fi

    log "📂 Archiving data to: '${target_dir}'" "local"

    for d in "${ARCHIVE_DIRECTORIES[@]}"; do
        local src="${ARCHIVE_BASE}/${d}"
        if [[ -d "${src}" ]]; then
            log "☁️ Syncing directory: '${src}' → '${target_dir}/${d}'" "local"
            rsync -rpt --copy-links --no-o --no-g --no-p \
                  --delete --progress --stats "${src}/" "${target_dir}/${d}/" | while IFS= read -r line; do
                log "    ${line}" "local" # Indent to display rsync output
            done
            if [[ $? -ne 0 ]]; then
                log "⚠️ Failed to sync directory: '${src}'" "local"
            fi
        else
            log "⚠️ Source directory missing: '${src}'" "local"
        fi
    done

    log "🔄 Flushing disk buffers" "local"
    sync

    # Log the completion to the local file as well.
    log "✅ Archive process completed for directory: '${target_dir}'" "local"
}

# Main function
main() {
    check_env_vars
    acquire_lock
    ensure_mount_point
    mount_device
    archive_data
    # NOTE: We still skip auto-unmounting here to avoid accidental "force unplug" behavior.
    log "ℹ️ Leaving device mounted; unmount manually when appropriate."
}

# Call the main function and pass all arguments.
main "$@"
