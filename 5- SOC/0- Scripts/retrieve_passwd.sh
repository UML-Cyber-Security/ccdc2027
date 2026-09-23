#!/bin/bash
read -s -p "Enter master hash: " MASTER_HASH
echo ""
read -p "Enter input file (one username per line): " INFILE

> changed_passwds

while IFS= read -r USERNAME; do
    if [[ -n "$USERNAME" ]]; then
        derived=$(echo "$MASTER_HASH:$USERNAME" | openssl dgst -sha256 | awk '{print $2}' | cut -c1-16)
        echo "$USERNAME,$derived" >> changed_passwds
    fi
done < "$INFILE"

echo "Passwords written to changed_passwds"