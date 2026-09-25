#!/bin/bash

#********************************
# Written by Michael Leahy
# Last Updated: March 8, 2026
#********************************

set -e

# Check if the script is ran as root.
if [ "$EUID" -ne 0 ]
  then echo "This script must be run as root."
  exit 1
fi

source /etc/os-release

if [[ "$ID" == "debian" ]]; then
    # register Microsoft key and feed
    wget -q https://packages.microsoft.com/config/debian/$(. /etc/os-release && echo ${VERSION_ID%%.*})/packages-microsoft-prod.deb -O packages-microsoft-prod.deb
    dpkg -i packages-microsoft-prod.deb

    # install sysmon
    apt-get update -y
    apt-get install -y sysmonforlinux

elif [[ "$ID" == "ubuntu" ]]; then
    # register Microsoft key and feed
    wget -q https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/packages-microsoft-prod.deb -O packages-microsoft-prod.deb
    dpkg -i packages-microsoft-prod.deb

    # install sysmon
    apt-get update -y
    apt-get install -y sysmonforlinux

elif [[ "$ID_LIKE" == *"rhel"* ]]; then
    # register Microsoft key and feed
    rpm -Uvh https://packages.microsoft.com/config/rhel/$(. /etc/os-release && echo ${VERSION_ID%%.*})/packages-microsoft-prod.rpm

    # install sysmon
    yum install -y sysmonforlinux

else
    echo "Unsupported OS. Exiting..."
    exit 1
fi

# Create config
mkdir -p /etc/sysmon
cat > /etc/sysmon/config.xml << 'EOF'
<Sysmon schemaversion="4.70">
  <EventFiltering>
    <!-- Log all process creation (Event ID 1) -->
    <RuleGroup name="" groupRelation="or">
      <ProcessCreate onmatch="include">
        <Rule groupRelation="or">
          <Image condition="begin with">/</Image>
        </Rule>
      </ProcessCreate>
    </RuleGroup>
    
    <!-- Log all network connections (Event ID 3) -->
    <RuleGroup name="" groupRelation="or">
      <NetworkConnect onmatch="include">
        <Rule groupRelation="or">
          <Image condition="begin with">/</Image>
        </Rule>
      </NetworkConnect>
    </RuleGroup>
  </EventFiltering>
</Sysmon>
EOF

#  Initialize Sysmon
sysmon -accepteula -i /etc/sysmon/config.xml

# Enable and start
systemctl enable sysmon
systemctl start sysmon