#!/bin/bash

#********************************
# Written by Michael Leahy
# Last Updated: March 3, 2026
#********************************

# Check if the script is ran as root.
if [ "$EUID" -ne 0 ]
  then echo "This script must be run as root."
  exit 1
fi

# Check if UFW is already installed
if ! command -v ufw >/dev/null 2>&1; then
    echo "[!] UFW not found. Installing..."

    if command -v apt >/dev/null 2>&1; then
        apt update && apt install -y ufw
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y ufw
    elif command -v yum >/dev/null 2>&1; then
        yum install -y ufw
    else
        echo "[!!] Could not determine package manager. Install UFW manually."
        exit 1
    fi
fi


# disable firewalld before starting ufw
echo "[!!] Disabiling Firewalld"
if systemctl is-active --quiet firewalld; then
    # Disable
    systemctl disable firewalld
    # Stop
    systemctl stop firewalld
    # Prevent Startup
    systemctl mask firewalld
fi

# set default rules
echo "[+] Adding default incoming and outgoing rules..."
ufw default deny incoming
ufw default allow outgoing

# Allow ssh
echo "[+] Allowing SSH..."
ufw allow 22/tcp

# Allow HTTP/HTTPS
echo "[+] Allowing HTTP/HTTPS..."
ufw allow 80/tcp
ufw allow out 80/tcp
ufw allow 443/tcp
ufw allow out 443/tcp

# Allow DNS
echo "[+] Allowing DNS..."
ufw allow out 53/udp

# enable UFW
echo "[+] Enabling UFW..."
ufw --force enable

echo "[!!] UFW configuration complete. Add custom rules if necessary"

# Flush the connection tracking table
echo "[!!] Flushing connection tracking table..."
if command -v apt >/dev/null 2>&1; then
    apt update && apt install conntrack -y
elif command -v dnf >/dev/null 2>&1; then
    dnf install conntrack-tools -y
elif command -v yum >/dev/null 2>&1; then
    yum install conntrack-tools -y
fi
conntrack -F