#!/bin/sh

#********************************
# Written by a sad Matthew Harper...
# POSIX sh port: runs under sh, dash, ash (BusyBox), bash
#
# Linux (auditd):  Alpine, Rocky/RHEL, Fedora, Debian/Ubuntu, openSUSE, Arch
# FreeBSD:         uses the built-in BSM audit system instead (see setup_freebsd)
#********************************

set -e

PATH="$PATH:/usr/local/sbin:/usr/sbin:/sbin"
export PATH

RULES_DIR="/etc/audit/rules.d"
RULES="$RULES_DIR/ccdc.rules"

have() { command -v "$1" >/dev/null 2>&1; }

# Print a status line, then append the heredoc that follows to the rules file
section() {
  echo "[+] $1"
  cat >> "$RULES"
}

# Clean up the generated rules so they load on any distro:
#  - resolve symlinked parent dirs (Rocky: /bin -> /usr/bin, /var/run -> /run)
#  - drop watches whose parent dir doesn't exist (Alpine has no /etc/systemd,
#    /etc/security, etc.), which auditctl would otherwise reject
#  - convert old-style "-w" watches to "-a always,exit -F path=/dir=" syscall
#    rules, which are faster and avoid the "Old style watch rules" warnings
#  - remove duplicate lines created by the path resolution
finalize_rules() {
  tmp="$RULES.tmp.$$"
  : > "$tmp"
  skipped=0
  while IFS= read -r line; do
    case "$line" in
      "-w "*)
        p=${line#-w }
        p=${p%% *}
        rest=${line#"-w $p"}
        p=${p%/}
        d=$(dirname "$p")
        b=$(basename "$p")
        if [ ! -d "$d" ]; then
          skipped=$((skipped + 1))
          continue
        fi
        d=$(cd "$d" && pwd -P)
        full="${d%/}/$b"
        # -w defaults to all permissions when no -p is given
        perm=rwxa
        key=
        # shellcheck disable=SC2086
        set -- $rest
        while [ $# -gt 0 ]; do
          case "$1" in
            -p) perm=$2; shift 2 ;;
            -k) key=$2;  shift 2 ;;
            *)  shift ;;
          esac
        done
        # Existing directories are watched recursively with dir=; files and
        # paths that don't exist yet (e.g. a tool an attacker may install) use path=
        if [ -d "$full" ]; then field=dir; else field=path; fi
        line="-a always,exit -F $field=$full -F perm=$perm${key:+ -k $key}"
        ;;
    esac
    if [ -n "$line" ] && grep -qxF -- "$line" "$tmp"; then
      continue
    fi
    printf '%s\n' "$line" >> "$tmp"
  done < "$RULES"
  mv "$tmp" "$RULES"
  chown root:root "$RULES"
  chmod 640 "$RULES"
  if have restorecon; then restorecon "$RULES" 2>/dev/null || true; fi
  echo "[*] Skipped $skipped watch rule(s) for paths that don't exist on this system"
}

# ── FreeBSD ───────────────────────────────────
# FreeBSD has no Linux auditd. Its BSM audit is built into the base system and is
# configured with event classes in /etc/security/audit_control, not per-file or
# per-syscall rules. These classes cover the same ground as the Linux rules below:
#   lo  login/logout                   (logins, session)
#   aa  authentication/authorization   (su, sudo, ssh auth)
#   ad  administrative                 (time, hostname, mount, kldload, user admin)
#   fm  file attribute modify          (chmod/chown: perm_mod)
#   fd  file delete                    (unlink/rename: delete)
#   fc  file create
#   ex  program execution, with args   (sudo_log, susp_activity, susp_shell)
#   -fr,-fw  FAILED reads/writes only  (unauthorized access attempts)
setup_freebsd() {
  AC=/etc/security/audit_control

  echo "[*] FreeBSD detected, configuring BSM audit"

  if [ -f "$AC" ] && [ ! -f "$AC.bak.ccdc" ]; then
    cp -p "$AC" "$AC.bak.ccdc"
    echo "[*] Backed up original config to $AC.bak.ccdc"
  fi

  echo "[+] Writing $AC"
  cat > "$AC" << 'EOF'
#
# CCDC audit configuration
#
dir:/var/audit
dist:off
flags:lo,aa,ad,fm,fd,fc,ex,-fr,-fw
minfree:5
naflags:lo,aa
policy:cnt,argv
filesz:10M
expire-after:200M
EOF
  chown root:wheel "$AC"
  chmod 600 "$AC"

  echo "[+] Enabling auditd at boot"
  sysrc auditd_enable=YES

  echo "[!!] Starting auditd"
  if service auditd status >/dev/null 2>&1; then
    # Already running: reload config without dropping the trail
    audit -s
  else
    service auditd start
  fi

  echo ""
  echo "[*] Audit trail directory:"
  ls -l /var/audit
  echo ""
  echo "[*] Watch events live:  praudit -l /dev/auditpipe"
  echo "[*] Search the trail:   auditreduce -c ex /var/audit/current | praudit -l"
}

