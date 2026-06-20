This md file contains a description of tools within the current directory

### loki.sh
Functionality/Description: Installs Grafana Loki v2.9.3 by downloading the binary, creating necessary directories, configuring a local logging instance, and setting it up as a systemd service listening on port 3100.

Use Case During Event: When the team needs to centralize and store logs from multiple sources for easier monitoring, searching, and analysis during incident response.

Risk Assessment: Medium – the script installs software from an external source and creates a persistent service. Additionally, improper network configuration or firewall rules could unintentionally expose the service, and log storage may grow quickly, potentially consuming disk space.

### prometheusGrafana.sh
Functionality/Description: Installs and configures Prometheus, Node Exporter, and Grafana by downloading binaries, setting up configuration files, creating systemd services, and enabling all services for system monitoring and visualization.

Use Case During Event: When the team needs real-time system monitoring, performance metrics, and dashboards to track system health, resource usage, and detect anomalies during an incident.

Risk Assessment: Medium – the script installs multiple services from external sources and exposes several web interfaces (ports 9090, 9100, and 3000). Default configurations (such as Grafana’s default credentials admin/admin) pose a security risk if not changed. Additionally, improper network configuration could expose these services externally. The script also creates persistent systemd services and runs binaries from the user’s home directory, which may introduce stability or security concerns if files are modified or tampered with.

### promtail.sh
Functionality/Description: Installs Promtail v2.9.3 by downloading the binary, configuring log collection from system log files and the systemd journal, and setting it up as a systemd service to forward logs to Grafana Loki.

Use Case During Event: When the team needs to collect and forward logs from local systems (e.g., syslog, auth logs, audit logs, and Sysmon logs) to a centralized logging server for monitoring and analysis.

