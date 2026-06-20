#!/bin/bash

#*************************
# Written by Michael Leahy
# Last Updated: February 20, 2026
#*************************

# WHAT THIS SCRIPT DOES: This script sets up TLS for the Grafana webpage

# Check if the script is ran as root.
if [ "$EUID" -ne 0 ] || [ -z "$1" ]; then
  echo "Usage sudo ./$0 <soc_server_ip>"
  exit 1
fi

set -e

SOC_IP=$1

openssl req -x509 -new -nodes -keyout local-ca.key -out local-ca.crt -days 3650 -sha256 -subj "/C=US/O=CCDC/CN=CCDC Root CA"

apt-get install -y ca-certificates

cp local-ca.crt /usr/local/share/ca-certificates

update-ca-certificates

mkdir -p /etc/grafana/certs
openssl genrsa -out /etc/grafana/certs/grafana.key 2048

cat << EOF > /etc/grafana/grafana.cnf
[req]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
req_extensions = req_ext

[dn]
C = US
O = CCDC
CN = ${SOC_IP}

[req_ext]
subjectAltName = @alt_names

[alt_names]
IP.1 = ${SOC_IP}
EOF

openssl req -new -key /etc/grafana/certs/grafana.key -out /etc/grafana/grafana.csr -config /etc/grafana/grafana.cnf

openssl x509 -req \
-in /etc/grafana/grafana.csr \
-CA local-ca.crt \
-CAkey local-ca.key \
-CAcreateserial \
-out /etc/grafana/certs/grafana.crt \
-days 365 \
-sha256 \
-extfile /etc/grafana/grafana.cnf \
-extensions req_ext

chown -R grafana:grafana /etc/grafana/certs/
chmod 700 /etc/grafana/certs
chmod 600 /etc/grafana/certs/grafana.key

sed -i "/^\[server\]/,/^\[.*\]/ s|^;*protocol *=.*|protocol = https|" /etc/grafana/grafana.ini
sed -i "/^\[server\]/,/^\[.*\]/ s|^;*domain *=.*|domain = ${SOC_IP}|" /etc/grafana/grafana.ini
sed -i "/^\[server\]/,/^\[.*\]/ s|^;*cert_file *=.*|cert_file = /etc/grafana/certs/grafana.crt|" /etc/grafana/grafana.ini
sed -i "/^\[server\]/,/^\[.*\]/ s|^;*cert_key *=.*|cert_key = /etc/grafana/certs/grafana.key|" /etc/grafana/grafana.ini

systemctl restart grafana-server.service
systemctl status grafana-server.service
