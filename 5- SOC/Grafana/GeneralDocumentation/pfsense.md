# Promtail on pfSense — Full Installation Guide

## Step 1 — SSH into pfSense

```bash
ssh admin@<your-pfsense-ip>
```

---

## Step 2 — Download Promtail

```bash
# Install unzip if not already present
pkg install -y unzip

# Download Promtail v2.9.3 FreeBSD binary
fetch https://github.com/grafana/loki/releases/download/v2.9.3/promtail-freebsd-amd64.zip

# Unzip and install
unzip promtail-freebsd-amd64.zip
chmod +x promtail-freebsd-amd64
mv promtail-freebsd-amd64 /usr/local/bin/promtail

# Verify it works
promtail --version
```

---

## Step 3 — Create Config Directory and File

```bash
mkdir -p /usr/local/etc/promtail
vi /usr/local/etc/promtail/config.yml
```

Paste the entire config below. In vi: press `i` to insert, paste, then `:wq` to save.

```yaml
server:
  http_listen_port: 9081
  grpc_listen_port: 0

positions:
  filename: /var/log/promtail-positions.yaml

clients:
  - url: http://192.168.4.215:3100/loki/api/v1/push

scrape_configs:

  # ─── FIREWALL ────────────────────────────────────────────────────────────────
  - job_name: pfsense_firewall
    static_configs:
      - targets:
          - localhost
        labels:
          job: pfsense_firewall
          host: pfsense
          __path__: /var/log/filter.log

  # ─── SYSTEM ──────────────────────────────────────────────────────────────────
  - job_name: pfsense_system
    static_configs:
      - targets:
          - localhost
        labels:
          job: pfsense
          host: pfsense
          __path__: /var/log/system.log

  # ─── DHCP ────────────────────────────────────────────────────────────────────
  - job_name: pfsense_dhcp
    static_configs:
      - targets:
          - localhost
        labels:
          job: pfsense_dhcp
          host: pfsense
          __path__: /var/log/dhcpd.log

  # ─── NGINX (Web GUI) ─────────────────────────────────────────────────────────
  - job_name: pfsense_nginx
    static_configs:
      - targets:
          - localhost
        labels:
          job: pfsense_nginx
          host: pfsense
          __path__: /var/log/nginx.log

  # ─── OPENVPN ─────────────────────────────────────────────────────────────────
  - job_name: pfsense_openvpn
    static_configs:
      - targets:
          - localhost
        labels:
          job: pfsense_openvpn
          host: pfsense
          __path__: /var/log/openvpn.log

  # ─── IPSEC ───────────────────────────────────────────────────────────────────
  - job_name: pfsense_ipsec
    static_configs:
      - targets:
          - localhost
        labels:
          job: pfsense_ipsec
          host: pfsense
          __path__: /var/log/ipsec.log

  # ─── PPP / PPPoE ─────────────────────────────────────────────────────────────
  - job_name: pfsense_ppp
    static_configs:
      - targets:
          - localhost
        labels:
          job: pfsense_ppp
          host: pfsense
          __path__: /var/log/ppp.log

  # ─── DNS RESOLVER (Unbound) ──────────────────────────────────────────────────
  - job_name: pfsense_resolver
    static_configs:
      - targets:
          - localhost
        labels:
          job: pfsense_resolver
          host: pfsense
          __path__: /var/log/resolver.log

  # ─── SURICATA IDS (only if Suricata package is installed) ────────────────────
  - job_name: pfsense_suricata
    static_configs:
      - targets:
          - localhost
        labels:
          job: pfsense_suricata
          host: pfsense
          __path__: /var/log/suricata/*.log

  # ─── SQUID PROXY (only if Squid package is installed) ────────────────────────
  - job_name: pfsense_squid
    static_configs:
      - targets:
          - localhost
        labels:
          job: pfsense_squid
          host: pfsense
          __path__: /var/log/squid/*.log
```

---

## Step 4 — Test the Config

Run Promtail manually first to confirm no errors:

```bash
promtail -config.file=/usr/local/etc/promtail/config.yml
```

You should see lines like:
```
level=info ... msg="Adding target" key="/var/log/filter.log:..."
level=info ... msg="Adding target" key="/var/log/system.log:..."
...
```

No `level=error` lines means it's working. Press `Ctrl+C` to stop.

> **Note:** Warnings about missing log files (suricata, squid, openvpn etc.)
> are normal if those packages aren't installed — Promtail will just skip them.

---

## Step 5 — Create the RC Startup Service

This makes Promtail start automatically on every boot:

```bash
vi /usr/local/etc/rc.d/promtail
```

Paste this:

```sh
#!/bin/sh
# PROVIDE: promtail
# REQUIRE: NETWORKING
# KEYWORD: shutdown

. /etc/rc.subr

name="promtail"
rcvar="promtail_enable"
command="/usr/local/bin/promtail"
command_args="-config.file=/usr/local/etc/promtail/config.yml >> /var/log/promtail.log 2>&1 &"
pidfile="/var/run/promtail.pid"

load_rc_config $name
: ${promtail_enable:=no}

run_rc_command "$1"
```

```bash
# Make it executable
chmod +x /usr/local/etc/rc.d/promtail

# Enable it
echo 'promtail_enable="YES"' >> /etc/rc.conf.local

# Start it
service promtail start
```

---

## Step 6 — Verify It's Running

```bash
# Check the process is alive
pgrep -l promtail

# Watch the log
tail -f /var/log/promtail.log

# Check it can reach Loki
curl http://192.168.4.215:3100/ready
# Should return: ready
```

---

## Step 7 — Survive pfSense Updates

pfSense firmware updates wipe `/usr/local`. To protect against this:

1. Go to **System → Package Manager** in the pfSense GUI
2. Install the **shellcmd** package
3. Go to **Services → Shellcmd**
4. Add a new command:
   - **Command:** `/usr/local/bin/promtail -config.file=/usr/local/etc/promtail/config.yml &`
   - **Type:** `afterfilterload`

This re-launches Promtail after every boot even if the rc.d script gets wiped.

---

## Useful Commands

```bash
# Stop Promtail
kill $(pgrep promtail)

# Restart Promtail
kill $(pgrep promtail); sleep 1; /usr/local/bin/promtail -config.file=/usr/local/etc/promtail/config.yml &

# Check what's listening on 9081
sockstat -l | grep 9081

# See what log files are available
ls /var/log/*.log

# Test Loki connectivity
curl http://192.168.4.215:3100/ready
```

---

## Logs Being Collected

| Job Label | Log File | What It Contains |
|---|---|---|
| `pfsense_firewall` | `/var/log/filter.log` | All firewall pass/block events |
| `pfsense` | `/var/log/system.log` | SSH, sudo, kernel, service events |
| `pfsense_dhcp` | `/var/log/dhcpd.log` | DHCP leases and device connections |
| `pfsense_nginx` | `/var/log/nginx.log` | Web GUI access and errors |
| `pfsense_openvpn` | `/var/log/openvpn.log` | VPN connections (if used) |
| `pfsense_ipsec` | `/var/log/ipsec.log` | IPsec tunnels (if used) |
| `pfsense_ppp` | `/var/log/ppp.log` | WAN/PPPoE events (if used) |
| `pfsense_resolver` | `/var/log/resolver.log` | DNS queries via Unbound |
| `pfsense_suricata` | `/var/log/suricata/*.log` | IDS alerts (if installed) |
| `pfsense_squid` | `/var/log/squid/*.log` | Proxy logs (if installed) |