# ── Root check ────────────────────────────────
if [ "$(id -u)" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

if [ "$(uname -s)" = "FreeBSD" ]; then
  setup_freebsd
  exit 0
fi

# ── Install auditd ────────────────────────────
if have auditctl; then
  echo "[*] auditd already installed"
elif have apt-get; then
  DEBIAN_FRONTEND=noninteractive
  export DEBIAN_FRONTEND
  apt-get -q install -y auditd audispd-plugins || apt-get -q install -y auditd
elif have dnf;    then dnf install -y audit audit-libs
elif have yum;    then yum install -y audit audit-libs
elif have zypper; then zypper --non-interactive install audit
elif have pacman; then pacman -Sy --noconfirm audit
elif have apk;    then apk add --no-cache audit
else
  echo "[ERROR] No known package manager found. Install auditd manually."
  exit 1
fi

# ── Enable auditd (systemd, OpenRC, or SysV) ──
if have systemctl && [ -d /run/systemd/system ]; then
  systemctl enable --now auditd
elif have rc-update; then
  rc-update add auditd default
  rc-service auditd start || true
elif have chkconfig; then
  chkconfig auditd on
  service auditd start || true
elif have service; then
  service auditd start || true
fi

# Make sure the kernel actually supports audit (fails in containers/WSL)
if ! auditctl -s >/dev/null 2>&1; then
  echo "[!] WARNING: kernel audit is unavailable (container, WSL, or no CONFIG_AUDIT)."
  echo "    Rules will be written but cannot be loaded on this system."
fi

# ── Start a fresh rules file (safe to re-run) ─
mkdir -p "$RULES_DIR"

# Base config: -D clears loaded rules before reloading. Rocky ships this in
# rules.d/audit.rules, but Alpine does not, so without it every reload tries to
# re-add existing rules and fails with "Rule exists".
cat > "$RULES_DIR/00-ccdc-base.rules" << 'EOF'
## Clear existing rules before loading
-D
## Larger buffer so bursts of events aren't dropped
-b 8192
EOF
chown root:root "$RULES_DIR/00-ccdc-base.rules"
chmod 640 "$RULES_DIR/00-ccdc-base.rules"
cat > "$RULES" << 'EOF'
## CCDC audit rules
# Keep loading rules if one fails (e.g. a syscall that doesn't exist on this arch)
-i
EOF

# ── Rules ─────────────────────────────────────

# Log modifications to date and time (2611)
section "Create auditd rule to watch for modifications to date and time" << 'EOF'
-a always,exit -F arch=b64 -S adjtimex,settimeofday -k time-change
-a always,exit -F arch=b32 -S adjtimex,settimeofday,stime -k time-change
-a always,exit -F arch=b64 -S clock_settime -k time-change
-a always,exit -F arch=b32 -S clock_settime -k time-change
-w /etc/localtime -p wa -k time-change
EOF

# Log modifications to host/domain name (2613)
section "Create auditd rule to watch for modifications to host or domain names" << 'EOF'
-a always,exit -F arch=b64 -S sethostname,setdomainname -k system-locale
-a always,exit -F arch=b32 -S sethostname,setdomainname -k system-locale
-w /etc/issue -p wa -k system-locale
-w /etc/issue.net -p wa -k system-locale
-w /etc/hosts -p wa -k system-locale
-w /etc/network -p wa -k system-locale
EOF

# Log modifications to AppArmor's Mandatory Access Controls (2614)
# Checks the kernel directly instead of systemctl, so it works without systemd
if [ -r /sys/module/apparmor/parameters/enabled ] &&
   grep -q Y /sys/module/apparmor/parameters/enabled; then
  section "Create auditd rule to watch for apparmor modifications" << 'EOF'
-w /etc/apparmor/ -p wa -k MAC-policy
-w /etc/apparmor.d/ -p wa -k MAC-policy
EOF
fi

# Collect login/logout information (2615)
section "Create auditd rule to monitor login and logout information" << 'EOF'
-w /var/log/faillog -p wa -k logins
-w /var/log/lastlog -p wa -k logins
-w /var/log/tallylog -p wa -k logins
EOF

# Collect session initiation info (2616)
section "Create auditd rule to collect session initialization information" << 'EOF'
-w /var/run/utmp -p wa -k session
-w /var/log/wtmp -p wa -k logins
-w /var/log/btmp -p wa -k logins
EOF

# Collect file permission changes (2617)
section "Create auditd rule to watch for file permission changes" << 'EOF'
-a always,exit -F arch=b64 -S chmod,fchmod,fchmodat -F auid>=1000 -F auid!=4294967295 -k perm_mod
-a always,exit -F arch=b32 -S chmod,fchmod,fchmodat -F auid>=1000 -F auid!=4294967295 -k perm_mod
-a always,exit -F arch=b64 -S chown,fchown,fchownat,lchown -F auid>=1000 -F auid!=4294967295 -k perm_mod
-a always,exit -F arch=b32 -S chown,fchown,fchownat,lchown -F auid>=1000 -F auid!=4294967295 -k perm_mod
-a always,exit -F arch=b64 -S setxattr,lsetxattr,fsetxattr,removexattr,lremovexattr,fremovexattr -F auid>=1000 -F auid!=4294967295 -k perm_mod
-a always,exit -F arch=b32 -S setxattr,lsetxattr,fsetxattr,removexattr,lremovexattr,fremovexattr -F auid>=1000 -F auid!=4294967295 -k perm_mod
EOF

# Collect unsuccessful unauthorized file access attempts (2618)
section "Create auditd rule to watch for unauthorized access attempts" << 'EOF'
-a always,exit -F arch=b64 -S creat,open,openat,truncate,ftruncate -F exit=-EACCES -F auid>=1000 -F auid!=4294967295 -k access
-a always,exit -F arch=b32 -S creat,open,openat,truncate,ftruncate -F exit=-EACCES -F auid>=1000 -F auid!=4294967295 -k access
-a always,exit -F arch=b64 -S creat,open,openat,truncate,ftruncate -F exit=-EPERM -F auid>=1000 -F auid!=4294967295 -k access
-a always,exit -F arch=b32 -S creat,open,openat,truncate,ftruncate -F exit=-EPERM -F auid>=1000 -F auid!=4294967295 -k access
EOF

# Collect successful file system mounts (2619)
section "Create auditd rule to watch for file system mounts" << 'EOF'
-a always,exit -F arch=b64 -S mount -F auid>=1000 -F auid!=4294967295 -k mounts
-a always,exit -F arch=b32 -S mount -F auid>=1000 -F auid!=4294967295 -k mounts
EOF

# Collect file deletion events (2620)
section "Create auditd rule to watch for file deletion events" << 'EOF'
-a always,exit -F arch=b64 -S unlink,unlinkat,rename,renameat -F auid>=1000 -F auid!=4294967295 -k delete
-a always,exit -F arch=b32 -S unlink,unlinkat,rename,renameat -F auid>=1000 -F auid!=4294967295 -k delete
EOF

# Collect modifications to sudoers (2621)
section "Create auditd rule to watch for modifications to the sudoers file" << 'EOF'
-w /etc/sudoers -p wa -k scope
-w /etc/sudoers.d/ -p wa -k scope
EOF

# Sudo log: all euid=0 execs from real users (2622)
# https://sudoedit.com/log-sudo-with-auditd/
section "Create auditd rule to watch for all sudo operations" << 'EOF'
-a always,exit -F arch=b32 -S execve -F euid=0 -F auid>=1000 -F auid!=-1 -F key=sudo_log
-a always,exit -F arch=b64 -S execve -F euid=0 -F auid>=1000 -F auid!=-1 -F key=sudo_log
EOF

# Collect kernel module loading/unloading (2623)
section "Create auditd rule to watch for kernel module loading/unloading" << 'EOF'
-w /sbin/insmod -p x -k modules
-w /sbin/rmmod -p x -k modules
-w /sbin/modprobe -p x -k modules
-a always,exit -F arch=b64 -S init_module,delete_module -k modules
EOF

# Cron / at
section "Create auditd rule to watch for cron/at modification" << 'EOF'
-w /var/spool/atspool -k cron
-w /var/spool/at -p wa -k cron
-w /var/spool/cron/atjobs -p wa -k cron
-w /etc/at.allow -k cron
-w /etc/at.deny -k cron
-w /etc/cron.allow -p wa -k cron
-w /etc/cron.deny -p wa -k cron
-w /etc/cron.d/ -p wa -k cron
-w /etc/cron.daily/ -p wa -k cron
-w /etc/cron.hourly/ -p wa -k cron
-w /etc/cron.monthly/ -p wa -k cron
-w /etc/cron.weekly/ -p wa -k cron
-w /etc/crontab -p wa -k cron
-w /var/spool/cron/root -k cron
-w /var/spool/cron/crontabs/ -p wa -k cron
EOF

# User files
section "Create auditd rule to watch for user modifications or creations (group, passwd, shadow, etc.)" << 'EOF'
-w /etc/group -p wa -k user_groups
-w /etc/passwd -p wa -k user_passwd
-w /etc/shadow -k user_shadow
-w /etc/login.defs -p wa -k logins
EOF

# Programs that modify user information
section "Create auditd rule to watch for uses of programs that modify user information" << 'EOF'
-w /usr/bin/passwd -p x -k passwd_modification
-w /usr/sbin/groupadd -p x -k group_modification
-w /usr/sbin/groupmod -p x -k group_modification
-w /usr/sbin/addgroup -p x -k group_modification
-w /usr/sbin/useradd -p x -k user_modification
-w /usr/sbin/userdel -p x -k user_modification
-w /usr/sbin/usermod -p x -k user_modification
-w /usr/sbin/adduser -p x -k user_modification
EOF

# Login configuration and information
section "Create auditd rule to watch for additional login information" << 'EOF'
-w /etc/securetty -p wa -k logins
EOF

# Root SSH key tampering
section "Create auditd rule to watch for root ssh key tampering" << 'EOF'
-w /root/.ssh -p wa -k rootkey
EOF

# Init system (systemd and OpenRC)
section "Create auditd rule to watch for init system modification" << 'EOF'
-w /bin/systemctl -p x -k systemd
-w /etc/systemd/ -p wa -k systemd
-w /usr/lib/systemd -p wa -k systemd
-w /etc/init.d/ -p wa -k init
-w /etc/runlevels/ -p wa -k init
EOF

# SSH configuration
section "Create auditd rule to watch for SSH configuration changes" << 'EOF'
-w /etc/ssh/sshd_config -k sshd
-w /etc/ssh/sshd_config.d -k sshd
EOF

# PAM configuration
section "Create auditd rule to watch for PAM configuration changes" << 'EOF'
-w /etc/pam.d/ -p wa -k pam
-w /etc/security/limits.conf -p wa -k pam
-w /etc/security/limits.d -p wa -k pam
-w /etc/security/pam_env.conf -p wa -k pam
-w /etc/security/namespace.conf -p wa -k pam
-w /etc/security/namespace.d -p wa -k pam
-w /etc/security/namespace.init -p wa -k pam
EOF

# User / process ID change (switching accounts)
section "Create auditd rule to watch for UID changes (su/sudo)" << 'EOF'
-w /bin/su -p x -k priv_esc
-w /usr/bin/sudo -p x -k priv_esc
EOF

# Suspicious activity
section "Create auditd rule to watch for suspicious activity" << 'EOF'
-w /usr/bin/wget -p x -k susp_activity
-w /usr/bin/curl -p x -k susp_activity
-w /usr/bin/base64 -p x -k susp_activity
-w /bin/nc -p x -k susp_activity
-w /bin/netcat -p x -k susp_activity
-w /usr/bin/ncat -p x -k susp_activity
-w /usr/bin/ss -p x -k susp_activity
-w /usr/bin/netstat -p x -k susp_activity
-w /usr/bin/ssh -p x -k susp_activity
-w /usr/bin/scp -p x -k susp_activity
-w /usr/bin/sftp -p x -k susp_activity
-w /usr/bin/ftp -p x -k susp_activity
-w /usr/bin/socat -p x -k susp_activity
-w /usr/bin/wireshark -p x -k susp_activity
-w /usr/bin/tshark -p x -k susp_activity
-w /usr/bin/rawshark -p x -k susp_activity
-w /usr/bin/rdesktop -p x -k T1219_Remote_Access_Tools
-w /usr/local/bin/rdesktop -p x -k T1219_Remote_Access_Tools
-w /usr/bin/wlfreerdp -p x -k susp_activity
-w /usr/bin/xfreerdp -p x -k T1219_Remote_Access_Tools
-w /usr/local/bin/xfreerdp -p x -k T1219_Remote_Access_Tools
-w /usr/bin/nmap -p x -k susp_activity
EOF

# Suspicious activity with system binaries
section "Create auditd rule to watch for suspicious activity with system binaries" << 'EOF'
-w /sbin/iptables -p x -k sbin_susp
-w /sbin/ip6tables -p x -k sbin_susp
-w /sbin/ifconfig -p x -k sbin_susp
-w /usr/sbin/arptables -p x -k sbin_susp
-w /usr/sbin/ebtables -p x -k sbin_susp
-w /sbin/xtables-nft-multi -p x -k sbin_susp
-w /usr/sbin/nft -p x -k sbin_susp
-w /usr/sbin/tcpdump -p x -k sbin_susp
-w /usr/sbin/traceroute -p x -k sbin_susp
-w /usr/sbin/ufw -p x -k sbin_susp
EOF

# Suspicious shells
# On Alpine, ash is the normal system shell (BusyBox), so don't flag it there
section "Create auditd rule to watch for suspicious shells" << 'EOF'
-w /bin/csh -p x -k susp_shell
-w /bin/fish -p x -k susp_shell
-w /bin/tcsh -p x -k susp_shell
-w /bin/tclsh -p x -k susp_shell
-w /bin/xonsh -p x -k susp_shell
-w /usr/local/bin/xonsh -p x -k susp_shell
-w /bin/open -p x -k susp_shell
-w /bin/rbash -p x -k susp_shell
EOF
if [ ! -f /etc/alpine-release ]; then
  echo "-w /bin/ash -p x -k susp_shell" >> "$RULES"
fi

# Make audit rules immutable until reboot (2624) -- ensure that this works
#echo "[+] Create auditd rule to make rules immutable unless there is a system restart"
#echo "-e 2" > "$RULES_DIR/99-finalize.rules"

# ── Load the rules ────────────────────────────
finalize_rules

# Some distros/images ship "-a task,never", which silently disables ALL syscall
# auditing. Comment it out so our rules actually record events.
for f in "$RULES_DIR"/*.rules; do
  [ -f "$f" ] || continue
  if grep -Eq '^-a[[:space:]]+(task,never|never,task)' "$f"; then
    echo "[!] Disabling '-a task,never' in $f (it blocks syscall auditing)"
    sed -e 's/^-a[[:space:]]*task,never/# CCDC disabled: &/' \
        -e 's/^-a[[:space:]]*never,task/# CCDC disabled: &/' "$f" > "$f.tmp.$$"
    cat "$f.tmp.$$" > "$f"
    rm -f "$f.tmp.$$"
  fi
  if grep -Eq '^-e[[:space:]]+2' "$f"; then
    echo "[!] $f contains '-e 2' (immutable). If rules are already locked, reboot to apply."
  fi
done

echo "[!!] Loading audit rules"
# augenrules merges rules.d/*.rules into /etc/audit/audit.rules and loads it.
# No restart needed: Rocky/RHEL refuses "systemctl restart auditd", and Alpine's
# OpenRC script skips loading rules on restart. Both load /etc/audit/audit.rules
# at boot, which augenrules has just regenerated, so the rules persist.
if have augenrules; then
  augenrules --load || echo "[!] augenrules failed (rules may be locked with -e 2; reboot to apply)"
else
  auditctl -R "$RULES" || echo "[!] auditctl failed to load rules"
fi

echo "[*] Active rule count: $(auditctl -l 2>/dev/null | grep -c '^-' || true)"