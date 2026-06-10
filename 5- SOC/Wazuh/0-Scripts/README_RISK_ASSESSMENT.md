## LIN_default_agent_install.sh

**Functionality/Description:** Prompts for a Linux type (Debian or RPM), machine name, and Wazuh manager IP, then pulls the latest Wazuh repo, installs the agent, and starts the service. No additional configuration is applied beyond the defaults.

**Use Case During Event:** Use this on a fresh machine when you just need a Wazuh agent connected to the manager quickly and don't need any custom FIM or tuned configs.

**Risk Assessment:** Low - straightforward package install with no system configuration changes beyond adding a repo and starting a service.

---

## LIN_FULL_agent_install.sh

**Functionality/Description:** Uninstalls any existing Wazuh agent, then reinstalls and applies a full custom configuration including shortened scan intervals, realtime FIM monitoring on sensitive paths (`/etc/passwd`, `/etc/shadow`, `/etc/ssh/sshd_config`, cron, sudoers, SSH authorized keys, and more), port inventory scanning, and auditd log ingestion. Supports Debian, RPM, OpenSUSE, and FreeBSD (FreeBSD is WIP). **Script is marked as WIP overall.**

**Use Case During Event:** Run on machines where you want full Wazuh coverage beyond defaults - replaces whatever agent config was there before and layers in competition-relevant FIM targets.

**Risk Assessment:** Medium - forcefully purges the existing agent and rewrites `ossec.conf` via `sed` in place, so a bad run could corrupt the config. Several sections are incomplete or commented out (auditd, active response, port monitoring rules), so don't rely on those features being functional.

## WIN_agent_install.ps1

**Functionality/Description:** Downloads the Wazuh 4.11.2 MSI installer silently and installs it with a hardcoded manager IP (`192.168.1.26`), agent group (`windows`), and agent name (`windows-test1`), then starts the Wazuh service. **Script is marked as WIP and manager IP/agent name are hardcoded.**

**Use Case During Event:** Run on Windows machines to get a Wazuh agent installed and connected to the manager quickly.

**Risk Assessment:** Medium - manager IP and agent name are hardcoded and must be updated before each use, otherwise agents will register with the wrong name and potentially the wrong manager.