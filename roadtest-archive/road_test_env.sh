#!/bin/bash

set -euo pipefail
IFS=$' \n\t'

# ----------------------------------------------------------------------------
# road_test_env.sh - configure and persist Apollo test settings (moved)
# ----------------------------------------------------------------------------

# Default config file (stored in tmpfs)
readonly CONFIG_FILE="/tmp/road_test.conf"

APOLLO_WORKSPACE=""
WEBHOOK_URL=""
UUID_TO_CONFIGURE=""

log_info()  { printf "[INFO]    %s\n" "$*"; }
log_error() { printf "[ERROR]   %s\n" "$*" >&2; }

persist_config() {
  cat > "$CONFIG_FILE" <<-EOF
APOLLO_WORKSPACE="$APOLLO_WORKSPACE"
WEBHOOK_URL="$WEBHOOK_URL"
UUID_TO_CONFIGURE="$UUID_TO_CONFIGURE"
EOF
}

load_config() { [[ -r "$CONFIG_FILE" ]] && source "$CONFIG_FILE" || true; }

validate_dir() { [[ -d "$1" ]] || { log_error "Directory not found: $1"; exit 1; } }

validate_url() { [[ "$1" =~ ^https?://[^/]+ ]] || { log_error "Invalid URL: $1"; exit 1; } }

prompt() {
  local var_name="$1"; shift
  local prompt_msg="$*"
  local default_val="${!var_name:-}"
  local input
  if [[ -n "$default_val" ]]; then
    read -rp "$prompt_msg [$default_val]: " input
    input="${input:-$default_val}"
  else
    read -rp "$prompt_msg: " input
  fi
  printf -v "$var_name" '%s' "$input"
}

discover_uuids() { blkid -o export | awk -F= '/^DEVNAME/ {dev=$2} /^UUID/ {print dev":"$2}'; }

step_apollo_workspace() { prompt APOLLO_WORKSPACE "Enter Apollo workspace path"; validate_dir "$APOLLO_WORKSPACE"; }
step_webhook_url()   { prompt WEBHOOK_URL "Enter notification Webhook URL"; validate_url "$WEBHOOK_URL"; }

step_select_uuid() {
  mapfile -t choices < <(discover_uuids)
  [[ ${#choices[@]} -gt 0 ]] || { log_error "No block devices with UUIDs found."; exit 1; }
  log_info "Available filesystems:";
  for i in "${!choices[@]}"; do
    IFS=":" read -r dev uuid <<< "${choices[i]}"
    printf '  %d) %s (UUID: %s)\n' "$((i+1))" "$dev" "$uuid"
  done
  local default_index=""
  if [[ -n "$UUID_TO_CONFIGURE" ]]; then
    for i in "${!choices[@]}"; do [[ "${choices[i]#*:}" == "$UUID_TO_CONFIGURE" ]] && default_index=$((i+1)); done
  fi
  while :; do
    if [[ -n "$default_index" ]]; then
      read -rp "Select an entry [${default_index}]: " sel; sel="${sel:-$default_index}"
    else
      read -rp "Select an entry (1-${#choices[@]}): " sel
    fi
    if [[ "$sel" =~ ^[0-9]+$ ]] && (( sel>=1 && sel<=${#choices[@]} )); then
      UUID_TO_CONFIGURE="${choices[sel-1]#*:}"; break
    fi
    log_error "Invalid selection: $sel"
  done
}

# Execution
load_config; step_apollo_workspace; step_webhook_url; step_select_uuid; persist_config
log_info "Configuration complete."
cat <<-EOF
Apollo Workspace : $APOLLO_WORKSPACE
Webhook URL      : $WEBHOOK_URL
Disk UUID        : $UUID_TO_CONFIGURE
EOF

SERVICE_DIR="/etc/systemd/system"
SERVICE_NAME="road_test_archive"
SERVICE_FILE="${SERVICE_NAME}@.service"
SERVICE_INSTANCE="${SERVICE_NAME}@${UUID_TO_CONFIGURE}.service"

UDEV_RULES_DIR="/etc/udev/rules.d"
SCRIPT_DIR="/usr/local/bin"
ARCHIVE_BASE_DIR="/mnt"

UDEV_RULE_FILE="99-roadtest.rules"
SCRIPT_FILE="${SERVICE_NAME}.sh"
ENV_DIR="/etc/road_test_archive"

REQUIRED_CMDS=(rsync jq curl logger flock mountpoint mount udevadm systemctl)

SETUP_HOST_BASEDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SCRIPTS_SOURCE_DIR="$SETUP_HOST_BASEDIR/scripts"
SYSTEMD_SOURCE_DIR="$SETUP_HOST_BASEDIR/etc/systemd/system"
UDEV_SOURCE_DIR="$SETUP_HOST_BASEDIR/etc/udev/rules.d"

check_root() { [[ "$EUID" -ne 0 ]] && { log_error "This script must be run as root or with sudo."; exit 1; } }

create_directories() {
  log_info "Creating necessary directories..."
  mkdir -p "$SERVICE_DIR" "$UDEV_RULES_DIR" "$SCRIPT_DIR" "$ARCHIVE_BASE_DIR" "$ENV_DIR"
  chown root:root "$ARCHIVE_BASE_DIR" || { log_error "Failed to set ownership on $ARCHIVE_BASE_DIR."; exit 1; }
}

copy_files() {
  log_info "Copying configuration files..."
  install -m 0755 "$SCRIPTS_SOURCE_DIR/$SCRIPT_FILE" "$SCRIPT_DIR/" || { log_error "Failed to install $SCRIPT_FILE to $SCRIPT_DIR."; exit 1; }
  install -m 0644 "$SYSTEMD_SOURCE_DIR/$SERVICE_FILE" "$SERVICE_DIR/" || { log_error "Failed to install $SERVICE_FILE to $SERVICE_DIR."; exit 1; }
  install -m 0644 "$UDEV_SOURCE_DIR/$UDEV_RULE_FILE" "$UDEV_RULES_DIR/" || { log_error "Failed to install $UDEV_RULE_FILE to $UDEV_RULES_DIR."; exit 1; }
}

set_permissions() { log_info "Setting file permissions..."; chmod 0755 "$SCRIPT_DIR/$SCRIPT_FILE" || { log_error "Failed to set execute permissions"; exit 1; } }

check_deps() { local miss=0; for cmd in "${REQUIRED_CMDS[@]}"; do command -v "$cmd" >/dev/null 2>&1 || { log_error "Required command missing: $cmd"; miss=1; }; done; [[ $miss -eq 0 ]] || { log_error "Install dependencies and re-run installer."; exit 1; } }

create_env_file() {
  local uuid="$1"; local target="$ENV_DIR/${uuid}.env"
  log_info "Creating environment file for instance: $target"
  mkdir -p "$(dirname "$target")"
  cat > "$target" <<-EOF
APOLLO_WORKSPACE="$APOLLO_WORKSPACE"
WEBHOOK_URL="$WEBHOOK_URL"
ARCHIVE_BASE_DIR="$ARCHIVE_BASE_DIR"
EOF
  chmod 0640 "$target"
}

modify_service_file() { log_info "Modifying service file..."; create_env_file "$UUID_TO_CONFIGURE"; }

modify_udev_rules_file() { log_info "Modifying udev rules file..."; chmod 0644 "$UDEV_RULES_DIR/$UDEV_RULE_FILE" || true; }

update_udev_and_systemd() { log_info "Updating udev rules and systemd configuration..."; udevadm control --reload-rules || log_error "Failed to reload udev rules."; udevadm trigger || log_error "Failed to trigger udev events."; systemctl daemon-reload || log_error "Failed to reload systemd daemon."; }

enable_and_start_service() { log_info "Enabling and starting the service for UUID $UUID_TO_CONFIGURE..."; systemctl enable "$SERVICE_INSTANCE" || log_error "Failed to enable service $SERVICE_INSTANCE."; systemctl start "$SERVICE_INSTANCE" || log_error "Failed to start service $SERVICE_INSTANCE."; }

# main
check_root
check_deps
create_directories
copy_files
set_permissions
modify_service_file
modify_udev_rules_file
update_udev_and_systemd
enable_and_start_service

log_info "Road test archive configuration completed for UUID $UUID_TO_CONFIGURE."
log_info "Checking service status..."
systemctl status "$SERVICE_INSTANCE"
