#!/bin/bash

# ------------------------------- config -------------------------------
UUID_TO_CONFIGURE="76C8-9244"
APOLLO_WORKSPACE="/home/zero/01code/apollo"

USER=$(whoami)
GROUP=$(id -g -n)

SERVICE_NAME="road-test-archive"
SERVICE_FILE="${SERVICE_NAME}@.service"
SERVICE_INSTANCE="${SERVICE_NAME}@${UUID_TO_CONFIGURE}.service"

SERVICE_DIR="/etc/systemd/system"
UDEV_RULES_DIR="/etc/udev/rules.d"
SCRIPT_DIR="/usr/local/bin"
ARCHIVE_BASE_DIR="/mnt"

UDEV_RULE_FILE="99-roadtest.rules"
SCRIPT_FILE="${SERVICE_NAME}.sh"

SETUP_HOST_BASEDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
SCRIPTS_SOURCE_DIR="$SETUP_HOST_BASEDIR/scripts"
SYSTEMD_SOURCE_DIR="$SETUP_HOST_BASEDIR/etc/systemd/system"
UDEV_SOURCE_DIR="$SETUP_HOST_BASEDIR/etc/udev/rules.d"

# ------------------------------- function -------------------------------

log_info() {
  echo "[INFO] $1"
}

log_error() {
  echo "[ERROR] $1" >&2
}

check_root() {
  if [[ "$EUID" -ne 0 ]]; then
    log_error "This script must be run as root or with sudo."
    exit 1
  fi
}

create_directories() {
  log_info "Creating necessary directories..."
  mkdir -p "$SERVICE_DIR" "$UDEV_RULES_DIR" "$SCRIPT_DIR" "$ARCHIVE_BASE_DIR"
  chown "$USER":"$GROUP" "$ARCHIVE_BASE_DIR" || {
    log_error "Failed to set ownership on $ARCHIVE_BASE_DIR."
    exit 1
  }
}

copy_files() {
  log_info "Copying configuration files..."
  cp "$SCRIPTS_SOURCE_DIR/$SCRIPT_FILE" "$SCRIPT_DIR/" || {
    log_error "Failed to copy $SCRIPT_FILE to $SCRIPT_DIR."
    exit 1
  }
  cp "$SYSTEMD_SOURCE_DIR/$SERVICE_FILE" "$SERVICE_DIR/" || {
    log_error "Failed to copy $SERVICE_FILE to $SERVICE_DIR."
    exit 1
  }
  cp "$UDEV_SOURCE_DIR/$UDEV_RULE_FILE" "$UDEV_RULES_DIR/" || {
    log_error "Failed to copy $UDEV_RULE_FILE to $UDEV_RULES_DIR."
    exit 1
  }
}

set_permissions() {
  log_info "Setting file permissions..."
  chmod +x "$SCRIPT_DIR/$SCRIPT_FILE" || {
    log_error "Failed to set execute permissions on $SCRIPT_DIR/$SCRIPT_FILE."
    exit 1
  }
}

modify_service_file() {
  log_info "Modifying service file..."
  sed -i "s/your_user/$USER/g" "$SERVICE_DIR/$SERVICE_FILE" || {
    log_error "Failed to replace 'your_user' in $SERVICE_DIR/$SERVICE_FILE."
    exit 1
  }
  sed -i "s/your_group/$GROUP/g" "$SERVICE_DIR/$SERVICE_FILE" || {
    log_error "Failed to replace 'your_group' in $SERVICE_DIR/$SERVICE_FILE."
    exit 1
  }
  grep -q "^Environment=APOLLO_WORKSPACE=" "$SERVICE_DIR/$SERVICE_FILE" || echo "Environment=APOLLO_WORKSPACE=\"$APOLLO_WORKSPACE\"" >> "$SERVICE_DIR/$SERVICE_FILE" || {
    log_error "Failed to add APOLLO_WORKSPACE environment variable to $SERVICE_DIR/$SERVICE_FILE."
    exit 1
  }
}

modify_udev_rules_file() {
  log_info "Modifying udev rules file..."
  sed -i "s/UUID_TO_CONFIGURE/$UUID_TO_CONFIGURE/g" "$UDEV_RULES_DIR/$UDEV_RULE_FILE" || {
    log_error "Failed to replace UUID in $UDEV_RULES_DIR/$UDEV_RULE_FILE."
    exit 1
  }
  sed -i "s/road-test-archive@.service/$SERVICE_NAME@.service/g" "$UDEV_RULES_DIR/$UDEV_RULE_FILE" || {
    log_error "Failed to replace service name in $UDEV_RULES_DIR/$UDEV_RULE_FILE."
    exit 1
  }
}

update_udev_and_systemd() {
  log_info "Updating udev rules and systemd configuration..."
  udevadm control --reload-rules || log_error "Failed to reload udev rules."
  udevadm trigger || log_error "Failed to trigger udev events."
  systemctl daemon-reload || log_error "Failed to reload systemd daemon."
}

enable_and_start_service() {
  log_info "Enabling and starting the service for UUID $UUID_TO_CONFIGURE..."
  systemctl enable "$SERVICE_INSTANCE" || log_error "Failed to enable service $SERVICE_INSTANCE."
  systemctl start "$SERVICE_INSTANCE" || log_error "Failed to start service $SERVICE_INSTANCE."
}

# ------------------------------- main -------------------------------

check_root

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
