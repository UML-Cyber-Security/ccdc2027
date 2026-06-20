#!/usr/bin/env bash

# Usage: ./script.sh -t user@example.com -s "Alert" -b "Issue detected" -f "ccdc-node1"

# -t:  send address
# -s, -b:    subject and body of message
# f:    from, sets the user identity
set -euo pipefail

TO=""
SUBJECT=""
BODY=""
FROM=""

while getopts "t:s:b:f:" opt; do
  case $opt in
    t) TO="$OPTARG" ;;
    s) SUBJECT="$OPTARG" ;;
    b) BODY="$OPTARG" ;;
    f) FROM="$OPTARG" ;;
    *) echo "Usage: $0 -t to -s subject -b body [-f from]"
       exit 1 ;;
  esac
done

if [[ -z "$TO" || -z "$SUBJECT" || -z "$BODY" ]]; then
  echo "Missing required arguments"
  exit 1
fi

# Default sender if not provided
if [[ -z "$FROM" ]]; then
  FROM="ccdc-alert"
fi

{
echo "From: $FROM"
echo "To: $TO"
echo "Subject: $SUBJECT"
echo ""
echo "$BODY"
} | /usr/sbin/sendmail -t -f "$FROM"

echo "[+] Email sent"