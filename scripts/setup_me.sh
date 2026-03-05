#!/bin/bash

set -euo pipefail

# Check if run as root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root." >&2
    exit 1
fi

# Variables
USERNAME="adminsetup"
SSH_CONFIG="/etc/ssh/sshd_config"
SSH_NEEDS_RESTART=0
GITHUB_USER="Upwind1647"
GITHUB_KEYS_URL="https://github.com/${GITHUB_USER}.keys"
APP_PORT=8000

# Create user
if id "$USERNAME" &>/dev/null; then
    echo "User $USERNAME already exists."
else
    useradd -m -s /bin/bash "$USERNAME"
    echo "User created: $USERNAME"
fi

# Lock password for user
passwd -l "$USERNAME" &>/dev/null
echo "Password for $USERNAME locked."

# Create .ssh folder
SSH_DIR="/home/$USERNAME/.ssh"
if [[ ! -d "$SSH_DIR" ]]; then
    mkdir -p "$SSH_DIR"
    echo "Created directory: $SSH_DIR"
fi

# SSH folder permissions
chmod 700 "$SSH_DIR"
chown "$USERNAME":"$USERNAME" "$SSH_DIR"

# Install basic packages (idempotent enough)
if ! command -v sudo &>/dev/null \
   || ! command -v curl &>/dev/null \
   || ! command -v git &>/dev/null \
   || ! command -v docker &>/dev/null \
   || ! command -v ufw &>/dev/null; then
    echo "Installing sudo, curl, git, python3-venv, docker.io and ufw..."
    apt-get update
    apt-get install -y sudo curl git python3-venv docker.io ufw
fi

# Add user to sudo and docker group
if groups "$USERNAME" | grep -q "\bsudo\b" && groups "$USERNAME" | grep -q "\bdocker\b"; then
    echo "$USERNAME already in sudo and docker groups."
else
    echo "Adding $USERNAME to sudo and docker"
    usermod -aG sudo,docker "$USERNAME"
fi

# NOPASSWD for $USERNAME
echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/90-$USERNAME"
chmod 0440 "/etc/sudoers.d/90-$USERNAME"

# Add GitHub public keys
SSH_DIR="/home/$USERNAME/.ssh"
AUTHORIZED_KEYS="$SSH_DIR/authorized_keys"

echo "Fetching SSH keys for $GITHUB_USER"
TMP_KEYS_FILE=$(mktemp)
trap 'rm -f "$TMP_KEYS_FILE" "$TMP_KEYS_FILE.filtered"' EXIT

if ! curl --silent --fail --max-time 10 "$GITHUB_KEYS_URL" -o "$TMP_KEYS_FILE"; then
    echo "ERROR: Could not fetch key from $GITHUB_KEYS_URL"
    exit 1
fi

# Filter to valid key lines
grep -E '^(ssh-(rsa|ed25519|ecdsa)|ecdsa-sha2)' "$TMP_KEYS_FILE" > "$TMP_KEYS_FILE.filtered" || true
if ! [ -s "$TMP_KEYS_FILE.filtered" ]; then
    echo "ERROR: No valid SSH public keys found at $GITHUB_KEYS_URL"
    exit 1
fi

# Key permissions and write keys
touch "$AUTHORIZED_KEYS"
chmod 600 "$AUTHORIZED_KEYS"
chown "$USERNAME":"$USERNAME" "$AUTHORIZED_KEYS"

ADDED_KEY=0
while read -r keyline; do
    if ! grep -qF "$keyline" "$AUTHORIZED_KEYS"; then
        echo "$keyline" >> "$AUTHORIZED_KEYS"
        ADDED_KEY=1
    fi
done < "$TMP_KEYS_FILE.filtered"
chown "$USERNAME":"$USERNAME" "$AUTHORIZED_KEYS"

if [ ! -s "$AUTHORIZED_KEYS" ]; then
    echo "ERROR: No SSH key written for $USERNAME in $AUTHORIZED_KEYS."
    exit 1
fi

if [ "$ADDED_KEY" -eq 1 ]; then
    echo "Added SSH key(s) from $GITHUB_USER to $AUTHORIZED_KEYS"
else
    echo "SSH key(s) from $GITHUB_USER already present in $AUTHORIZED_KEYS"
fi

# SSH

# Backup SSH config
if [ ! -f "$SSH_CONFIG" ]; then
    echo "ERROR: $SSH_CONFIG not found." >&2
    exit 1
