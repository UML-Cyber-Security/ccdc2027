#!/usr/bin/env bash
set -euo pipefail

find_path="${1:-}"

echo "[+] PII scan starting"

#######################################
# EXCLUSIONS
#######################################
EXCLUDES_FIND=(
  -path "*/.ansible/*" -prune -o
  -path "/proc/*" -prune -o
  -path "/sys/*" -prune -o
  -path "/dev/*" -prune -o
  -path "*/.cache/*" -prune -o
)

EXCLUDES_GREP=(
  --exclude-dir=.ansible
  --exclude-dir=.cache
  --exclude-dir=proc
  --exclude-dir=sys
)

#######################################
# EMAIL SCAN (dedicated)
#######################################
scan_emails() {
  local target="$1"

  echo "[+] Scanning for email addresses in: $target"

  grep -REIho "${EXCLUDES_GREP[@]}" \
    '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' \
    "$target" 2>/dev/null || true
}

#######################################
# TEXT PII SCAN (phones, SSN, CC, etc.)
#######################################
scan_text() {
  local target="$1"

  echo "[+] Scanning PII patterns in: $target"

  grep -REIho "${EXCLUDES_GREP[@]}" \
    '(\([0-9]{3}\) |[0-9]{3}-)[0-9]{3}-[0-9]{4}|
     [0-9]{3}-[0-9]{2}-[0-9]{4}|
     (?:\d{4}-?){3}\d{4}|
     [A-Z]{1,2}[0-9]{1,2}\s?[A-Z]{1,3}\s?[0-9]{1,4}' \
    "$target" 2>/dev/null || true
}

#######################################
# FILE TYPE DISCOVERY
#######################################
find_files() {
  local target="$1"

  echo "[+] Searching sensitive file types in: $target"

  find "$target" \
    "${EXCLUDES_FIND[@]}" \
    -type f \( \
      -name '*.doc' -o -name '*.docx' -o -name '*.xls' -o -name '*.xlsx' -o \
      -name '*.ppt' -o -name '*.pptx' -o -name '*.pdf' -o -name '*.txt' -o \
      -name '*.csv' -o -name '*.rtf' -o -name '*.odt' -o -name '*.ods' -o \
      -name '*.odp' -o -name '*.docm' -o -name '*.xlsb' \
    \) -print 2>/dev/null
}

#######################################
# MAIN SCAN FUNCTION
#######################################
run_scan() {
  local target="$1"

  if [[ -d "$target" ]]; then
    scan_emails "$target"
    scan_text "$target"
    find_files "$target"
  fi
}

#######################################
# OPTIONAL TARGET
#######################################
if [[ -n "$find_path" ]]; then
  echo "[+] Custom target: $find_path"
  run_scan "$find_path"
fi

#######################################
# DEFAULT TARGETS
#######################################
echo "[+] Scanning /home"
run_scan /home

echo "[+] Scanning /var/www"
run_scan /var/www

#######################################
# VSFTPD CHECK
#######################################
if [[ -f /etc/vsftpd.conf ]]; then
  echo "[+] vsftpd detected"

  anon_root=$(grep -E '^anon_root' /etc/vsftpd.conf | awk '{print $2}' || true)
  local_root=$(grep -E '^local_root' /etc/vsftpd.conf | awk '{print $2}' || true)

  [[ -n "${anon_root:-}" ]] && run_scan "$anon_root"
  [[ -n "${local_root:-}" ]] && run_scan "$local_root"
fi

#######################################
# PROFTPD CHECK
#######################################
if [[ -f /etc/proftpd/proftpd.conf ]]; then
  echo "[+] proftpd detected"

  default_root=$(grep -E '^DefaultRoot' /etc/proftpd/proftpd.conf | awk '{print $2}' || true)
  [[ -n "${default_root:-}" ]] && run_scan "$default_root"
fi

#######################################
# SAMBA SHARES
#######################################
if [[ -f /etc/samba/smb.conf ]]; then
  echo "[+] samba detected"

  grep -E '^path' /etc/samba/smb.conf | awk '{print $3}' | sed 's/"//g' |
  while read -r share; do
    [[ -n "$share" ]] && run_scan "$share"
  done
fi

echo "[+] PII scan complete"