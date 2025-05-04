#!/usr/bin/env bash

###############################################################################
# Copyright 2017 The Apollo Authors. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
###############################################################################

set -euo pipefail

TOP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "${TOP_DIR}/scripts/apollo.bashrc"

# --- Constants ---
readonly CHRONY_CONF="/etc/chrony/chrony.conf"
readonly PACKAGE_NAME="chrony"
readonly SERVICE_NAME="chrony"
readonly NTP_POOL_BASE=".pool.ntp.org"

# --- Helper Functions ---

# Check if the script is run by root or a user with sudo privileges
check_sudo() {
  if [[ $EUID -ne 0 ]]; then
    info "You are not running as root. Attempting to use sudo."
    # Check if sudo is available
    if ! command -v sudo >/dev/null; then
      error "sudo command not found. Please run this script as root or install sudo."
      exit 1
    fi
    # Test sudo permissions
    if ! sudo -n true 2>/dev/null; then
      error "You do not have passwordless sudo privileges. Please run this script with 'sudo'."
      exit 1
    fi
  fi
  info "Sudo access verified."
}

# Check if chrony is installed, and install if not
check_chrony_installed() {
  info "Checking if ${PACKAGE_NAME} is installed..."
  if ! command -v chronyd >/dev/null; then # Check for the daemon executable
    warning "${PACKAGE_NAME} is not installed. Attempting to install using apt-get..."
    # Assumes Debian/Ubuntu based system
    if ! sudo apt-get update; then
      error "Failed to run apt-get update. Check your network connection or package sources."
      exit 1
    fi
    if ! sudo apt-get install -y "${PACKAGE_NAME}"; then
      error "Failed to install ${PACKAGE_NAME}. Please install it manually."
      exit 1
    fi
    success "${PACKAGE_NAME} installed successfully."
  else
    success "${PACKAGE_NAME} is already installed."
  fi
}

# Parse command line arguments
parse_args() {
  if [ "$#" -ne 1 ]; then
    usage
    exit 1
  fi
  # Convert region to lowercase and remove leading/trailing whitespace
  REGION="$(echo "$1" | xargs | tr 'A-Z' 'a-z')"

  if [ -z "$REGION" ]; then
      error "Invalid region provided. Region cannot be empty."
      usage
      exit 1
  fi

  info "Region set to ${BOLD}${REGION}${NO_COLOR}"
}

# Configure chrony with the specified regional NTP server by appending to the config file
configure_chrony() {
  info "Configuring ${CHRONY_CONF}..."
  local ntp_server="${REGION}${NTP_POOL_BASE}"

  # Backup existing config
  local backup_file="${CHRONY_CONF}.bak-$(date +%Y%m%d_%H%M%S)"
  info "Backing up existing configuration to ${backup_file}"
  if ! sudo cp "${CHRONY_CONF}" "${backup_file}"; then
    error "Failed to create backup of ${CHRONY_CONF} to ${backup_file}. Aborting configuration."
    exit 1
  fi
  success "Backup created."

  # Instead of removing all 'server' entries, we will just append the new one.
  # This preserves existing server configurations in the file.
  # Chrony will evaluate all listed servers based on their quality and options.
  info "Appending new NTP server: ${ntp_server} to ${CHRONY_CONF}"
  if ! echo "server ${ntp_server} iburst" | sudo tee -a "${CHRONY_CONF}" >/dev/null; then
    error "Failed to add new server entry to ${CHRONY_CONF}. Check file permissions."
    exit 1
  fi
  success "New server entry appended."

  # Enable and restart chrony service
  info "Enabling and restarting ${SERVICE_NAME} service..."
  if ! sudo systemctl enable "${SERVICE_NAME}"; then
    warning "Failed to enable ${SERVICE_NAME} service (may already be enabled or not supported)."
  else
      success "${SERVICE_NAME} service enabled."
  fi

  # Give systemctl enable a moment to settle if it just happened
  sleep 1

  if ! sudo systemctl restart "${SERVICE_NAME}"; then
    error "Failed to restart ${SERVICE_NAME} service. Check service status and logs ('sudo systemctl status ${SERVICE_NAME}')."
    exit 1
  fi
  success "${SERVICE_NAME} service restarted."
}

# Check chrony status
check_status() {
  echo # Add a blank line for better readability
  info "Checking Chrony status..."

  info "Chrony tracking status:"
  if ! chronyc tracking; then
      warning "Failed to get chrony tracking status. Chrony might not be fully initialized yet or service is not running."
      warning "Check with 'sudo systemctl status ${SERVICE_NAME}'."
  fi

  echo # Add a blank line
  info "Chrony NTP sources:"
  if ! chronyc sources -v; then
      warning "Failed to get chrony NTP sources. Chrony might not be fully initialized yet or service is not running."
      warning "Check with 'sudo systemctl status ${SERVICE_NAME}'."
  fi

  echo # Add a blank line
  info "Configuration complete. Chrony will now use the configured servers."
  info "Please wait a few minutes for chrony to synchronize. You can check progress with 'chronyc tracking' and 'chronyc sources -v'."
}

# Display usage instructions
usage() {
  echo # Add a blank line
  info "${RED}Usage${NO_COLOR}: ${BOLD}${0}${NO_COLOR} <region_code>"
  info "  <region_code>: The 2-letter region code (e.g., us, cn, eu, asia, oceania)"
  echo
  info "  ${BOLD}Examples:${NO_COLOR}"
  info "    $0 us  # Use NTP pool servers for USA (us.pool.ntp.org)"
  info "    $0 cn  # Use NTP pool servers for China (cn.pool.ntp.org)"
  info "    $0 eu  # Use NTP pool servers for Europe (eu.pool.ntp.org)"
  echo
  info "Note: This script assumes a Debian/Ubuntu system using apt and systemd."
  info "It requires 'sudo' permissions and depends on logging functions from '${TOP_DIR}/scripts/apollo.bashrc'."
  info "The script will APPREND the new server to chrony.conf, NOT replace existing ones."
}

# Main function to orchestrate the steps
main() {
  check_sudo
  parse_args "$@"
  check_chrony_installed
  configure_chrony
  check_status
}

# Execute the main function with all passed arguments
main "$@"