fi
if [ ! -f "${SSH_CONFIG}.bak" ]; then
    cp -a "$SSH_CONFIG" "${SSH_CONFIG}.bak"
    echo "Backed up sshd_config to ${SSH_CONFIG}.bak"
fi

# Disable root login
if grep -qE "^\s*PermitRootLogin\s+no" "$SSH_CONFIG"; then
    echo "Root login already disabled."
else
    if grep -qE "^\s*#?\s*PermitRootLogin" "$SSH_CONFIG"; then
        sed -i -E 's|^\s*#?\s*PermitRootLogin.*|PermitRootLogin no|' "$SSH_CONFIG"
    else
        [ -n "$(tail -c 1 "$SSH_CONFIG")" ] && echo "" >> "$SSH_CONFIG"
        echo "PermitRootLogin no" >> "$SSH_CONFIG"
    fi
    SSH_NEEDS_RESTART=1
    echo "Disabled root login for SSH."
fi

# Force key-auth (disable password auth)
if grep -qE "^\s*PasswordAuthentication\s+no" "$SSH_CONFIG"; then
    echo "Password Authentication already disabled."
else
    if grep -qE "^\s*#?\s*PasswordAuthentication" "$SSH_CONFIG"; then
        sed -i -E 's|^\s*#?\s*PasswordAuthentication.*|PasswordAuthentication no|' "$SSH_CONFIG"
    else
        [ -n "$(tail -c 1 "$SSH_CONFIG")" ] && echo "" >> "$SSH_CONFIG"
        echo "PasswordAuthentication no" >> "$SSH_CONFIG"
    fi
    SSH_NEEDS_RESTART=1
    echo "Disabled SSH password authentication."
fi

# Optional: X11 forwarding aus
if grep -qE "^\s*X11Forwarding\s+no" "$SSH_CONFIG"; then
    echo "X11 forwarding already disabled."
else
    if grep -qE "^\s*#?\s*X11Forwarding" "$SSH_CONFIG"; then
        sed -i -E 's|^\s*#?\s*X11Forwarding.*|X11Forwarding no|' "$SSH_CONFIG"
    else
        [ -n "$(tail -c 1 "$SSH_CONFIG")" ] && echo "" >> "$SSH_CONFIG"
        echo "X11Forwarding no" >> "$SSH_CONFIG"
    fi
    SSH_NEEDS_RESTART=1
    echo "Disabled X11 forwarding for SSH."
fi

# Optional: MaxAuthTries reduzieren
if grep -qE "^\s*MaxAuthTries\s+3" "$SSH_CONFIG"; then
    echo "MaxAuthTries already set to 3."
else
    if grep -qE "^\s*#?\s*MaxAuthTries" "$SSH_CONFIG"; then
        sed -i -E 's|^\s*#?\s*MaxAuthTries.*|MaxAuthTries 3|' "$SSH_CONFIG"
    else
        [ -n "$(tail -c 1 "$SSH_CONFIG")" ] && echo "" >> "$SSH_CONFIG"
        echo "MaxAuthTries 3" >> "$SSH_CONFIG"
    fi
    SSH_NEEDS_RESTART=1
    echo "Set MaxAuthTries to 3."
fi

# UFW

# Set defaults and allow SSH
ufw default deny incoming > /dev/null
ufw default allow outgoing > /dev/null
ufw limit ssh > /dev/null

# Allow Status-API port (for Docker / FastAPI)
ufw allow "${APP_PORT}"/tcp > /dev/null

# Enable UFW
if ufw status | grep -q "Status: active"; then
    echo "UFW is already active"
else
    echo "Enabling UFW"
    ufw --force enable
fi

# Restart SSH if needed
if [ "$SSH_NEEDS_RESTART" -eq 1 ]; then
    if ! sshd -t 2>/dev/null; then
        echo "ERROR: sshd_config is invalid (sshd -t failed). Restore from ${SSH_CONFIG}.bak if needed." >&2
        exit 1
    fi
    echo "Restarting SSH"
    if ! ( systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null || service ssh restart 2>/dev/null ); then
        echo "ERROR: Could not restart SSH service." >&2
    fi
fi

echo "--- Setup Complete ---"
echo "User:    $USERNAME"
echo "Login:   ssh $USERNAME@<IP>"
echo "UFW:     SSH + Port ${APP_PORT}/tcp allowed"
