#!/bin/bash

# WHAT THIS SCRIPT DOES: 
# Sets up a Linux client with Node Exporter, Promtail, and Falco to send metrics and logs to a SOC server for all linux machines.

# Usage: sudo ./setup-linux-client.sh <hostname> <soc_server_ip>

set -e

if [ "$EUID" -ne 0 ]; then
    echo "Please run as root"
    exit 1
fi

if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Usage: sudo $0 <hostname> <soc_server_ip>"
    exit 1
fi

HOSTNAME=$1
SOC_SERVER=$2
source /etc/os-release
# Install required tools
if [[ "$ID" == "ubuntu" || "$ID" == "debian" || "$ID_LIKE" == *"debian"* ]]; then
    apt-get update -y
    apt-get install -y curl wget unzip gnupg
elif [[ "$ID_LIKE" == *"rhel"* || "$ID" == "rocky" || "$ID" == "almalinux" || "$ID" == "centos" ]]; then
    dnf install -y curl wget unzip gnupg2 || yum install -y curl wget unzip gnupg2
fi

echo "=== Setting up monitoring for: $HOSTNAME ==="

# Install Node Exporter
echo "[1/4] Installing Node Exporter..."
cd /tmp
wget -q https://github.com/prometheus/node_exporter/releases/download/v1.7.0/node_exporter-1.7.0.linux-amd64.tar.gz
tar xzf node_exporter-1.7.0.linux-amd64.tar.gz
mv node_exporter-1.7.0.linux-amd64/node_exporter /usr/local/bin/
chmod +x /usr/local/bin/node_exporter

tee /etc/systemd/system/node_exporter.service > /dev/null <<EOF
[Unit]
Description=Node Exporter
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/node_exporter
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now node_exporter

# Install Promtail
echo "[2/4] Installing Promtail..."
wget -q https://github.com/grafana/loki/releases/download/v2.9.3/promtail-linux-amd64.zip
unzip -o promtail-linux-amd64.zip
mv promtail-linux-amd64 /usr/local/bin/promtail
chmod +x /usr/local/bin/promtail
mkdir -p /etc/promtail /var/lib/promtail

tee /etc/promtail/config.yml > /dev/null <<EOF
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /var/lib/promtail/positions.yaml

clients:
  - url: http://${SOC_SERVER}:3100/loki/api/v1/push

scrape_configs:
  - job_name: varlogs
    static_configs:
      - targets:
          - localhost
        labels:
          job: varlogs
          host: ${HOSTNAME}
          __path__: /var/log/*.log

  - job_name: syslog
    static_configs:
      - targets:
          - localhost
        labels:
          job: syslog
          host: ${HOSTNAME}
          __path__: /var/log/syslog

      - targets:
          - localhost
        labels:
          job: syslog
          host: ${HOSTNAME}
          __path__: /var/log/messages

  - job_name: auth
    static_configs:
      - targets:
          - localhost
        labels:
          job: auth
          host: ${HOSTNAME}
          __path__: /var/log/auth.log

      - targets:
          - localhost
        labels:
          job: auth
          host: ${HOSTNAME}
          __path__: /var/log/secure

  - job_name: falco
    static_configs:
      - targets:
          - localhost
        labels:
          job: falco
          host: ${HOSTNAME}
          __path__: /var/log/falco/*.json

  - job_name: auditd
    static_configs:
      - targets:
          - localhost
        labels:
          job: auditd
          host: ${HOSTNAME}
          __path__: /var/log/audit/audit.log

  - job_name: sysmon
    journal:
      matches: SYSLOG_IDENTIFIER=sysmon
    relabel_configs:
      - source_labels: [__journal__hostname]
        target_label: host
        replacement: ${HOSTNAME}
      - target_label: job
        replacement: sysmon
EOF

tee /etc/systemd/system/promtail.service > /dev/null <<EOF
[Unit]
Description=Promtail
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/promtail -config.file=/etc/promtail/config.yml
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now promtail

# Install Falco
echo "[3/4] Installing Falco..."

if [[ "$ID" == "debian" || "$ID" == "ubuntu" || "$ID_LIKE" == *"debian"* ]]; then
    # trust the falcosecurity GPG key
    curl -fsSL https://falco.org/repo/falcosecurity-packages.asc | \
    gpg --dearmor -o /usr/share/keyrings/falco-archive-keyring.gpg

    # configure apt repository
    echo "deb [signed-by=/usr/share/keyrings/falco-archive-keyring.gpg] https://download.falco.org/packages/deb stable main" | \
    tee -a /etc/apt/sources.list.d/falcosecurity.list

    apt-get update -y

    # install falco package
    apt-get install -y falco
elif [[ "$ID" == "rhel" || "$ID" == "rocky" || "$ID" == "almalinux" || "$ID" == "centos" || "$ID_LIKE" == *"rhel"* ]]; then
    # trust the falcosecurity GPG key
    rpm --import https://falco.org/repo/falcosecurity-packages.asc

    # configure yum repository
    curl -o /etc/yum.repos.d/falcosecurity.repo https://falco.org/repo/falcosecurity-rpm.repo

    yum update -y

    # install falco package
    yum install -y falco
fi

mkdir -p /var/log/falco /etc/falco/config.d
tee /etc/falco/config.d/custom-output.yaml > /dev/null <<EOF
json_output: true
json_include_output_property: true

file_output:
  enabled: true
  keep_alive: false
  filename: /var/log/falco/alerts.json
EOF

systemctl enable falco-modern-bpf 2>/dev/null || systemctl enable falco
systemctl restart falco-modern-bpf 2>/dev/null || systemctl restart falco

# Install rsyslog if needed
echo "[4/4] Ensuring rsyslog is installed..."
if [ "$ID_LIKE" == *"debian"* ]; then 
    apt install -y rsyslog 2>/dev/null
elif [ "$ID_LIKE" == *"rhel"* ]; then
    yum install -y rsyslog 2>/dev/null
fi

systemctl enable --now rsyslog 2>/dev/null
systemctl start rsyslog.service 2>/dev/null

echo ""
echo "=== Setup Complete for $HOSTNAME ==="
echo "Node Exporter: http://$(hostname -I | awk '{print $1}'):9100"
echo "Promtail: http://$(hostname -I | awk '{print $1}'):9080"