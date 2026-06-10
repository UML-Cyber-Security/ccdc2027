# WHAT IS THIS: 
# Script that should be run to reinstall + configure ALL Wazuh agents. This script should work for 
# WINDOWS OS's and should automatically uninstall and reinstall a Wazuh agent
# THIS IS WIP

$ProgressPreference = 'SilentlyContinue'
Invoke-WebRequest -Uri https://packages.wazuh.com/4.x/windows/wazuh-agent-4.11.2-1.msi -OutFile $env:tmp\wazuh-agent; msiexec.exe /i $env:tmp\wazuh-agent /q WAZUH_MANAGER='192.168.1.26' WAZUH_AGENT_GROUP='windows' WAZUH_AGENT_NAME='windows-test1' 
NET START WazuhSvc
