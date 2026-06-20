# Sysmon for Linux Installation Guide — Rocky Linux

## 1. Install Prerequisites

```bash
dnf install -y wget
```

## 2. Add Microsoft Repository

```bash
rpm --import https://packages.microsoft.com/keys/microsoft.asc
```

## 3. Add Microsoft Repo File

```bash
cat > /etc/yum.repos.d/microsoft.repo << 'EOF'
[microsoft-prod]
name=Microsoft Product Repository
baseurl=https://packages.microsoft.com/rhel/9/prod/
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF
```

> **Note:** If running Rocky 8, replace `rhel/9` with `rhel/8` in the baseurl.

## 4. Install Sysmon

```bash
dnf install -y sysmonforlinux
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