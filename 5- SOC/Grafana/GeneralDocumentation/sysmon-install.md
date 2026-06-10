# Sysmon for Linux Installation Guide

## 1. Install Prerequisites

```bash
apt update && apt install -y wget gnupg2 apt-transport-https
```

## 2. Add Microsoft GPG Key

```bash
wget -qO /etc/apt/trusted.gpg.d/microsoft.asc https://packages.microsoft.com/keys/microsoft.asc
```

## 3. Add Microsoft Repository

```bash
echo "deb [arch=amd64] https://packages.microsoft.com/repos/microsoft-ubuntu-noble-prod noble main" \
> /etc/apt/sources.list.d/microsoft.list
```

## 4. Update and Install Sysmon

```bash
apt update && apt install -y sysmonforlinux
```

## 5. Create Configuration

```bash
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
```

## 6. Initialize Sysmon

```bash
sysmon -accepteula -i /etc/sysmon/config.xml
```

## 7. Enable and Start the Service

```bash
systemctl enable sysmon
systemctl start sysmon
systemctl status sysmon
```

## 8. promtail config
```bash
- job_name: sysmon
    journal:
      matches: SYSLOG_IDENTIFIER=sysmon
    relabel_configs:
      - source_labels: [__journal__hostname]
        target_label: host
      - target_label: job
        replacement: sysmon
```
