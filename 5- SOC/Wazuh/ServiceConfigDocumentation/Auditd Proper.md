## Proper Auditd W/ Wazuh Integration ##
How to setup pretty Wazuh auditd rules.  
THIS IS A DIRTY AND TEMPORARY WAY - upon an upgrade of the Wazuh server, this process will need to be redone.  

```
https://github.com/socfortress/Wazuh-Rules/blob/main/Auditd/README.md
```

### 1. Install auditd using script on Endpoint ###

Make sure everything here is working.  



### 2. On the Wazuh-Manager ###

1. Edit the ```/var/ossec/etc/lists/audit-keys```

```
time-change:time_change
system-locale:hostname_change
logins:login
session:sessions
perm_mod:file_permissions
access:acess_attempt

mounts:mount

delete:deletes
scope:sudoers
sudo_log:sudo_events

modules:kernel
cron:cron_modification

user_groups:groups
user_passwd:passwd
user_shadow:shadow

passwd_modification:passwd_mods
group_modification:group_mods
user_modification:user_mods

rootkey:root_key
systemd:systemd_events

sshd:sshd_config

pam:pam_mods
priv_esc:priv_escalation

susp_activity:suspicous_runs
T1219_Remote_Access_Tools:remote_access
sbin_susp:suspicous_bins
susp_shell:suspicous_shells
```

2. Edit ```/var/ossec/ruleset/rules/0365-auditd_rules.xml```
Add in the new ```0365-auditd_rules.xml``` (In this folder) Replacing the old version.  

3. ```systemctl restart wazuh-manager```

### 3. Testing Configuration ###

Should be working on the dashboard now.  

### Troubleshooting ###

The Wazuh AGENT should have the following block in the ```/var/ossec/etc/ossec.conf```.  

```
<localfile>
    <location>/var/log/audit/audit.log</location>
    <log_format>audit</log_format>
</localfile>
```





