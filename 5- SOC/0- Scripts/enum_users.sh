#!/bin/bash
OUTPUT="users.txt"
> "$OUTPUT"

echo "root" >> "$OUTPUT"

while IFS=: read -r username _ uid _ _ _ shell; do
    if [[ "$uid" -ge 1000 && "$shell" != */nologin && "$shell" != */false ]]; then
        echo "$username" >> "$OUTPUT"
    fi
done < /etc/passwd

echo "Users written to $OUTPUT"