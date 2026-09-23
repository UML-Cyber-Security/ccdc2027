#!/bin/bash
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root"
    exit
fi
read -s -p "Enter master hash: " MASTER_HASH
echo ""
if [ "$(uname)" == "FreeBSD" ]; then
    OS="freebsd"
elif [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    OS="unknown"
fi
change_password() {
    local username=$1
    if [[ "$username" == ccdc* || "$username" == ccsi* ]]; then                 # exclude accounts like blackteam here
        echo "Skipped: $username"
        return
    fi
    local derived_pass=$(echo "$MASTER_HASH:$username" | openssl dgst -sha256 | awk '{print $2}' | cut -c1-16)
    if [ "$OS" == "freebsd" ]; then
        echo "$derived_pass" | pw usermod "$username" -h 0
    else
        echo "$username:$derived_pass" | chpasswd
    fi
    echo "Changed: $username"
    sleep 2
}
change_password "root"
while IFS=: read -r username _ uid _ _ _ shell; do
    if [[ "$uid" -ge 1000 && "$shell" != */nologin && "$shell" != */false ]]; then
        change_password "$username"
    fi
done < /etc/passwd