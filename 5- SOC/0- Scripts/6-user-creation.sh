#!/bin/bash

# ─────────────────────────────────────────────
#  Blue Team User Setup Script
#  Creates bt1–bt10, sets SSH keys, passwords,
#  and grants sudo/wheel + visudo entries
# ─────────────────────────────────────────────

set -e

# Full paths to sbin binaries (fixes PATH issues on some systems)
USERADD=/usr/sbin/useradd
USERMOD=/usr/sbin/usermod
VISUDO=/usr/sbin/visudo

# ── 1. Ask for sudo group type ────────────────
echo "========================================"
echo "  Blue Team User Setup"
echo "========================================"
echo ""
echo "Which sudo group does this system use?"
echo "  1) sudo   (Debian / Ubuntu)"
echo "  2) wheel  (Rocky / RHEL / CentOS)"
read -rp "Enter 1 or 2: " GROUP_CHOICE

case "$GROUP_CHOICE" in
  1) SUDO_GROUP="sudo"  ;;
  2) SUDO_GROUP="wheel" ;;
  *)
    echo "[ERROR] Invalid choice. Exiting."
    exit 1
    ;;
esac

echo "[*] Using group: $SUDO_GROUP"
echo ""

# ── 2. Collect SSH public key ─────────────────
echo "Paste the SSH public key to deploy to all bt users:"
read -rp "SSH Public Key: " SSH_PUBLIC_KEY

if [[ -z "$SSH_PUBLIC_KEY" ]]; then
  echo "[ERROR] SSH public key cannot be empty. Exiting."
  exit 1
fi

# ── 3. Collect and hash password ──────────────
read -rsp "Enter the team password: " TEAM_PASSWORD
echo ""
if [[ -z "$TEAM_PASSWORD" ]]; then
  echo "[ERROR] Password cannot be empty. Exiting."
  exit 1
fi

PASSWORD_HASH=$(openssl passwd -6 "$TEAM_PASSWORD")
echo "[*] Password hash generated."
echo ""

# ── 4. Create bt1–bt10 ────────────────────────
echo "[*] Creating users bt1–bt10..."
for i in $(seq 1 10); do
  if id "bt$i" &>/dev/null; then
    echo "  [!] bt$i already exists, skipping creation."
  else
    $USERADD -m -s /bin/bash -G "$SUDO_GROUP" "bt$i"
    echo "  [+] Created bt$i"
  fi
done

# ── 5. Set passwords ──────────────────────────
echo "[*] Setting passwords..."
for i in $(seq 1 10); do
  $USERMOD -p "$PASSWORD_HASH" "bt$i"
done
echo "  [+] Passwords set."

# ── 6. Set up .ssh directories and keys ───────
echo "[*] Deploying SSH keys..."
for i in $(seq 1 10); do
  mkdir -p "/home/bt$i/.ssh"
  echo "$SSH_PUBLIC_KEY" > "/home/bt$i/.ssh/authorized_keys"
  chmod 700 "/home/bt$i/.ssh"
  chmod 600 "/home/bt$i/.ssh/authorized_keys"
  chown -R "bt$i:bt$i" "/home/bt$i/.ssh"
done
echo "  [+] SSH keys deployed."

# ── 7. Ensure group membership ────────────────
echo "[*] Adding users to $SUDO_GROUP group..."
for i in $(seq 1 10); do
  $USERMOD -aG "$SUDO_GROUP" "bt$i"
done
echo "  [+] Group membership set."

# ── 8. Add visudo entries ─────────────────────
echo "[*] Adding visudo entries..."
VISUDO_FILE="/etc/sudoers.d/blueteam"

> "$VISUDO_FILE"

for i in $(seq 1 10); do
  echo "bt$i ALL=(ALL) NOPASSWD: ALL" >> "$VISUDO_FILE"
done

chmod 440 "$VISUDO_FILE"

if $VISUDO -cf "$VISUDO_FILE"; then
  echo "  [+] visudo entries written and validated: $VISUDO_FILE"
else
  echo "  [ERROR] visudo validation failed! Removing file to prevent lockout."
  rm -f "$VISUDO_FILE"
  exit 1
fi

# ── 9. Verify ─────────────────────────────────
echo ""
echo "========================================"
echo "  Verification"
echo "========================================"
echo ""
echo "[*] Checking /etc/passwd for bt users:"
grep "bt[0-9]" /etc/passwd

echo ""
echo "[*] Checking authorized_keys for bt1:"
cat /home/bt1/.ssh/authorized_keys

echo ""
echo "[*] Checking .ssh permissions for bt1:"
ls -la /home/bt1/.ssh/

echo ""
echo "[*] Sudoers drop-in file contents:"
cat "$VISUDO_FILE"

echo ""
echo "========================================"
echo "  Setup Complete!"
echo "========================================"