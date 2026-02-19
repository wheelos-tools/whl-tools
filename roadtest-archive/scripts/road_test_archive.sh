#!/usr/bin/env bash

# road_test_archive.sh - robust archival runner (copied into roadtest-archive)

set -euo pipefail
IFS=$'\n\t '

LOG_TAG="road-test-archive"
ARCHIVE_DIRECTORIES=("log" "bag" "core")
LOCK_FILE="/var/lock/$(basename "$0").lock"

readonly CMD_DEPENDS=(rsync curl logger flock mountpoint mount umount)

log() {
    local msg="$1"; local t="${2:-}"
    local ts; ts=$(date +'%Y-%m-%d %H:%M:%S')
    local line="[${ts}] [${LOG_TAG}] ${msg}"
    echo "${line}"
    logger -t "${LOG_TAG}" "${msg}" || true
    if [[ "${t}" == "local" && -n "${LOCAL_LOG_FILE:-}" ]]; then
        echo "${line}" >> "${LOCAL_LOG_FILE}" || true
    fi
}

check_deps() { local miss=0; for c in "${CMD_DEPENDS[@]}"; do command -v "$c" >/dev/null 2>&1 || { log "Missing dependency: $c"; miss=1; }; done; [[ $miss -eq 0 ]] || exit 1; }

cleanup() {
    local code=${1:-$?}
    if [[ $code -ne 0 ]]; then log "Script failed with exit code ${code}"; else log "Script completed successfully"; fi
    if [[ -n "${FD_OPEN:-}" ]]; then flock -u 200 || true; fi
    rm -f "${LOCK_FILE}" 2>/dev/null || true
}
trap 'cleanup $?' EXIT

acquire_lock() { mkdir -p "$(dirname "$LOCK_FILE")"; exec 200>"${LOCK_FILE}"; FD_OPEN=1; flock -n 200 || { log "Another instance is running (lock: ${LOCK_FILE})"; exit 1; }; log "Lock acquired"; }

validate_env() { [[ -n "${APOLLO_WORKSPACE:-}" ]] || { log "APOLLO_WORKSPACE not set"; exit 1; }; [[ -n "${DEVICE_UUID:-}" ]] || { log "DEVICE_UUID not set"; exit 1; }; [[ -n "${WEBHOOK_URL:-}" ]] || { log "WEBHOOK_URL not set"; exit 1; }; }

main_mount_point_and_paths() { ARCHIVE_BASE_DIR="${ARCHIVE_BASE_DIR:-${APOLLO_WORKSPACE}/mnt}"; MOUNT_POINT="${ARCHIVE_BASE_DIR}/${DEVICE_UUID}"; DEVICE_PATH="/dev/disk/by-uuid/${DEVICE_UUID}"; ARCHIVE_BASE="${APOLLO_WORKSPACE}/data"; LOCAL_LOG_FILE="${MOUNT_POINT}/archive.log"; }

ensure_mount_point() { [[ -d "${MOUNT_POINT}" ]] || { log "Creating mount point ${MOUNT_POINT}" "local"; mkdir -p "${MOUNT_POINT}" || { log "Failed to create mount point"; exit 1; }; }; }

mount_device() { [[ -e "${DEVICE_PATH}" ]] || { log "Device node not found: ${DEVICE_PATH}"; exit 1; }; if ! mountpoint -q "${MOUNT_POINT}"; then log "Mounting ${DEVICE_PATH} -> ${MOUNT_POINT}" "local"; if mount "${DEVICE_PATH}" "${MOUNT_POINT}"; then DID_MOUNT=true; log "Mounted ${DEVICE_PATH}" "local"; else log "Mount failed"; exit 1; fi; else log "Already mounted: ${MOUNT_POINT}" "local"; fi; }

unmount_device() { if [[ "${DID_MOUNT:-false}" == true ]]; then log "Attempting to unmount ${MOUNT_POINT}" "local"; if umount "${MOUNT_POINT}"; then log "Unmount succeeded" "local"; else log "Unmount failed" "local"; fi; else log "Not unmounting (not mounted by this script)" "local"; fi; }

archive_data() {
    START_TS=$(date +'%Y-%m-%dT%H:%M:%S')
    local ts target_dir failed=0
    ts=$(date +'%Y-%m-%d_%H-%M-%S')
    target_dir="${MOUNT_POINT}/${ts}"
    log "Creating target ${target_dir}" "local"
    mkdir -p "${target_dir}" || return 1
    for d in "${ARCHIVE_DIRECTORIES[@]}"; do
        local src="${ARCHIVE_BASE}/${d}"
        if [[ -d "${src}" ]]; then
            log "Sync: ${src} -> ${target_dir}/${d}" "local"
            rsync -aHAX --delete --info=progress2 "${src}/" "${target_dir}/${d}/" 2>&1 | while IFS= read -r line; do log "    ${line}" "local"; done || failed=1
        else
            log "Source missing: ${src}" "local"
        fi
    done
    sync
    END_TS=$(date +'%Y-%m-%dT%H:%M:%S')
    log "Archive finished: ${target_dir}" "local"
    return $failed
}

send_notification() {
    local status="$1"
    local text="Archive Status: ${status}\nStart Time: ${START_TS:-}\nEnd Time: ${END_TS:-}\nDevice: ${DEVICE_UUID:-}"
    if ! command -v jq >/dev/null 2>&1; then log "jq not installed; skipping JSON payload construction"; return 0; fi
    local payload
    payload=$(jq -n --arg msg_type "text" --arg text "$text" '{msg_type: $msg_type, content: {text: $text}}')
    if curl -s --max-time 30 --retry 3 -X POST -H "Content-Type: application/json" -d "$payload" "$WEBHOOK_URL"; then log "Notification sent: ${status}"; else log "Notification failed"; fi
}

main() { check_deps; validate_env; acquire_lock; main_mount_point_and_paths; ensure_mount_point; DID_MOUNT=false; mount_device; if archive_data; then log "Archive succeeded"; send_notification "success"; else log "Archive failed"; send_notification "fail"; exit 1; fi; unmount_device; }

main
