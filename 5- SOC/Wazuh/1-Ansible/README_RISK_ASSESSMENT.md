## var-ossec-etc-ossec-agent.conf.j2

**Functionality/Description:** A Jinja2 template used by Ansible to generate the `ossec.conf` Wazuh agent configuration file. Dynamically renders manager addresses, enrollment settings, FIM directories, rootcheck, SCA, syscollector, auditd log ingestion, and active response rules based on Ansible variables and the target OS family (Linux, Windows, macOS).

**Use Case During Event:** Used by the Ansible playbook to deploy a consistent, fully configured Wazuh agent config across all machines automatically - eliminates the need to manually edit `ossec.conf` on each host.

**Risk Assessment:** Low - no code is executed by the template itself, but misconfigured Ansible variables passed into it could result in agents connecting to the wrong manager or missing critical FIM paths.