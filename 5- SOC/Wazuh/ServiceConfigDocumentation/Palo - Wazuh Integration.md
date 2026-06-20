## Palo Alto Wazuh Integration ##
What this is:  

WIP on how to do Wazuh- Palo bozer  
Setps up syslog forwarding from Palo Alto to Wazuh through port 514.  


### Installation ###  
Make sure Wazuh and Palo Alto is already installed.  


### On the Wazuh Server ###

1. Add the following config line in ```var/ossec/etc/ossec.conf```, between the <ossec_config> tags.  
Protocol - upd/tcp  
Allowed-ips - Ip of the Palo Alto (Needs to be the IP from Wazuh's subnet)  
Local-ip - Ip of the Wazuh manager  
```
<remote>
  <connection>syslog</connection>
  <port>514</port>
  <protocol>tcp</protocol>
  <allowed-ips>192.168.2.15/24</allowed-ips>
  <local_ip>192.168.2.10</local_ip>
</remote>
```

2. Change the following <logall>no to <logall> yes:  
```
<ossec_config>
  <global>
    <jsonout_output>yes</jsonout_output>
    <alerts_log>yes</alerts_log>
    <logall>yes</logall>
```

2. ```systemctl restart wazuh-manager```

### Palo Alto Configuration ###

1. Device -> Syslog -> Add (Profile name and server name + details)
![alt text](<../Images/image15.png>)
2. Objects -> Log Forwarding -> Add (Profile name) -> Add -> Syslog specifically  
![alt text](<../Images/image16.png>)
3. Policies -> Security -> (For each security profile click and) -> Actions -> Add Wazuh to the Log Forwarding   
![alt text](<../Images/image17.png>)
4. Commit Changes (should only take 10 years)