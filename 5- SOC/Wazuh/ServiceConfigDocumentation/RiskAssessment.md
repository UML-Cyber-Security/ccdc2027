## 0365-audit_rules.xml

**Functionality/Description:** A custom Wazuh rules file that extends the default auditd decoder with competition-relevant detections covering anomalous process/file activity, SELinux events, login anomalies, privilege escalation, and filesystem watch events (write, read, attribute change, execute) across sensitive paths like `/etc/passwd`, `/etc/shadow`, `sshd_config`, PAM, sudoers, cron, and more.

**Use Case During Event:** Load into the Wazuh manager to get granular auditd-sourced alerts on the dashboard - works alongside `ossec.conf.j2`'s auditd log ingestion to give you full visibility into kernel-level activity on monitored hosts.

**Risk Assessment:** Low - read-only rules file with no system changes, though the high volume of level-3 watch rules may generate significant alert noise depending on how active the monitored systems are.