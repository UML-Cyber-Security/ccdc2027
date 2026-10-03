#!/bin/sh

# ─────────────────────────────────────────────
#  Blue Team User Setup Script (POSIX sh)
#  Creates bt1–bt10, sets SSH keys, passwords,
#  and grants sudo/wheel + sudoers entries
#
#  Works on: Debian/Ubuntu, RHEL/Rocky/CentOS/Fedora,
#            Alpine (BusyBox), openSUSE, Arch
# ─────────────────────────────────────────────

set -e

# sbin dirs are often missing from PATH (e.g. su without -)
PATH="$PATH:/usr/local/sbin:/usr/sbin:/sbin"
export PATH

USER_COUNT=10
SUDOERS_FILE="/etc/sudoers.d/blueteam"

# Restore terminal echo if interrupted during the password prompt
trap 'stty echo 2>/dev/null || true' EXIT INT TERM

have() { command -v "$1" >/dev/null 2>&1; }

group_exists() { grep -q "^$1:" /etc/group; }

home_of() { awk -F: -v u="$1" '$1 == u { print $6 }' /etc/passwd; }

# ── 0. Preflight ──────────────────────────────
if [ "$(id -u)" -ne 0 ]; then
  echo "[ERROR] This script must be run as root."
  exit 1
fi

echo "========================================"
echo "  Blue Team User Setup"
echo "========================================"
echo ""

# Install sudo if missing
if ! have sudo || ! have visudo; then
  echo "[*] sudo/visudo not found, attempting to install..."
  if   have apk;     then apk add --no-cache sudo
  elif have apt-get; then apt-get update && apt-get install -y sudo
  elif have dnf;     then dnf install -y sudo
  elif have yum;     then yum install -y sudo
  elif have zypper;  then zypper --non-interactive install sudo
  elif have pacman;  then pacman -Sy --noconfirm sudo
  else
    echo "[ERROR] No known package manager found. Install sudo manually."
    exit 1
  fi
fi

# Detect sudo group: Debian/Ubuntu use "sudo", most others use "wheel"
if group_exists sudo; then
  SUDO_GROUP="sudo"
elif group_exists wheel; then
  SUDO_GROUP="wheel"
else
  SUDO_GROUP="wheel"
  echo "[*] No sudo or wheel group found, creating wheel..."
  if have groupadd; then groupadd "$SUDO_GROUP"; else addgroup -S "$SUDO_GROUP"; fi
fi
echo "[*] Using group: $SUDO_GROUP"

# Pick a login shell: bash if present, otherwise sh
if [ -x /bin/bash ]; then LOGIN_SHELL=/bin/bash; else LOGIN_SHELL=/bin/sh; fi
echo "[*] Using login shell: $LOGIN_SHELL"

if ! grep -Eq '^[#@]includedir[[:space:]]+/etc/sudoers\.d' /etc/sudoers; then
  echo "[!] WARNING: /etc/sudoers does not include /etc/sudoers.d."
  echo "    The blueteam drop-in will be ignored until you add:"
  echo "    @includedir /etc/sudoers.d"
fi
echo ""

# ── 1. Collect SSH public key ─────────────────
echo "Paste the SSH public key to deploy to all bt users:"
printf "SSH Public Key: "
read -r SSH_PUBLIC_KEY

if [ -z "$SSH_PUBLIC_KEY" ]; then
  echo "[ERROR] SSH public key cannot be empty. Exiting."
  exit 1
fi

# ── 2. Collect password (hidden input) ────────
printf "Enter the team password: "
stty -echo
read -r TEAM_PASSWORD
stty echo
echo ""

if [ -z "$TEAM_PASSWORD" ]; then
  echo "[ERROR] Password cannot be empty. Exiting."
  exit 1
fi

