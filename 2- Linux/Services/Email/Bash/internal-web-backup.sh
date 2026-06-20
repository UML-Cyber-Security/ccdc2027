#!/usr/bin/env bash
set -euo pipefail

### CONFIG
LOCAL_HOSTNAME=$(hostname)
BACKUP_BASE="$HOME/webserver-backups"

TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
DEST="$BACKUP_BASE/$TIMESTAMP"
LATEST_LINK="$BACKUP_BASE/latest"

mkdir -p "$DEST"

echo "[+] Backup destination: $DEST"

### WEB SERVER CONFIG PATHS
declare -A SERVICES=(
  ["nginx"]="/etc/nginx"
  ["apache2"]="/etc/apache2"
  ["httpd"]="/etc/httpd"
  ["lighttpd"]="/etc/lighttpd"
)

### DETECT AND BACKUP
FOUND=0

for SERVICE in "${!SERVICES[@]}"; do
  CONFIG_PATH="${SERVICES[$SERVICE]}"

  if [ -d "$CONFIG_PATH" ]; then
    echo "[+] Found $SERVICE at $CONFIG_PATH"

    OUT_DIR="$DEST/$SERVICE"
    mkdir -p "$OUT_DIR"

    cp -a "$CONFIG_PATH" "$OUT_DIR/" 2>/dev/null || {
      echo "[!] Warning: partial copy of $SERVICE (permission limited)"
    }

    FOUND=1
  fi
done

### UPDATE LATEST POINTER
rm -f "$LATEST_LINK"
ln -s "$TIMESTAMP" "$LATEST_LINK"

### RESULT SUMMARY
echo "======================================"
echo " "
echo "SUMMARY"
echo " "
echo "======================================"
echo "[+] Hostname        : $LOCAL_HOSTNAME"
if [ "$FOUND" -eq 0 ]; then
  echo "[!] No known web server configs found."
else
  echo "[✓] Backup complete."
fi

echo "[✓] Stored in: $DEST"
echo "[✓] Latest -> $LATEST_LINK"