#!/bin/bash

# Function to validate IP address
validate_ip() {
    local ip=$1
    local valid_ip_regex='^([0-9]{1,3}\.){3}[0-9]{1,3}$'
    
    if [[ ! $ip =~ $valid_ip_regex ]]; then
        return 1
    fi
    
    # Check each octet is between 0-255
    IFS='.' read -r -a octets <<< "$ip"
    for octet in "${octets[@]}"; do
        if ((octet < 0 || octet > 255)); then
            return 1
        fi
    done
    return 0
}

# Function to validate CIDR
validate_cidr() {
    local cidr=$1
    # Remove leading slash if present
    cidr=${cidr#/}
    
    if [[ ! $cidr =~ ^[0-9]+$ ]]; then
        return 1
    fi
    
    if ((cidr < 0 || cidr > 32)); then
        return 1
    fi
    return 0
}

# Ask about DHCP first
while true; do
    read -p "Enable DHCP? (y/n): " DHCP
    if [[ $DHCP == 'y' ]] || [[ $DHCP == 'n' ]]; then
        break
    else
        echo "Invalid input. Please enter 'y' or 'n'."
    fi
done

# Only ask for static configuration if DHCP is disabled
if [[ $DHCP == 'n' ]]; then
    # Ask user for IP
    while true; do
        read -p "Enter IP address (e.g., 192.168.1.59): " USER_IP
        if validate_ip "$USER_IP"; then
            break
        else
            echo "Invalid IP address. Please enter a valid IPv4 address."
        fi
    done

    # Ask user for CIDR
    while true; do
        read -p "Enter CIDR Range (e.g., 24 or /24): " CIDR
        # Remove leading slash if present
        CIDR=${CIDR#/}
        if validate_cidr "$CIDR"; then
            break
        else
            echo "Invalid CIDR. Please enter a number between 0 and 32."
        fi
    done

    # Ask for gateway
    while true; do
        read -p "Enter gateway IP: " GATEWAY
        if validate_ip "$GATEWAY"; then
            break
        else
            echo "Invalid gateway IP. Please enter a valid IPv4 address."
        fi
    done
fi

# Define output file
NETPLAN_FILE="/etc/netplan/50-cloud-init.yaml"

# Backup existing configuration
if [[ -f $NETPLAN_FILE ]]; then
    BACKUP_FILE="${NETPLAN_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
    echo "Backing up existing configuration to $BACKUP_FILE"
    sudo cp "$NETPLAN_FILE" "$BACKUP_FILE"
    if [[ $? -eq 0 ]]; then
        echo "Backup created successfully."
    else
        echo "Failed to create backup. Exiting for safety."
        exit 1
    fi
else
    echo "No existing netplan file found at $NETPLAN_FILE"
fi

# Create netplan configuration based on DHCP choice
if [[ $DHCP == 'y' ]]; then
    cat <<EOF | sudo tee $NETPLAN_FILE > /dev/null
network:
  version: 2
  ethernets:
    ens18:
      dhcp4: true
EOF
else
    cat <<EOF | sudo tee $NETPLAN_FILE > /dev/null
network:
  version: 2
  ethernets:
    ens18:
      dhcp4: false
      addresses:
        - $USER_IP/$CIDR
      routes:
        - to: default
          via: $GATEWAY
      nameservers:
        addresses:
          - 8.8.8.8
          - $GATEWAY
EOF
fi

echo ""
echo "Netplan configuration updated in $NETPLAN_FILE"
echo "Testing changes with 'netplan try' (you'll have 120 seconds to confirm)"
echo ""
sudo netplan try

# Check if netplan try was successful
if [[ $? -ne 0 ]]; then
    echo ""
    echo "Configuration test failed or was cancelled."
    echo "To restore backup, run: sudo cp $BACKUP_FILE $NETPLAN_FILE && sudo netplan apply"
    exit 1
fi

echo ""
echo "Configuration applied successfully!"
echo "Backup saved at: $BACKUP_FILE"