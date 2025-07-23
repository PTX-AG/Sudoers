#!/usr/bin/env bash
# shellcheck source=/dev/null
set -o errexit -o nounset -o pipefail
[ "${DEBUG:-}" ] && set -x

# setup_user.sh: create/configure a user, enable sudo and SSH, and secure SSH access

# Default configuration
DRY_RUN=false
CONFIG_FILE=
USERNAME=
PASSWORD=
SSH_KEYS_FILE=
SSH_PORT=22
LOG_FILE=/var/log/setup_user.log

print_usage() {
  cat <<EOF
Usage: $0 [options]
Options:
  -h, --help             Show this help and exit
  -n, --dry-run          Show actions without executing them
  -c, --config FILE      Configuration file (shell KEY=VALUE format)
  -u, --username NAME    Username to create/configure
  -p, --password PASS    Password for the user (not recommended on CLI)
  -k, --ssh-keys FILE    File with SSH public keys (one per line)
      --ssh-port PORT    SSH daemon port (default: 22)
      --log-file FILE    Path to log file (default: /var/log/setup_user.log)
EOF
  exit 0
}

log() {
  local msg="$*"
  echo "$(date +'%F %T') - $msg" | tee -a "$LOG_FILE"
}

run_cmd() {
  if $DRY_RUN; then
    log "[DRY-RUN] $*"
  else
    log "Running: $*"
    "$@"
  fi
}

bail() {
  log "Error on line $1. Exiting."
  exit 1
}
trap 'bail $LINENO' ERR

# Parse options
OPTIONS=hnd:c:u:p:k:
LONGOPTS=help,dry-run,config:,username:,password:,ssh-keys:,ssh-port:,log-file:

PARSED=$(getopt --options "$OPTIONS" --longoptions "$LONGOPTS" --name "$0" -- "$@")
eval set -- "$PARSED"
while true; do
  case "$1" in
    -h|--help) print_usage ;; 
    -n|--dry-run) DRY_RUN=true; shift ;; 
    -c|--config) CONFIG_FILE="$2"; shift 2 ;; 
    -u|--username) USERNAME="$2"; shift 2 ;; 
    -p|--password) PASSWORD="$2"; shift 2 ;; 
    -k|--ssh-keys) SSH_KEYS_FILE="$2"; shift 2 ;; 
    --ssh-port) SSH_PORT="$2"; shift ;; 
    --log-file) LOG_FILE="$2"; shift ;; 
    --) shift; break ;; 
    *) echo "Unknown option: $1"; exit 1 ;; 
  esac
done

# Load config file if provided
if [[ -n "$CONFIG_FILE" ]]; then
  if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
    log "Loaded configuration from $CONFIG_FILE"
  else
    bail "Config file not found: $CONFIG_FILE"
  fi
fi

# Ensure root privileges
if [[ $EUID -ne 0 ]]; then
  bail "Must be run as root"
fi

# Prompt for username if missing
if [[ -z "$USERNAME" ]]; then
  read -rp "Enter the username to create/configure: " USERNAME
fi

# Prompt for password if missing
if [[ -z "$PASSWORD" ]]; then
  read -rsp "Enter password for user '$USERNAME': " PASSWORD
  echo
fi

# Interactive prompts for other configuration if not set via flags or config file
# SSH key file to install (optional)
if [[ -z "$SSH_KEYS_FILE" ]]; then
  read -rp "Enter path to SSH public keys file (leave blank to skip): " SSH_KEYS_FILE
fi
# SSH daemon port
read -rp "Enter SSH port [${SSH_PORT}]: " _port
SSH_PORT=${_port:-$SSH_PORT}
# Log file location
read -rp "Enter log file path [${LOG_FILE}]: " _logf
LOG_FILE=${_logf:-$LOG_FILE}
# Dry-run mode
read -rp "Perform dry-run (no changes)? [y/N]: " _dry
if [[ "$_dry" =~ ^[Yy]$ ]]; then
  DRY_RUN=true
fi

# Detect package manager and service command
if command -v apt-get &>/dev/null; then
  PKG_INSTALL="apt-get update && apt-get install -y"
  SSH_PKG=openssh-server
  SSH_SERVICE=ssh
