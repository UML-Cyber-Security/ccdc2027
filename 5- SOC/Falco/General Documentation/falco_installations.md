# falco installation instructions

---

## OS compatibilities and drivers

  Debian 11/12                  ->  modern_ebpf  ->  falco-modern-bpf
  Ubuntu 20.04  (no SecureBoot) ->  kmod         ->  falco-kmod
  Ubuntu 20.04  (SecureBoot ON) ->  ebpf         ->  falco-bpf
  Mint 20.1     (no SecureBoot) ->  kmod         ->  falco-kmod
  Mint 20.1     (SecureBoot ON) ->  ebpf         ->  falco-bpf
  Rocky 9.3                     ->  modern_ebpf  ->  falco-modern-bpf
  Fedora 29                     ->  kmod         ->  falco-kmod
  FreeBSD 13.1                  ->  NOT SUPPORTED

---

# INSTALL

## Debian / Ubuntu / Mint

### 1. Add GPG key
```bash
curl -fsSL https://falco.org/repo/falcosecurity-packages.asc | \
  sudo gpg --dearmor -o /usr/share/keyrings/falco-archive-keyring.gpg
```

### 2. Add repo
```bash
echo "deb [signed-by=/usr/share/keyrings/falco-archive-keyring.gpg] \
  https://download.falco.org/packages/deb stable main" | \
  sudo tee /etc/apt/sources.list.d/falcosecurity.list
```

### 3. Install headers + Falco
```bash
sudo apt install -y linux-headers-$(uname -r)
sudo apt update && sudo apt install -y falco
```

### 4. Check Secure Boot
```bash
mokutil --sb-state
```

### 5a. SecureBoot DISABLED -> use kmod
```bash
sudo systemctl enable falco-kmod --now
```

### 5b. SecureBoot ENABLED -> use ebpf
```bash
sudo rm /etc/systemd/system/falco.service

sudo tee /etc/falco/config.d/engine-kind-falcoctl.yaml <<EOF
engine:
  kind: ebpf
EOF

sudo systemctl daemon-reload
sudo systemctl enable falco-bpf --now
```

---

## Rocky 9.3 / Fedora 29

### 1. Import GPG key
```bash
sudo rpm --import https://falco.org/repo/falcosecurity-packages.asc
```

### 2. Add repo
```bash
sudo tee /etc/yum.repos.d/falcosecurity.repo <<EOF
[falcosecurity]
name=falcosecurity
baseurl=https://download.falco.org/packages/rpm
enabled=1
gpgcheck=1
gpgkey=https://falco.org/repo/falcosecurity-packages.asc
EOF
```

### 3. Install headers + Falco
```bash
sudo dnf install -y falco kernel-devel-$(uname -r)
```

### 4. Enable service
```bash
# Rocky 9.3:
sudo systemctl enable falco-modern-bpf --now

# Fedora 29:
sudo systemctl enable falco-kmod --now
```

---

# VERIFY

Check status      ->  `sudo systemctl status falco-<SERVICE>`
Watch live alerts ->  `sudo journalctl -fu falco-<SERVICE>`
Test trigger      ->  `cat /etc/shadow`  (fires a Warning alert)

Not sure which service? -> `systemctl list-units | grep falco`

---

# KEY FILES

  /etc/falco/falco.yaml              ->  main config
  /etc/falco/config.d/               ->  drop-in overrides
  /etc/falco/falco_rules.yaml        ->  built-in rules  (DO NOT EDIT)
  /etc/falco/falco_rules.local.yaml  ->  your custom rules

---

# TROUBLESHOOTING

## Crashes on start -- "undefined symbol: __res_search"

Affects: Debian 11 + Falco 0.43+
Cause:   libcontainer.so incompatible with Debian 11 glibc

```bash
sudo mv /etc/falco/config.d/falco.container_plugin.yaml \
        /etc/falco/falco.container_plugin.yaml.disabled

grep -n "libcontainer\|load_plugins" /etc/falco/falco.yaml
sudo nano /etc/falco/falco.yaml
# comment out the container plugin block
# set load_plugins: []

sudo systemctl restart falco-modern-bpf
```

Note: rules still work, you just lose container metadata on alerts.

---

## kmod blocked -- "Operation not permitted"

Affects: any system with Secure Boot enabled
Cause:   kernel lockdown blocks unsigned modules

