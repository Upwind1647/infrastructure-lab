#!/bin/bash

set -euo pipefail

# Config
readonly USERNAME="adminsetup"
readonly SSH_CONFIG="/etc/ssh/sshd_config"
SSH_NEEDS_RESTART=0

# Logging
log_ok()      { echo "[OK]      $1"; }
log_changed() { echo "[CHANGED] $1"; }
log_skip()    { echo "[SKIP]    $1"; }
log_warn()    { echo "[WARN]    $1" >&2; }
log_error()   { echo "[ERROR]   $1" >&2; }

# Functions

# Sets an sshd_config key
set_sshd_option() {
    local key="$1"
    local value="$2"

    # Case 1: Already set correctly
    if grep -qE "^${key}[[:space:]]+${value}$" "$SSH_CONFIG"; then
        log_skip "${key} already set to '${value}'."
        return
    fi

    # Case 2: Uncommented line with wrong value
    if grep -qE "^${key}[[:space:]]+" "$SSH_CONFIG"; then
        sed -i -E "s/^${key}[[:space:]]+.*/${key} ${value}/" "$SSH_CONFIG"
        log_changed "${key} → '${value}'."

    # Case 3: Commented out
    elif grep -qE "^#[[:space:]]*${key}" "$SSH_CONFIG"; then
        sed -i -E "s/^#[[:space:]]*${key}.*/${key} ${value}/" "$SSH_CONFIG"
        log_changed "${key} uncommented → '${value}'."

    # Case 4: Line missing entirely
    else
        echo "${key} ${value}" >> "$SSH_CONFIG"
        log_changed "${key} appended → '${value}'."
    fi

    SSH_NEEDS_RESTART=1
}

# 0. PRE-FLIGHT CHECK

if [[ "$EUID" -ne 0 ]]; then
    log_error "This script must be run as root."
    exit 1
fi

# 1. USER & SUDO

if id "$USERNAME" &>/dev/null; then
    log_skip "User '$USERNAME' already exists."
else
    useradd -m -s /bin/bash "$USERNAME"
    log_changed "User '$USERNAME' created."
fi

if command -v sudo &>/dev/null; then
    log_skip "sudo already installed."
else
    apt-get update -qq && apt-get install -y -qq sudo
    log_changed "sudo installed."
fi

if groups "$USERNAME" | grep -qw "sudo"; then
    log_skip "'$USERNAME' already in sudo group."
else
    usermod -aG sudo "$USERNAME"
    log_changed "'$USERNAME' added to sudo group."
fi

# 2. SSH KEY PREPARATION

readonly SSH_DIR="/home/${USERNAME}/.ssh"
readonly AUTH_KEYS="${SSH_DIR}/authorized_keys"

if [[ -d "$SSH_DIR" ]]; then
    log_skip "'$SSH_DIR' already exists."
else
    mkdir -p "$SSH_DIR"
    log_changed "Created '$SSH_DIR'."
fi

if [[ -f "$AUTH_KEYS" ]]; then
    log_skip "'$AUTH_KEYS' already exists."
else
    touch "$AUTH_KEYS"
    log_changed "Created '$AUTH_KEYS'."
fi

chmod 700 "$SSH_DIR"
chmod 600 "$AUTH_KEYS"
chown -R "${USERNAME}:${USERNAME}" "$SSH_DIR"
log_ok "SSH directory permissions verified."

# 3. SSH HARDENING

if [[ ! -s "$AUTH_KEYS" ]]; then
    log_warn "============================================================"
    log_warn "'$AUTH_KEYS' is EMPTY."
    log_warn "Skipping SSH hardening to prevent lock-out."
    log_warn "Add your public key first, then re-run this script."
    log_warn "============================================================"
else
    set_sshd_option "PermitRootLogin" "no"
    set_sshd_option "PasswordAuthentication" "no"

    if [[ "$SSH_NEEDS_RESTART" -eq 1 ]]; then
        systemctl restart ssh
        log_changed "SSH service restarted."
    else
        log_skip "SSH config unchanged. No restart needed."
    fi
fi

# 4. UFW FIREWALL

if command -v ufw &>/dev/null; then
    log_skip "UFW already installed."
else
    apt-get update -qq && apt-get install -y -qq ufw
    log_changed "UFW installed."
fi

ufw_status=$(ufw status verbose 2>/dev/null || true)

if echo "$ufw_status" | grep -q "Default: deny (incoming)"; then
    log_skip "UFW default incoming: deny."
else
    ufw default deny incoming > /dev/null
    log_changed "UFW default incoming → deny."
fi

if echo "$ufw_status" | grep -q "Default: allow (outgoing)"; then
    log_skip "UFW default outgoing: allow."
else
    ufw default allow outgoing > /dev/null
    log_changed "UFW default outgoing → allow."
fi

if ufw status | grep -q "22/tcp.*LIMIT"; then
    log_skip "UFW SSH limit rule exists."
else
    ufw limit ssh > /dev/null
    log_changed "UFW SSH limit rule added."
fi

if echo "$ufw_status" | grep -q "Status: active"; then
    log_skip "UFW already active."
else
    ufw --force enable
    log_changed "UFW enabled."
fi

echo ""
log_ok "=== Setup complete ==="

if [[ ! -s "$AUTH_KEYS" ]]; then
    echo ""
    log_warn "ACTION REQUIRED: Add your SSH public key to '${AUTH_KEYS}', then re-run."
fi
