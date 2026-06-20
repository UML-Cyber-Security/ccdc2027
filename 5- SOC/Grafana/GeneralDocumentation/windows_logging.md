# How To Deploy Windows Event Logging with Promtail → Loki

**Author:** Sanjeev Shankar Vijaya Sankar  
**Last Updated:** March 13, 2026

---

## Overview

This document details how to configure Windows Event Log ingestion into Loki using Promtail. The setup allows Windows Sysmon and Security logs to be shipped to a centralized Loki logging server for SOC visibility and investigation in Grafana.

---

## Prerequisites

- Ensure the Loki server is reachable over the network.
- Ensure port `3100` is open to the Loki server.
- If Loki is behind pfSense, create a NAT port forward and firewall rule.
- Ensure the Windows server and Loki server have synchronized system time.
- Confirm Loki is running:

```bash
sudo systemctl status loki
```

---

## Loki Server Verification

Before configuring Windows logging, confirm the Loki server is operational.

Verify the Loki version:

```bash
loki --version
```

Confirm Loki is listening on port 3100:

```bash
sudo ss -tulpn | grep 3100
```

Expected output should include:

```
*:3100
```

Confirm Loki is healthy:

```bash
curl http://localhost:3100/ready
```

Expected output:

```
ready
```

---

## Windows Client Setup

### 1. Download Promtail

Navigate to the Loki GitHub releases page:

```
https://github.com/grafana/loki/releases
```

Download the file corresponding to the Loki version running on the server.

Example:

```
promtail-windows-amd64.exe.zip
```

Extract the archive and rename the executable:

```
promtail-windows-amd64.exe → promtail.exe
```

### 2. Create Directory Structure

Create the following directories on the Windows server:

```
C:\Promtail
C:\Promtail\config
C:\Promtail\data
```

Move `promtail.exe` into:

```
C:\Promtail
```

### 3. Create the Promtail Configuration File

Open Notepad as Administrator and create:

```
C:\Promtail\config\promtail-windows.yaml
```

If the file is saved as `.txt`, rename it with PowerShell:

```powershell
Rename-Item promtail-windows.yaml.txt promtail-windows.yaml
```

### 4. Promtail Configuration

Add the following configuration:

```yaml
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: C:/Promtail/data/positions.yaml

clients:
  - url: http://<LOKI_ENDPOINT>:3100/loki/api/v1/push
    tenant_id: fake

scrape_configs:

  - job_name: windows-sysmon
    windows_events:
      eventlog_name: "Microsoft-Windows-Sysmon/Operational"
      bookmark_path: C:/Promtail/data/sysmon-bookmark.xml
      poll_interval: 3s
      labels:
        job: windows-sysmon
        instance: ${COMPUTERNAME}

  - job_name: windows-security
    windows_events:
      eventlog_name: "Security"
      bookmark_path: C:/Promtail/data/security-bookmark.xml
      poll_interval: 3s
      labels:
        job: windows-security
        instance: ${COMPUTERNAME}
```

Replace `<LOKI_ENDPOINT>` with the address used to reach the Loki server.

**Examples:**

Direct internal network:

```
http://10.0.2.53:3100/loki/api/v1/push
```

If Loki is behind pfSense:

```
http://<pfsense_public_ip>:3100/loki/api/v1/push
```

---

## pfSense Configuration (If Loki Is Behind Firewall)

If Loki resides on a private network, pfSense must forward traffic to it.

### NAT Port Forward

Navigate to:

```
Firewall → NAT → Port Forward
```

Create rule:

| Setting | Value |
|---|---|
| Interface | WAN |
| Protocol | TCP |
| Destination | WAN Address |
| Destination Port | 3100 |
| Redirect Target IP | 10.0.2.53 |
| Redirect Target Port | 3100 |

This forwards:

```
pfSense_WAN_IP:3100 → 10.0.2.53:3100
```

### Firewall Rule

Ensure a firewall rule allows access to the port.

Navigate to:

```
Firewall → Rules → WAN
```

Create or confirm a rule allowing:

| Field | Value |
|---|---|
| Action | Pass |
| Protocol | TCP |
| Source | Windows public IP |
| Destination | WAN Address |
| Destination Port | 3100 |

---

## Network Connectivity Verification

Before running Promtail, verify connectivity from Windows:

```powershell
Test-NetConnection <LOKI_ENDPOINT_IP> -Port 3100
```

Expected output:

```
TcpTestSucceeded : True
```

If this fails, verify:

- pfSense NAT configuration
- pfSense firewall rules
- Loki service status
- Network routing

---

## Time Synchronization Verification

Logging systems rely on consistent timestamps. Ensure the Windows server and Loki server have synchronized time.

**On Windows:**

```powershell
Get-Date
Get-TimeZone
```

If the timezone is incorrect, change it:

```powershell
Set-TimeZone -Id "Eastern Standard Time"
```

> **Note:** Changing timezone does not modify the system clock and will not break TLS certificates.

**On the Loki server:**

```bash
date
```

The times should match within a few seconds.

---

## Starting Promtail

Run PowerShell as Administrator:

```powershell
cd C:\Promtail
.\promtail.exe --config.file=C:\Promtail\config\promtail-windows.yaml --log.level=info
```

Successful startup should show:

```
Starting Promtail
server listening on addresses
```

---

## Verifying Logs in Grafana

Once Promtail is running, logs should begin appearing in Loki.

In Grafana, go to **Explore** and run:

```logql
{job="windows-sysmon"}
```

or

```logql
{job="windows-security"}
```

If configured correctly, Windows event logs should appear.

---

## Troubleshooting

### Promtail connection timeout

If Promtail shows:

```
context deadline exceeded
```

Check:

- pfSense firewall rules
- NAT port forwarding
- Loki service status
- Correct Loki endpoint in config