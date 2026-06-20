#!/bin/bash

# WHAT THIS SCRIPT DOES:
# Installs Grafana Loki v2.9.3 as a systemd service for log aggregation on port 3100.
# Last Updated: February 21, 2026

# Download and install Loki
cd /tmp
wget https://github.com/grafana/loki/releases/download/v2.9.3/loki-linux-amd64.zip
sudo apt install -y unzip
unzip loki-linux-amd64.zip
sudo mv loki-linux-amd64 /usr/local/bin/loki
sudo chmod +x /usr/local/bin/loki

# Create directories
sudo mkdir -p /etc/loki /var/lib/loki


sudo tee /etc/loki/loki-config.yaml <<'EOF'
auth_enabled: false

server:
  http_listen_port: 3100
  grpc_listen_port: 9096

common:
  instance_addr: 127.0.0.1
  path_prefix: /var/lib/loki
  storage:
    filesystem:
      chunks_directory: /var/lib/loki/chunks
      rules_directory: /var/lib/loki/rules
  replication_factor: 1
  ring:
    kvstore:
      store: inmemory

schema_config:
  configs:
    - from: 2020-10-24
      store: boltdb-shipper
      object_store: filesystem
      schema: v11
      index:
        prefix: index_
        period: 24h

limits_config:
  reject_old_samples: true
  reject_old_samples_max_age: 168h
  volume_enabled: true
EOF


sudo tee /etc/systemd/system/loki.service <<'EOF'
[Unit]
Description=Loki Log Aggregation
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/loki -config.file=/etc/loki/loki-config.yaml
Restart=always

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now loki
sudo systemctl status loki
