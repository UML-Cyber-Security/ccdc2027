#!/bin/bash

# WHAT THIS SCRIPT DOES: 

#prometheus + node exporter + grafana setup script
#should work for Ubuntu/Debian Linux

set -e

#update versions as needed
PROMETHEUS_VERSION="3.8.1"
NODE_EXPORTER_VERSION="1.10.2"
GRAFANA_VERSION="11.4.0"

INSTALL_DIR="$HOME"
PROMETHEUS_DIR="$INSTALL_DIR/prometheus-${PROMETHEUS_VERSION}.linux-amd64"
NODE_EXPORTER_DIR="$INSTALL_DIR/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64"


# Check if already installed

echo ""
echo "[0/6] checkinng for existing installations.."

ALREADY_INSTALLED=false

if systemctl is-active --quiet prometheus 2>/dev/null; then
    echo "  • Prometheus service is already running"
    ALREADY_INSTALLED=true
fi

if systemctl is-active --quiet node_exporter 2>/dev/null; then
    echo "  • Node Exporter service is already running"
    ALREADY_INSTALLED=true
fi

if systemctl is-active --quiet grafana-server 2>/dev/null; then
    echo "  • Grafana service is already running"
    ALREADY_INSTALLED=true
fi

if [ "$ALREADY_INSTALLED" = true ]; then
    echo ""
    echo "the services are already installed and running!!!!"
    echo ""
    echo "access the services here:"
    echo "  - prometheus:    http://localhost:9090"
    echo "  - node exporter: http://localhost:9100/metrics"
    echo "  - grafana:       http://localhost:3000"
    echo ""
    echo "UNINSTALL COMMANDS! (run these first if you want to reinstall):"
    echo "  STOP SERVICES:"
    echo "      pkill prometheus"
    echo "      pkill node_exporter"
    echo "      sudo systemctl stop grafana-server"
    echo "      sudo systemctl disable grafana-server"
    echo "  REMOVE GRAFANA:"
    echo "      sudo apt remove --purge grafana -y"
    echo "      sudo rm -rf /etc/grafana"
    echo "      sudo rm -rf /var/lib/grafana"
    echo "  REMOVE PROMETHEUS AND NODE EXPORTER FILES:"
    echo "      rm -rf ~/prometheus-*"
    echo "      rm -rf ~/node_exporter-*"
    echo "  REMOVE THE DEB FILE TOO:"
    echo "      rm -f ~/grafana_*.deb"
    echo ""
    exit 0
fi




#1. Download and Install Prometheus
echo ""
echo "[1/6] Downloading Prometheus v${PROMETHEUS_VERSION}..."
cd "$INSTALL_DIR"

if [ ! -f "prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz" ]; then
    wget -q --show-progress "https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz"
fi

if [ ! -d "$PROMETHEUS_DIR" ]; then
    tar xzf "prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz"
fi
echo ":) Prometheus downloaded and extracted"


# 2. Download and Install Node Exporter

echo ""
echo "[2/6] Downloading Node Exporter v${NODE_EXPORTER_VERSION}..."

if [ ! -f "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz" ]; then
    wget -q --show-progress "https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"
fi

if [ ! -d "$NODE_EXPORTER_DIR" ]; then
    tar xzf "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"
fi
echo ":) Node Exporter downloaded and extracted"

#3. Configure Prometheus

echo ""
echo "[3/6] Configuring Prometheus..."

cat > "$PROMETHEUS_DIR/prometheus.yml" << 'EOF'
# Prometheus configuration file

global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  # Scrape Prometheus itself
  - job_name: "prometheus"
    static_configs:
      - targets: ["localhost:9090"]

  # Scrape Node Exporter
  - job_name: "node"
    static_configs:
      - targets: ["localhost:9100"]
EOF

echo ":) Prometheus configured"

#4. Install Grafana

echo ""
echo "[4/6] Installing Grafana v${GRAFANA_VERSION}..."

sudo apt-get install -y adduser libfontconfig1 musl > /dev/null 2>&1

if [ ! -f "grafana_${GRAFANA_VERSION}_amd64.deb" ]; then
    wget -q --show-progress "https://dl.grafana.com/oss/release/grafana_${GRAFANA_VERSION}_amd64.deb"
fi

sudo dpkg -i "grafana_${GRAFANA_VERSION}_amd64.deb" > /dev/null 2>&1
echo ":) Grafana installed"


#5. Create systemd services for Prometheus and Node Exporter

echo ""
echo "[5/6] Creating systemd services (so they run permanently)..."

#edit config file to make a service for prometheus
sudo tee /etc/systemd/system/prometheus.service > /dev/null << EOF
[Unit]
Description=Prometheus Monitoring
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
ExecStart=${PROMETHEUS_DIR}/prometheus --config.file=${PROMETHEUS_DIR}/prometheus.yml --storage.tsdb.path=${PROMETHEUS_DIR}/data
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

#edit config file to make a service for node exporter
sudo tee /etc/systemd/system/node_exporter.service > /dev/null << EOF
[Unit]
Description=Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
ExecStart=${NODE_EXPORTER_DIR}/node_exporter
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

#reload systemd
sudo systemctl daemon-reload

echo ":) Systemd services created"


#6. Start and Enable Services
echo ""
echo "[6/6] Starting services..."

#Enable services to start when the system boots
sudo systemctl enable prometheus > /dev/null 2>&1
sudo systemctl enable node_exporter > /dev/null 2>&1
sudo systemctl enable grafana-server > /dev/null 2>&1

#Start services
sudo systemctl start node_exporter
echo ":) Node Exporter started (port 9100)"

sudo systemctl start prometheus
echo ":) Prometheus started (port 9090)"

sudo systemctl start grafana-server
echo ":) Grafana started (port 3000)"


#Done!!!!

echo ""
echo ":) Setup Complete!"
echo ""
echo "Access your services:"
echo "  • Prometheus:    http://localhost:9090"
echo "  • Node Exporter: http://localhost:9100/metrics"
echo "  • Grafana:       http://localhost:3000"
echo ""
echo "Grafana login: admin / admin"
echo ""
echo "Do this next:"
echo "  1. Add Prometheus data source (URL: http://localhost:9090)"
echo "  2. Import dashboard ID 1860 for Node Exporter metrics"
echo ""
echo "SSH tunnel command (if needed-accessing from home):"
echo "  ssh -L 9090:localhost:9090 -L 9100:localhost:9100 -L 3000:localhost:3000 user@your-vm"
echo ""