Risk Assessment: Medium – the script installs and enables a persistent service that continuously reads sensitive log files (e.g., /var/log/auth.log, /var/log/audit/audit.log). If misconfigured, it could expose sensitive information or overwhelm the logging system. Additionally, logs are sent over HTTP without encryption (http://localhost:3100), which could be a risk if traffic is redirected or the service is exposed. Improper permissions or configuration could also lead to unauthorized access to logs.

### setup-linux-client.sh
Functionality/Description: Configures a Linux client to forward logs and metrics to a centralized SOC server by installing and configuring Node Exporter, Promtail, and Falco. The script sets up systemd services, configures log collection (including system, auth, audit, and Falco logs), and forwards data to a remote logging system.

Use Case During Event: When the team needs to quickly onboard multiple Linux machines into a centralized monitoring and logging infrastructure for visibility, detection, and incident response across the environment.

Risk Assessment: High – the script performs extensive system modifications, including installing multiple services, adding external repositories, importing GPG keys, and enabling persistent background services. It also transmits logs and system data over the network to a remote server, which could expose sensitive information if the destination is compromised or communication is not secured (uses HTTP, not HTTPS). Additionally, misconfiguration or incorrect input (e.g., wrong SOC server IP) could disrupt logging or leak data. The script requires root privileges and modifies critical system components, increasing the potential impact of misuse or errors.

### tls-setup.sh
Functionality/Description: Configures TLS encryption for Grafana by generating a self-signed local Certificate Authority (CA), creating SSL certificates for the Grafana server, and modifying Grafana configuration files to enable HTTPS access on the specified SOC server IP.

Use Case During Event: When the team needs to secure the Grafana web interface with HTTPS to protect dashboard access and prevent credential or data exposure during monitoring and incident response operations.

Risk Assessment: Medium – the script modifies critical Grafana configuration files and replaces the default HTTP setup with HTTPS using a self-signed certificate, which may cause service disruption if misconfigured. The use of self-signed certificates can trigger browser trust warnings and may not be suitable for production environments without proper certificate management. Additionally, incorrect IP input or configuration errors could result in Grafana becoming inaccessible until manually corrected.

### falco.json
Functionality/Description: A Grafana dashboard ingesting Falco events from Loki, visualising event volume, top processes and parent processes, binaries running from non-standard paths, shells spawning network tools, top source/destination IPs, live log feeds, and a 5-deep process ancestry chain. Hostname filtering is driven by a dynamic multi-select variable scoped to the falco Loki job.

Use Case During Event: Primary real-time visibility layer for monitored hosts. Use the non-standard path and shell-spawning-network-tools panels for quick triage, and the ancestry chain panel to trace attacker process lineage during active incidents.

Risk Assessment: Low — read-only visualisation with no write access to any system. Ensure all target hosts are reporting into Loki before the event begins and confirm the hostname variable is set to cover all machines, so there are no gaps in visibility coverage.

### auditd.json

Functionality/Description: A Grafana dashboard ingesting Linux auditd logs from Loki, displaying gauge overviews for sudo usage, root logins, failed logins, and total logins. Deeper panels cover successful login tables, login attempts per host, root login frequency, failed login attempts broken down by account/IP/host, top executed binaries, sudo command history, and cronjob execution activity.

Use Case During Event: Primary authentication and privilege monitoring layer. Use the failed logins and root login panels to spot brute-force attempts or unauthorised root access early, and the sudo usage table to track privilege escalation across all monitored hosts in real time.

Risk Assessment: Low — read-only visualisation with no write access to any system. Ensure the dashboard is deployed and validated before the event begins, and confirm all hosts are reporting into Loki correctly so there are no blind spots in coverage.

### pfsense.json

Functionality/Description: A Grafana dashboard ingesting pfSense logs from Loki across two jobs (pfsense and pfsense_firewall), displaying stat overviews for SSH logins, failed logins, config changes, firewall connections, blocked connections, and sudo commands. Detailed panels cover SSH authentication events, sudo command execution, GUI/config change activity, all firewall connections, and a blocked-connections-only live feed. Auto-refreshes every 30 seconds.

Use Case During Event: Primary visibility layer for the network perimeter. Use the SSH authentication and sudo panels to monitor for unauthorised access attempts on the firewall itself, the config change panel to detect any tampering with firewall rules, and the blocked connections feed to confirm that defensive rules are firing correctly.

Risk Assessment: Low — read-only visualisation with no write access to any system. Ensure both Loki jobs (pfsense and pfsense_firewall) are confirmed as ingesting logs before the event begins, and validate the dashboard is showing live data so there are no silent gaps in firewall visibility.

### sysmon.json

Functionality/Description: A Grafana dashboard ingesting Sysmon and syslog data from Loki, displaying a timing correlation time-series overlaying service completions, root commands, and network connections. Panels cover destination IP distribution, service counts by name, top binaries accessed, a cgroup services table, cron job execution history, system processes with parent/child relationships, and a full network connections table with source/destination IPs, ports, and associated process.

Use Case During Event: Use alongside the Falco and Auditd dashboards for deeper process and network visibility. The timing correlation panel is particularly useful for spotting bursts of activity across services, commands, and network connections simultaneously. The system processes and network connections tables give a granular view of what is running and communicating at any given moment.

Risk Assessment: Low — read-only visualisation with no write access to any system. Confirm all panels are populated with live data before the event begins to avoid false confidence in coverage.

### zeek.json

Functionality/Description: A Grafana dashboard ingesting Zeek network logs from Loki, covering total connections, connection rate by protocol, top destination and source IPs, inter-subnet flow pairs, DNS queries by source IP, DNS query type breakdown, NXDOMAIN failures by source, Zeek anomaly events, connections on non-standard ports, high connection-rate hosts, HTTP response codes over time, and TLS version breakdown.

Use Case During Event: Primary network traffic visibility layer. Use the anomaly detection panels to spot scanning activity and unusual port usage, the DNS panels to catch beaconing or tunnelling behaviour, and the TLS breakdown to identify outdated or unexpected protocol versions in use across the network.

Risk Assessment: Low — read-only visualisation with no write access to any system. Confirm the zeek Loki job is ingesting data for all relevant log types (conn, dns, http, ssl, weird) before the event begins, and validate the time window is appropriate so that anomaly panels have enough data to establish a meaningful baseline.