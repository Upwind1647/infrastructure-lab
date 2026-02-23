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
chown -R "$USERNAME":"$USERNAME" "$SSH_DIR"

# Install sudo and curl if missing
if ! command -v sudo &>/dev/null || ! command -v curl &>/dev/null; then
    echo "Installing sudo and curl..."
    apt-get update && apt-get install -y sudo curl
fi

# Add user to sudo group
if groups "$USERNAME" | grep -q "\bsudo\b"; then
    echo "$USERNAME already has sudo."
else
    echo " Adding $USERNAME to sudo "
    usermod -aG sudo "$USERNAME"
fi

# NOPASSWD for $USERNAME
echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/90-$USERNAME"
chmod 0440 "/etc/sudoers.d/90-$USERNAME"

# Add github public key
SSH_DIR="/home/$USERNAME/.ssh"
AUTHORIZED_KEYS="$SSH_DIR/authorized_keys"

# Fetch keys from github
echo "Fetching SSH keys for $GITHUB_USER"
TMP_KEYS_FILE=$(mktemp)
if ! curl --silent --fail "$GITHUB_KEYS_URL" -o "$TMP_KEYS_FILE"; then
    echo "ERROR: Could not fetch key from $GITHUB_KEYS_URL"
    exit 1
fi

# Filter to valid key lines
grep '^[[:space:]]*ssh-' "$TMP_KEYS_FILE" > "$TMP_KEYS_FILE.filtered" || true
if ! [ -s "$TMP_KEYS_FILE.filtered" ]; then
    echo "ERROR: No valid SSH public keys found at $GITHUB_KEYS_URL"
    rm -f "$TMP_KEYS_FILE" "$TMP_KEYS_FILE.filtered"
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
rm -f "$TMP_KEYS_FILE" "$TMP_KEYS_FILE.filtered"

if [ ! -s "$AUTHORIZED_KEYS" ]; then
    echo "ERROR: No SSH key written for $USERNAME in $AUTHORIZED_KEYS."
    exit 1
fi
if [ "$ADDED_KEY" -eq 1 ]; then
    echo "Added SSH key(s) from $GITHUB_USER to $AUTHORIZED_KEYS"
else
    echo "SSH key from $GITHUB_USER already in $AUTHORIZED_KEYS"
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
        sed -i 's|^\s*#?\s*PermitRootLogin.*|PermitRootLogin no|' "$SSH_CONFIG"
    else
        echo "PermitRootLogin no" >> "$SSH_CONFIG"
    fi
    SSH_NEEDS_RESTART=1
    echo "Disabled root login for SSH."
fi

# Force key-auth
if grep -qE "^\s*PasswordAuthentication\s+no" "$SSH_CONFIG"; then
    echo "Password Authentication already disabled."
else
    if grep -qE "^\s*#?\s*PasswordAuthentication" "$SSH_CONFIG"; then
        sed -i 's|^\s*#?\s*PasswordAuthentication.*|PasswordAuthentication no|' "$SSH_CONFIG"
    else
        echo "PasswordAuthentication no" >> "$SSH_CONFIG"
    fi
    SSH_NEEDS_RESTART=1
    echo "Disabled SSH password authentication."
fi

# UFW

# Install ufw
if ! command -v ufw &>/dev/null; then
    echo "Installing UFW"
    apt-get update && apt-get install -y ufw
fi

# Set defaults and allow SSH
ufw default deny incoming > /dev/null
ufw default allow outgoing > /dev/null
ufw limit ssh > /dev/null

# Enable UFW
if ufw status | grep -q "Status: active"; then
    echo "UFW is already active"
else
    echo "Enabling UFW"
    ufw --force enable
fi

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
