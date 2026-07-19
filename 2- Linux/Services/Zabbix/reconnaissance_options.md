# Checkpoint 0:

## Summary 
We were first tasked with finding tools that could give us detailed visibility on a Linux system. We have broken down visibility into 6 different categories and have found tools that fulfil the requirements of these categories:

Requirements:
1. Running Processes: We need visibility on what programs are currently running, who is running them, what the parent processes are, etc.
2. Services: We need to see what services are running, what's running when the machine starts and if they are actively on. 
3. Networking: We need to see what the machine is listening on, what connections are opened and what processes own which connections. ie, if something is running on port 65, which process is it and which user
4. Scheduled Jobs: We need to see what the machine is set to run automatically or in the future such as cron jobs, systemd timers, etc. 
5. Applications: We need to see what major applications are installed like web servers, databases, etc
6. Logs & Health Metrics: We need to see computer health metrics for the CPU, memory, and the disk. We also need logs for failing services


### Individual Candidate 1: Zabbix (https://www.zabbix.com/) (https://github.com/zabbix/zabbix)

Zabbix uses an agent installed on each individual host that reports back to a central Zabbix server (similar to Wazuh). You can then view everything through its web UI. It's used for monitoring a large number of servers. 

#### Pros: 
- Used in real enterprise environments so it's a trusted service
- Scales to a large amount of hosts
- Seems to have strong documentation (in all honesty I haven't looked at it that much but there seems to be a lot) 
#### Cons:
- You need a centralized server so if it goes down you lose all visibility
- Large set up process
- Seems to have a steep learning curve

Requirements met: 1 - 4, 6. 

### Individual Candidate 2: Cockpit (https://cockpit-project.org/) (https://github.com/cockpit-project/cockpit)

Cockpit is a web dashboard that is a server admin interface that allows you to monitor a Linux system via your browser. It shows you what's happening to your system real time. It can show running processes, all services (and their status), allows you to start/stop services, it shows barebones network information for interfaces and connections and shows logs and health metrics via journald. 

#### Pros:
- Simple to use
- Not much configuration, Built into RHEL systems
#### Cons:
- Doesn't show cron jobs or scheduled tasks
- Isn't good for deep reconnaissance, more for surface level things

Requirements met: 1 - 3, 6

### Individual Candidate 3: Wazuh (https://wazuh.com/) (https://github.com/wazuh/wazuh)

Wazuh is an open source SIEM solution like Graylog that you deploy on one machine, acting like the centralized server and install individual agents on the machines you want to monitor. The agents give data back to the manager in real time and you can view the data on a web UI. 

#### Pros:
- We already have a lot of documentation and scripts written for it
- Works across multiple Linux distros
- It can detect when files are tampered with
- (I think it can integrate with Grafana but I don't know how good it is)
- Even if the manager goes down, the agents still collect data locally for you to see once you bring it back up
#### Cons:
- Requires a central managing server so if it goes down you lose visibility
- Heavy initial set up

Requirements met: 1 - 4, 6

## Tools for looking at applications: 

None of these solid candidates meet requirement 5 in the best way so here are some smaller tools to fill in that gap:

Osquery: You can use SQL to query a system like it's a database. The program exposes your OS as a database and allows you to explore system data as SQL queries. It can be used to easily look at if web servers or databases are installed

Nothing?: Another option is to not install any external resource at all and just use Linux's built-in package manager to see what's installed and grep for major services like web servers or databases.