```bash
# confirm:
mokutil --sb-state          # SecureBoot enabled
sudo dmesg | grep lockdown  # unsigned module loading is restricted

# fix -- switch to ebpf:
sudo rm /etc/systemd/system/falco.service

sudo tee /etc/falco/config.d/engine-kind-falcoctl.yaml <<EOF
engine:
  kind: ebpf
EOF

sudo systemctl daemon-reload
sudo systemctl enable falco-bpf --now
```

---

## "Failed to enable unit: File already exists"

Cause: stale symlink from previous install

```bash
sudo rm /etc/systemd/system/falco.service
sudo systemctl daemon-reload
sudo systemctl enable falco-<DRIVER> --now
```

---

## falcoctl.yaml prompt during upgrade

```
Y  ->  take new version    (use if no custom config)
N  ->  keep your version   (use if you customized it)
D  ->  show diff           (use if unsure)
```

---

## GPG error on apt update

Cause: key rotated Dec 2025

```bash
curl -fsSL https://falco.org/repo/falcosecurity-packages.asc | \
  sudo gpg --dearmor -o /usr/share/keyrings/falco-archive-keyring.gpg
sudo apt update
```

---

# PROMTAIL INTEGRATION

## Unit name by OS

  Debian 11/12       modern_ebpf  ->  _SYSTEMD_UNIT=falco-modern-bpf.service
  Ubuntu 20.04 no SB kmod         ->  _SYSTEMD_UNIT=falco-kmod.service
  Ubuntu 20.04 SB    ebpf         ->  _SYSTEMD_UNIT=falco-bpf.service
  Mint 20.1 no SB    kmod         ->  _SYSTEMD_UNIT=falco-kmod.service
  Mint 20.1 SB       ebpf         ->  _SYSTEMD_UNIT=falco-bpf.service
  Rocky 9.3          modern_ebpf  ->  _SYSTEMD_UNIT=falco-modern-bpf.service
  Fedora 29          kmod         ->  _SYSTEMD_UNIT=falco-kmod.service

Confirm yours: `systemctl list-units | grep falco`

---

## Option 1 -- Journald (recommended, no Falco changes needed)

```yaml
# /etc/promtail/promtail.yaml

server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /tmp/positions.yaml

clients:
  - url: http://<LOKI_HOST>:3100/loki/api/v1/push

scrape_configs:
  - job_name: falco
    journal:
      matches: _SYSTEMD_UNIT=falco-modern-bpf.service   # <-- change per OS
      labels:
        job: falco
        host: <HOSTNAME>
    relabel_configs:
      - source_labels: [__journal__priority_keyword]
        target_label: level
```

---

## Option 2 -- File output

Add to `/etc/falco/falco.yaml`:
```yaml
file_output:
  enabled: true
  keep_alive: false
  filename: /var/log/falco/falco.log
```

```bash
sudo mkdir -p /var/log/falco
sudo systemctl restart falco-modern-bpf
```

Promtail config:
```yaml
scrape_configs:
  - job_name: falco
    static_configs:
      - targets: [localhost]
        labels:
          job: falco
          host: <HOSTNAME>
          __path__: /var/log/falco/falco.log
    pipeline_stages:
      - regex:
          expression: '.*(?P<level>Emergency|Alert|Critical|Error|Warning|Notice|Informational|Debug).*'
      - labels:
          level:
```

---

## Option 3 -- JSON output (best for Loki queries)

Add to `/etc/falco/falco.yaml`:
```yaml
json_output: true
json_include_output_property: true
```

```bash
sudo systemctl restart falco-modern-bpf
```

Promtail config:
```yaml
scrape_configs:
  - job_name: falco
    journal:
      matches: _SYSTEMD_UNIT=falco-modern-bpf.service   # <-- change per OS
      labels:
        job: falco
        host: <HOSTNAME>
    pipeline_stages:
      - json:
          expressions:
            priority: priority
            rule: rule
            output: output
      - labels:
          priority:
          rule:
      - output:
          source: output
```

Loki queries unlocked:
```
{job="falco", priority="Warning"}
{job="falco", rule="Read sensitive file untrusted"}
```

---

## Promtail Troubleshooting

No logs in Loki:
```bash
systemctl list-units | grep falco        # confirm unit name
curl http://<LOKI_HOST>:3100/ready       # confirm Loki reachable
cat /tmp/positions.yaml                  # check position tracking
```

Permission error reading journal:
```bash
sudo usermod -aG systemd-journal promtail
sudo systemctl restart promtail
```

Duplicate logs:
```bash
sudo rm /tmp/positions.yaml
sudo systemctl restart promtail
```