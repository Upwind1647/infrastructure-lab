#!/bin/bash

set -e

# Variables
USERNAME="adminsetup"
SSH_CONFIG="/etc/ssh/sshd_config"
SSH_NEEDS_RESTART=0

# 1. create user & sudo
if id "$USERNAME" &>/dev/null; then
    echo "$USERNAME already exists."
else
    useradd -m -s /bin/bash "$USERNAME"
    echo "User created."
fi

# sudo check
if ! command -v sudo &> /dev/null; then
    echo "Installing sudo"
    apt-get update && apt-get install -y sudo
fi

# Ensures user is in sudo group
if groups "$USERNAME" | grep -q "\bsudo\b"; then
    echo "$USERNAME already has sudo."
else
    echo "$USERNAME to sudo "
    usermod -aG sudo "$USERNAME"
fi

# 2. SSH Hardening

# Disable Root Login
if grep -q "^PermitRootLogin no" "$SSH_CONFIG"; then
    echo "Root login already disabled."
else
    # Finds line starting with optional #, changing it to no
    sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' "$SSH_CONFIG"
    SSH_NEEDS_RESTART=1
fi

# Force Key-Auth
if grep -q "^PasswordAuthentication no" "$SSH_CONFIG"; then
    echo "Password Authentication already disabled."
else
    echo "Disabling Password Authentication"
    sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' "$SSH_CONFIG"
    SSH_NEEDS_RESTART=1
fi

# Restart SSH only if changes were made
if [ "$SSH_NEEDS_RESTART" -eq 1 ]; then
    echo "Restarting SSH service..."
    systemctl restart ssh
else
    echo "SSH config unchanged. No restart needed."
fi

# 3. UFW Setup
if ! command -v ufw &> /dev/null; then
    echo "Installing UFW"
    apt-get update && apt-get install -y ufw
fi

# Set Defaults
ufw default deny incoming > /dev/null
ufw default allow outgoing > /dev/null

# Allow SSH
ufw limit ssh > /dev/null

# Enable UFW
if ufw status | grep -q "Status: active"; then
    echo "UFW is already active"
else
    echo "Enabling UFW"
    ufw --force enable
fi

echo "--- Setup Complete. Don't forget to copy your SSH key to /home/$USERNAME/.ssh/authorized_keys ---"
