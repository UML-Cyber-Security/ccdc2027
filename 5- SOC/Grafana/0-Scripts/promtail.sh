#!/bin/bash

# WHAT THIS SCRIPT DOES:
# Installs Promtail v2.9.3 as a systemd service to ship logs to Loki on port 9080.

# Download Promtail
cd /tmp
wget https://github.com/grafana/loki/releases/download/v2.9.3/promtail-linux-amd64.zip
unzip -o promtail-linux-amd64.zip
sudo mv promtail-linux-amd64 /usr/local/bin/promtail
sudo chmod +x /usr/local/bin/promtail

# Create directories
sudo mkdir -p /etc/promtail /var/lib/promtail

sudo tee /etc/promtail/config.yaml <<'EOF'
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /var/lib/promtail/positions.yaml

clients:
  - url: http://localhost:3100/loki/api/v1/push

scrape_configs:
  - job_name: varlogs
    static_configs:
      - targets:
          - localhost
        labels:
          job: varlogs
          host: soc-server
          __path__: /var/log/*.log

  - job_name: syslog
    static_configs:
      - targets:
          - localhost
        labels:
          job: syslog
          host: soc-server
          __path__: /var/log/syslog

  - job_name: auth
    static_configs:
      - targets:
          - localhost
        labels:
          job: auth
          host: soc-server
          __path__: /var/log/auth.log

  - job_name: auditd
    static_configs:
      - targets:
          - localhost
        labels:
          job: auditd
          host: soc-server
          __path__: /var/log/audit/audit.log
        
  - job_name: sysmon
    journal:
      matches: SYSLOG_IDENTIFIER=sysmon
    relabel_configs:
      - source_labels: [__journal__hostname]
        target_label: host
        replacement: soc-server
      - target_label: job
        replacement: sysmon
EOF

sudo tee /etc/systemd/system/promtail.service <<'EOF'
[Unit]
Description=Promtail Log Agent
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/promtail -config.file=/etc/promtail/config.yaml
Restart=always

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now promtail
sudo systemctl status promtail
