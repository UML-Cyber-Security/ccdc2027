# Cgroup Tracing

`bpftrace` is a high-level tracing language for Linux that uses eBPF to hook into kernel events at runtime, capturing process creation events — including cgroup context — synchronously before the process exits. This correlates short-lived processes to their parent systemd service.

---

## bpftrace Setup

### 1. Create the tracing script

```bash
sudo tee /usr/local/bin/cgroup-trace.bt << 'EOF'
tracepoint:syscalls:sys_enter_execve {
    printf("{\"ts\":%lld,\"pid\":%d,\"comm\":\"%s\",\"cgroup\":\"%s\"}\n",
        nsecs, pid, comm,
        str(curtask->cgroups->dfl_cgrp->kn->name)
    );
}
EOF
```

### 2. Create the necessary log files

```bash
sudo touch /var/log/cgroup.log && sudo chmod 666 /var/log/cgroup.log
```

### 3. Create the systemd service

This service will automatically send the logs to the `/var/log/cgroup.log` file.

```bash
sudo tee /etc/systemd/system/cgroup-trace.service << 'EOF'
[Unit]
Description=bpftrace cgroup-to-process logger
After=network.target

[Service]
Type=simple
ExecStart=/bin/bash -c 'bpftrace /usr/local/bin/cgroup-trace.bt | tee /var/log/cgroup.log'
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
```

### 4. Enable and start the service

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now cgroup-trace
```

## Promtail Setup

Add the following job to the `/etc/promtail/config.yml` file.

```bash
  - job_name: cgroup
    static_configs:
      - targets:
        - localhost
        labels:
          job: cgroup
          host: chefops-grafana
          __path__: /var/log/cgroup.log
```

Restart the promtail systemd service.

```bash
sudo systemctl restart promtail.service
```

## Grafana Setup

Once the job shows up on grafana, this is all that is required as a query in the dashboard.

```bash
{job="cgroup"} |= ``
```

The data processing and transformation steps are already setup on the `sysmon` grafana dashboard.