elif command -v yum &>/dev/null || command -v dnf &>/dev/null; then
  PKG_INSTALL="yum install -y"
  SSH_PKG=openssh-server
  SSH_SERVICE=sshd
elif command -v apk &>/dev/null; then
  PKG_INSTALL="apk add --no-cache"
  SSH_PKG=openssh-server
  SSH_SERVICE=sshd
else
  bail "Unsupported package manager"
fi

# Create user if needed
if id "$USERNAME" &>/dev/null; then
  log "User '$USERNAME' exists, skipping creation"
else
  run_cmd useradd -m -s /bin/bash "$USERNAME"
  run_cmd bash -c "echo '$USERNAME:$PASSWORD' | chpasswd"
  log "Created user '$USERNAME'"
fi

# Install sudo
if ! command -v sudo &>/dev/null; then
  run_cmd $PKG_INSTALL sudo
else
  log "sudo already installed"
fi

# Determine sudo group
SUDO_GROUP=sudo
if ! getent group sudo &>/dev/null && getent group wheel &>/dev/null; then
  SUDO_GROUP=wheel
fi
# Add user to sudo group
if id -nG "$USERNAME" | grep -qw "$SUDO_GROUP"; then
  log "User '$USERNAME' already in group '$SUDO_GROUP'"
else
  run_cmd usermod -aG "$SUDO_GROUP" "$USERNAME"
  log "Added '$USERNAME' to group '$SUDO_GROUP'"
fi

# Install and enable SSH
if ! command -v sshd &>/dev/null; then
  run_cmd $PKG_INSTALL $SSH_PKG
else
  log "SSH server already installed"
fi
if command -v systemctl &>/dev/null; then
  run_cmd systemctl enable "$SSH_SERVICE"
  run_cmd systemctl restart "$SSH_SERVICE"
else
  run_cmd service "$SSH_SERVICE" restart
fi

# Backup and secure sshd_config
SSHD_CONF=/etc/ssh/sshd_config
if [[ ! -f ${SSHD_CONF}.bak ]]; then
  run_cmd cp -p "$SSHD_CONF" "${SSHD_CONF}.bak"
fi
run_cmd sed -ri 's/^#?PermitRootLogin\s+.*/PermitRootLogin no/' "$SSHD_CONF"
run_cmd sed -ri 's/^#?PasswordAuthentication\s+.*/PasswordAuthentication no/' "$SSHD_CONF"
if [[ "$SSH_PORT" != "22" ]]; then
  if grep -qE '^#?Port\s+' "$SSHD_CONF"; then
    run_cmd sed -ri "s/^#?Port\s+.*/Port $SSH_PORT/" "$SSHD_CONF"
  else
    run_cmd bash -c "echo 'Port $SSH_PORT' >> $SSHD_CONF"
  fi
  log "Set SSH port to $SSH_PORT"
fi

# Setup SSH authorized_keys if provided
if [[ -n "$SSH_KEYS_FILE" ]]; then
  if [[ -f "$SSH_KEYS_FILE" ]]; then
    SSH_DIR="/home/$USERNAME/.ssh"
    run_cmd mkdir -p "$SSH_DIR"
    AUTH_KEYS="$SSH_DIR/authorized_keys"
    run_cmd cp "$SSH_KEYS_FILE" "$AUTH_KEYS"
    run_cmd chmod 600 "$AUTH_KEYS"
    run_cmd chown -R "$USERNAME":"$USERNAME" "$SSH_DIR"
    log "Installed SSH keys from $SSH_KEYS_FILE"
  else
    bail "SSH keys file not found: $SSH_KEYS_FILE"
  fi
fi

# Install and enable fail2ban if available
if command -v fail2ban-client &>/dev/null; then
  log "fail2ban already installed"
elif run_cmd $PKG_INSTALL fail2ban; then
  log "Installed fail2ban"
else
  log "fail2ban not available in package repo; skipping service enable"
fi
# Only enable/restart if fail2ban is present
if command -v fail2ban-client &>/dev/null && command -v systemctl &>/dev/null; then
  run_cmd systemctl enable fail2ban
  run_cmd systemctl restart fail2ban
fi

log "Setup completed for user '$USERNAME'"