# ── 3. Create users ───────────────────────────
echo "[*] Creating users bt1–bt$USER_COUNT..."
i=1
while [ "$i" -le "$USER_COUNT" ]; do
  u="bt$i"
  if id "$u" >/dev/null 2>&1; then
    echo "  [!] $u already exists, skipping creation."
  elif have useradd; then
    useradd -m -s "$LOGIN_SHELL" "$u"
    echo "  [+] Created $u"
  else
    # BusyBox adduser (Alpine without shadow)
    adduser -D -s "$LOGIN_SHELL" "$u"
    echo "  [+] Created $u"
  fi
  i=$((i + 1))
done

# ── 4. Set passwords ──────────────────────────
# chpasswd hashes with the system default (SHA-512/yescrypt on modern distros)
echo "[*] Setting passwords..."
i=1
while [ "$i" -le "$USER_COUNT" ]; do
  printf '%s:%s\n' "bt$i" "$TEAM_PASSWORD"
  i=$((i + 1))
done | chpasswd
unset TEAM_PASSWORD
echo "  [+] Passwords set."

# ── 5. Deploy SSH keys ────────────────────────
echo "[*] Deploying SSH keys..."
i=1
while [ "$i" -le "$USER_COUNT" ]; do
  u="bt$i"
  h=$(home_of "$u")
  g=$(id -gn "$u")
  mkdir -p "$h/.ssh"
  printf '%s\n' "$SSH_PUBLIC_KEY" > "$h/.ssh/authorized_keys"
  chmod 700 "$h/.ssh"
  chmod 600 "$h/.ssh/authorized_keys"
  chown -R "$u:$g" "$h/.ssh"
  # Fix SELinux contexts on RHEL-family systems
  if have restorecon; then restorecon -R "$h/.ssh" 2>/dev/null || true; fi
  i=$((i + 1))
done
echo "  [+] SSH keys deployed."

# ── 6. Group membership ───────────────────────
echo "[*] Adding users to $SUDO_GROUP group..."
i=1
while [ "$i" -le "$USER_COUNT" ]; do
  u="bt$i"
  if id -Gn "$u" | tr ' ' '\n' | grep -qx "$SUDO_GROUP"; then
    echo "  [=] $u already in $SUDO_GROUP"
  elif have usermod; then
    usermod -aG "$SUDO_GROUP" "$u"
  elif have gpasswd; then
    gpasswd -a "$u" "$SUDO_GROUP" >/dev/null
  else
    addgroup "$u" "$SUDO_GROUP"
  fi
  i=$((i + 1))
done
echo "  [+] Group membership set."

# ── 7. Sudoers drop-in ────────────────────────
echo "[*] Writing sudoers entries..."
mkdir -p /etc/sudoers.d
TMP_SUDOERS="$SUDOERS_FILE.tmp.$$"
: > "$TMP_SUDOERS"
i=1
while [ "$i" -le "$USER_COUNT" ]; do
  echo "bt$i ALL=(ALL) NOPASSWD: ALL" >> "$TMP_SUDOERS"
  i=$((i + 1))
done
chmod 440 "$TMP_SUDOERS"

# Validate before installing so a bad file never goes live
if visudo -cf "$TMP_SUDOERS" >/dev/null; then
  mv "$TMP_SUDOERS" "$SUDOERS_FILE"
  echo "  [+] Sudoers entries written and validated: $SUDOERS_FILE"
else
  rm -f "$TMP_SUDOERS"
  echo "  [ERROR] visudo validation failed! Nothing was installed."
  exit 1
fi

# ── 8. Verify ─────────────────────────────────
echo ""
echo "========================================"
echo "  Verification"
echo "========================================"
echo ""
echo "[*] bt users in /etc/passwd:"
grep '^bt[0-9]*:' /etc/passwd

echo ""
echo "[*] authorized_keys for bt1:"
cat "$(home_of bt1)/.ssh/authorized_keys"

echo ""
echo "[*] .ssh permissions for bt1:"
ls -la "$(home_of bt1)/.ssh/"

echo ""
echo "[*] $SUDO_GROUP group:"
grep "^$SUDO_GROUP:" /etc/group

echo ""
echo "[*] Sudoers drop-in contents:"
cat "$SUDOERS_FILE"

echo ""
echo "========================================"
echo "  Setup Complete!"
echo "========================================"