# Zeek Documentation & Usage

**Author:** Michael Leahy  
**Last Updated:** April 13, 2026

## Installing Zeek

1. Install zeek  
    For example, for Linux machines running Ubuntu 24.04:
    ```bash
    echo 'deb https://download.opensuse.org/repositories/security:/zeek/xUbuntu_24.04/ /' | sudo tee /etc/apt/sources.list.d/security:zeek.list
    curl -fsSL https://download.opensuse.org/repositories/security:zeek/xUbuntu_24.04/Release.key | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/security_zeek.gpg > /dev/null
    sudo apt update
    sudo apt install zeek-7.0
    ```

2. Run Zeek as a background service:
    Edit the config file 
    ```bash
    sudo nano /etc/systemd/system/zeek.service
    ```
    Add the following lines
    ```bash
    [Unit]
    Description=Zeek Network Security Monitor
    After=network.target

    [Service]
    ExecStart=/usr/local/zeek/bin/zeek -i eth0 Log::default_logdir=/opt/zeek/logs/current
    Restart=always
    User=root

    [Install]
    WantedBy=multi-user.target
    ```

    Enable the service
    ```bash
    sudo systemctl daemon-reload
    sudo systemctl enable zeek
    sudo systemctl start zeek
    sudo systemctl status zeek
    ```

