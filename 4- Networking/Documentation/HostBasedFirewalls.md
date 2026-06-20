# Host-Based Firewalls

## Overview
### What Are Host-Based Firewall (and why they're useful)
Host-based firewalls are pieces of software that are run on a singular machine to filter incoming and outgoing traffic to just that machine. While the perimeter firewall implements rules that are common to all machines on the network, host-based firewalls allow for more unique and machine specific rule sets.

### Default Policies
By default, both incoming and outgoing traffic should be denied. Often, firewalls use the default policy of deny incoming and allow outgoing. An easy way for attackers to bypass this is to setup reverse shells on machines, taking advantage of the allow outgoing policy. Therefore, by default, host-based firewalls should deny incoming and outgoing traffic, only allowing the bare minimum of what is needed, such as traffic over ports 22 (SSH), 80 (HTTP), 443 (HTTPS), 53 (DNS), and 123 (NTP).

**Note:** Before implementing the default deny incoming/deny outgoing policy, ensure the SSH is allowed so that you don't lock yourself out of the system

## Linux

### Iptables

#### What is Iptables
When viewing `iptables` rules, there are three different sections: INPUT, FORWARD, OUTPUT. INPUT rules are for incoming traffic, OUTPUT rules are for outgoing traffic, and FORWARD rules are for traffic between interfaces on the system.

`iptables` rules are read from top down, meaning whatever rules are at the top override the rules below it

#### How to Use Iptables
To view the `iptables` rules list run:
```bash
sudo iptables -L --line-numbers
```

When adding rules, there are two flags you can use. The `-I` flag is the insert flag and should be used for most rules. The `-A` flag is the append rule, and it places rules at the bottom of the list. The append flag should only be used for the DENY ALL rule. All other rules should use the insert flag.

To add the deny incoming and outgoing traffic rule:
```bash
sudo iptables -A INPUT -j DROP
sudo iptables -A OUTPUT -j DROP
```

To add an INPUT rule:
```bash
iptables -I INPUT <other options>
```

To add and OUTPUT rule:
```bash
iptables -I OUTPUT <other options>
```

To delete a rule, list the rules with line numbers and identify the line number of the rule you want to delete. Then run
```bash
sudo iptables -D <list> <line_number>
```

To ensure the configured iptables survive reboots, save the rules using:
```bash
sudo iptables-save > /etc/sysconfig/iptables
```

#### Useful Iptables Commands
- Deny incoming: `iptables -A INPUT -j DROP`
- Deny outgoing: `iptables -A OUTPUT -j DROP`

- Allow SSH: `iptables -I INPUT -p tcp --dport 22 -j ACCEPT`
- Allow HTTP: `iptables -I INPUT -p tcp --dport 80 -j ACCEPT`
- Allow out HTTP: `iptables -I OUTPUT -p tcp --dport 80 -j ACCEPT`
- Allow HTTPS: `iptables -I INPUT -p tcp --dport 443 -j ACCEPT`
- Allow out HTTPS: `iptables -I OUTPUT -p tcp --dport 443 -j ACCEPT`
- Allow out DNS: `iptables -I OUTPUT -p udp --dport 53 -j ACCEPT`

### UFW

#### What is UFW
UFW (uncomplicated firewall) is a wrapper for iptables, making it easier to define rules, block ports of IP address, and generally control network traffic. UFW rules apply for both IPv4 and IPv6. UFW is best used for Ubuntu based systems. By default UFW denies all incoming traffic and allows all outgoing.

#### How to use UFW
To install UFW:
```bash
sudo apt install ufw
```

To check the status of UFW:
```bash
sudo ufw status verbose
```

To enable UFW:
```bash
sudo ufw enable
```

**Note:** Before enabling UFW, ensure SSH is allowed

To change the default rules run:
```bash
sudo ufw default deny incoming
sudo ufw default deny outgoing
```

To add rules:
```bash
sudo ufw allow <rule>
sudo ufw deny <rule>
```

To remove rules:
```bash
sudo ufw delete <rule>
```

#### Useful Rules
```bash
ufw allow from <ip_address> proto tcp to any port 22
ufw deny from <ip_address> proto tcp to any port 22
ufw delete allow 22/tcp
ufw deny from <ip_address>
ufw deny out to <ip_address>
ufw deny in on eth0 from <ip_address>
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow out 80/tcp
ufw allow 443/tcp
ufw allow out 443/tcp
```

### Nftables

#### What is Nftables

#### How to use Nftables

### Firewalld

#### How to use Firewalld

#### How to use Firewalld

## Windows