#!/bin/bash

# ========= CONFIG =========
SUBNETS=("10.0.1.0/24" "10.0.2.0/24" "10.0.3.0/24")
RATE=1200
TIMING="-T4"
OUTDIR="$HOME/nmap_inventory"
DATE=$(date +%F_%H%M)
# ==========================

mkdir -p "$OUTDIR"
cd "$OUTDIR" || exit 1

echo "[+] Phase 1: Fast host discovery"

nmap -sn -PS445,3389,135 ${TIMING} "${SUBNETS[@]}" \
  -oG alive.gnmap >/dev/null

awk '/Up$/{print $2}' alive.gnmap > alive.txt

COUNT=$(wc -l < alive.txt)

if [ "$COUNT" -eq 0 ]; then
  echo "[-] No alive hosts found. Exiting."
  exit 1
fi

echo "[+] Found $COUNT alive hosts"

echo "[+] Phase 2: Optimized service scan"

sudo nmap -Pn -sS -p- \
  --open \
  ${TIMING} \
  --min-rate "$RATE" \
  --max-retries 2 \
  --host-timeout 10m \
  -iL alive.txt \
  -oX inventory_${DATE}.xml \
  -oN inventory_${DATE}.nmap

echo "[+] Converting XML to CSV"

if command -v nmaptocsv >/dev/null 2>&1; then
  nmaptocsv inventory_${DATE}.xml -o inventory_${DATE}.csv
else
  echo "[!] nmaptocsv not found. Install with:"
  echo "    pip install --user nmaptocsv"
fi

echo "[+] Scan complete"
echo "[+] Output directory: $OUTDIR"
ls -lh "$OUTDIR"