## Configure Zeek with Promtail
1. If not already installed, install Promtail. Refer to Promtail documentation for these steps
2. Update the promtail config to parse and send Zeek logs. Here is an example promtail config.
    ```yaml
    server:
      http_listen_port: 9080
      grpc_listen_port: 0

      positions:
      filename: /var/lib/promtail/positions.yaml

      clients:
      - url: http://loki:3100/loki/api/v1/push

      scrape_configs:
      - job_name: varlogs
          static_configs:
          - targets:
              - localhost
              labels:
              job: varlogs
              host: grafana-server
              __path__: /var/log/*.log

      - job_name: syslog
          static_configs:
          - targets:
              - localhost
              labels:
              job: syslog
              host: grafana-server
              __path__: /var/log/syslog

      - job_name: auth
          static_configs:
          - targets:
              - localhost
              labels:
              job: auth
              host: grafana-server
              __path__: /var/log/auth.log

      - job_name: auditd
          static_configs:
          - targets:
              - localhost
              labels:
              job: auditd
              host: grafana-server
              __path__: /var/log/audit/audit.log
              
      - job_name: sysmon
          journal:
          matches: SYSLOG_IDENTIFIER=sysmon
          relabel_configs:
          - source_labels: [__journal__hostname]
              target_label: host
              replacement: grafana-server
          - target_label: job
              replacement: sysmon

          # ---------------------------------------------------------------------------
      # 1. conn.log  — network connections (THE most important log for your dashboard)
      #    Fields: ts uid src_ip src_port dst_ip dst_port proto service ...
      # ---------------------------------------------------------------------------
      - job_name: zeek_conn
          static_configs:
          - targets: [localhost]
              labels:
              job: zeek
              log_type: conn
              host: __HOSTNAME__          # optional — good for multi-sensor setups
              __path__: /var/log/zeek/conn.log

          pipeline_stages:
          # Skip the Zeek file header lines (start with '#')
          - drop:
              expression: '^#'

          # Parse the tab-separated fields we care about.
          # Zeek conn.log column order (0-indexed):
          #   0:ts  1:uid  2:id.orig_h  3:id.orig_p  4:id.resp_h  5:id.resp_p
          #   6:proto  7:service  8:duration  9:orig_bytes  10:resp_bytes  ...
          - regex:
              expression: '^(?P<ts>[^\t]+)\t(?P<uid>[^\t]+)\t(?P<src_ip>[^\t]+)\t(?P<src_port>[^\t]+)\t(?P<dst_ip>[^\t]+)\t(?P<dst_port>[^\t]+)\t(?P<proto>[^\t]+)\t(?P<service>[^\t]+)'

          # Promote low-cardinality fields to Loki labels (keep this list SHORT).
          # High-cardinality fields (src_ip, dst_ip) stay as log content and are
          # extracted at query time with `pattern` or `regexp`.
          - labels:
              proto:      # tcp / udp / icmp
              service:    # http / dns / ssl / (empty) — safe cardinality

          # Set the timestamp from the Zeek epoch field so log ordering is correct.
          # Without this, Promtail uses ingest time → out-of-order rejections in Loki.
          - timestamp:
              source: ts
              format: Unix   # Zeek ts is a Unix float e.g. 1775775591.130927

      # ---------------------------------------------------------------------------
      # 2. dns.log  — DNS queries and responses
      #    Useful for: DNS query volume per host, query types, NXDOMAIN detection
      # ---------------------------------------------------------------------------
      - job_name: zeek_dns
          static_configs:
          - targets: [localhost]
              labels:
              job: zeek
              log_type: dns
              __path__: /var/log/zeek/dns.log

          pipeline_stages:
          - drop:
              expression: '^#'
          # Relevant fields: ts uid src_ip src_port dst_ip dst_port proto trans_id
          #                  rtt query qclass qtype rcode ...
          - regex:
              expression: '^(?P<ts>[^\t]+)\t(?P<uid>[^\t]+)\t(?P<src_ip>[^\t]+)\t(?P<src_port>[^\t]+)\t(?P<dst_ip>[^\t]+)\t(?P<dst_port>[^\t]+)\t(?P<proto>[^\t]+)\t[^\t]+\t[^\t]+\t(?P<query>[^\t]+)\t[^\t]+\t(?P<qtype>[^\t]+)\t(?P<rcode>[^\t]+)'
          - labels:
              proto:
              qtype:      # A / AAAA / MX / TXT / PTR — safe cardinality
              rcode:      # NOERROR / NXDOMAIN / SERVFAIL
          - timestamp:
              source: ts
              format: Unix

      # ---------------------------------------------------------------------------
      # 3. http.log  — HTTP transactions
      #    Useful for: identifying web services, user-agents, response codes
      # ---------------------------------------------------------------------------
      - job_name: zeek_http
          static_configs:
          - targets: [localhost]
              labels:
              job: zeek
              log_type: http
              __path__: /var/log/zeek/http.log

          pipeline_stages:
          - drop:
              expression: '^#'
          # Relevant fields: ts uid src_ip src_port dst_ip dst_port method host uri
          #                  referrer version user_agent status_code ...
          - regex:
              expression: '^(?P<ts>[^\t]+)\t(?P<uid>[^\t]+)\t(?P<src_ip>[^\t]+)\t(?P<src_port>[^\t]+)\t(?P<dst_ip>[^\t]+)\t(?P<dst_port>[^\t]+)\t[^\t]+\t(?P<method>[^\t]+)\t[^\t]+\t[^\t]+\t[^\t]+\t[^\t]+\t[^\t]+\t[^\t]+\t[^\t]+\t(?P<status_code>[^\t]+)'
          - labels:
              method:       # GET / POST / PUT etc.
              status_code:  # 200 / 404 / 500 etc.
          - timestamp:
              source: ts
              format: Unix

      # ---------------------------------------------------------------------------
      # 4. ssl.log  — TLS/SSL sessions
      #    Useful for: certificate inspection, cipher suite auditing
      # ---------------------------------------------------------------------------
      - job_name: zeek_ssl
          static_configs:
          - targets: [localhost]
              labels:
              job: zeek
              log_type: ssl
              __path__: /var/log/zeek/ssl.log

          pipeline_stages:
          - drop:
              expression: '^#'
          - regex:
              expression: '^(?P<ts>[^\t]+)\t(?P<uid>[^\t]+)\t(?P<src_ip>[^\t]+)\t(?P<src_port>[^\t]+)\t(?P<dst_ip>[^\t]+)\t(?P<dst_port>[^\t]+)\t(?P<version>[^\t]+)'
          - labels:
              version:      # TLSv12 / TLSv13 — safe cardinality
          - timestamp:
              source: ts
              format: Unix

      # ---------------------------------------------------------------------------
      # 5. weird.log  — Zeek's anomaly/protocol violation log
      #    Useful for: detecting scan activity, malformed packets, protocol abuse
      # ---------------------------------------------------------------------------
      - job_name: zeek_weird
          static_configs:
          - targets: [localhost]
              labels:
              job: zeek
              log_type: weird
              __path__: /var/log/zeek/weird.log

          pipeline_stages:
          - drop:
              expression: '^#'
          - regex:
              expression: '^(?P<ts>[^\t]+)\t(?P<uid>[^\t]+)\t(?P<src_ip>[^\t]+)\t(?P<src_port>[^\t]+)\t(?P<dst_ip>[^\t]+)\t(?P<dst_port>[^\t]+)\t(?P<proto>[^\t]+)\t(?P<name>[^\t]+)'
          - labels:
              proto:
              name:       # weird type name — e.g. "above_hole_data_without_any_acks"
                          # cardinality is bounded in practice; monitor if it grows
          - timestamp:
              source: ts
              format: Unix

      # ---------------------------------------------------------------------------
      # 6. notice.log  — Zeek's built-in alert/notice framework
      #    Only populated if you have Zeek notice policies configured.
      # ---------------------------------------------------------------------------
      - job_name: zeek_notice
          static_configs:
          - targets: [localhost]
              labels:
              job: zeek
              log_type: notice
              __path__: /var/log/zeek/notice.log

          pipeline_stages:
          - drop:
              expression: '^#'
          - regex:
              expression: '^(?P<ts>[^\t]+)\t(?P<uid>[^\t]+)\t(?P<src_ip>[^\t]+)\t(?P<src_port>[^\t]+)\t(?P<dst_ip>[^\t]+)\t(?P<dst_port>[^\t]+)\t(?P<proto>[^\t]+)\t(?P<note>[^\t]+)'
          - labels:
              proto:
              note:       # notice type — e.g. Scan::Port_Scan, SSH::Password_Guessing
          - timestamp:
              source: ts
              format: Unix
    ```

3. Restart the promtail service
    ```bash
    sudo systemctl restart promtail.service
    ```

## Visualizing Logs on Grafana
1. Import the `zeek.json` file from the Dashboards folder into Grafana. Fix any data source errors.
