# Zabbix Install

## Installing Zabbix (For Debian)

Pre requisites:
- Debian 12 or 13 (no older)

---

## 1. Update system packages

```
sudo apt update && sudo apt upgrade -y
```

Add Zabbix 7.0 Repository. These packages aren't included in the default repo so you need to add the official Zabbix one.

Commands for Debian 13:
```
wget https://repo.zabbix.com/zabbix/7.0/debian/pool/main/z/zabbix-release/zabbix-release_latest_7.0+debian13_all.deb
sudo dpkg -i zabbix-release_latest_7.0+debian13_all.deb
sudo apt update
```

Commands for Debian 12:
```
wget https://repo.zabbix.com/zabbix/7.0/debian/pool/main/z/zabbix-release/zabbix-release_latest_7.0+debian12_all.deb
sudo dpkg -i zabbix-release_latest_7.0+debian12_all.deb
sudo apt update
```

Verify it was added correctly, you should see version 7.0.X from repo.zabbix.com:
```
apt-cache policy zabbix-server-pgsql
```

---

## 2. Install the Zabbix Server, Frontend & Agent 2

```
sudo apt install -y zabbix-server-pgsql zabbix-frontend-php zabbix-nginx-conf zabbix-sql-scripts zabbix-agent2
```

---

## 3. Install a database (MySQL or PostgreSQL)

### MySQL

Install MariaDB:
```
sudo apt install -y mariadb-server
sudo systemctl start mariadb
sudo systemctl enable mariadb
```

Create the database and user:
```
sudo mariadb
```

Then run:
```
CREATE DATABASE zabbix CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;
CREATE USER 'zabbix'@'localhost' IDENTIFIED BY '1qazxsW@1';
GRANT ALL PRIVILEGES ON zabbix.* TO 'zabbix'@'localhost';
FLUSH PRIVILEGES;
EXIT;
```

Import the schema (this takes several minutes on slower VMs, leave it running):
```
zcat /usr/share/zabbix-sql-scripts/mysql/server.sql.gz | mariadb --default-character-set=utf8mb4 -uzabbix --verbose zabbix
```

### PostgreSQL

Install PostgreSQL:
```
sudo apt install -y postgresql
```

Verify PostgreSQL is running (should show active):
```
sudo systemctl status postgresql
```

Create a Zabbix database user:
```
sudo -u postgres createuser --pwprompt zabbix
```

Create the database owned by the zabbix user:
```
sudo -u postgres createdb -O zabbix -E Unicode -T template0 zabbix
```

Import the schema:
```
zcat /usr/share/zabbix-sql-scripts/postgresql/server.sql.gz | sudo -u zabbix psql zabbix
```

---

## 4. Configure the Zabbix Server

```
sudo nano /etc/zabbix/zabbix_server.conf
```

Change the following, it will be commented out by default:
- Before:
```
# DBPassword=
```
- After:
```
DBPassword=1qazxsW@1
```

1qazxsW@1 is an example password, use a strong password (not the CCDC one plz).

---

## 5. Configure Nginx for the frontend

The package installs a configured Nginx server block so you need to adjust a few lines. Edit the file with the command:
```
sudo nano /etc/zabbix/nginx.conf
```

Change this:
```
server {
        # listen          8080;
        # server_name     example.com;
```

To this:
```
server {
        listen          8080;
        server_name     <SERVER IP OR SERVER DOMAIN>;
```

To avoid port conflicts, delete or disable the default Nginx virtual host:
```
sudo rm -f /etc/nginx/sites-enabled/default
```

---

## 6. Configure Timezones

Zabbix needs the PHP timezone to be set manually. Edit the file:
```
sudo nano /etc/zabbix/php-fpm.conf
```

Add this line anywhere:
```
php_value[date.timezone] = America/New_York
```

---

## 7. Enable and Start all Services

```
sudo systemctl restart zabbix-server zabbix-agent2 nginx php8.2-fpm
sudo systemctl enable zabbix-server zabbix-agent2 nginx php8.2-fpm
```

Verify all services are active and have no errors:
```
sudo systemctl status zabbix-server
sudo systemctl status zabbix-agent2
```

Both should show that they are active and running.

NOTE: Make sure your firewall allows all the required ports (80, 443 for TLS, 10051, 10050) to pass through.

---

## Checkpoint 1 Q & A

**1. Why would this tooling be useful during the competition?**

Zabbix gives us real time visibility into every host from a single dashboard. You can see if a service goes down, a new process appears, if something starts eating up resources, and much more. You can also set up automatic alerts for things you would commonly see. 

**2. If the red team compromises your account or the host, can they abuse this same tooling against you? How, and what would you do to reduce that risk?**

Yes if they get into the Zabbix web UI they can see everything you're monitoring and potentially use it against us. For example the red team can then use Zabbix's script execution to run commands on monitored hosts. To reduce this risk the important things we need to do are as we are installing Zabbix we use a STRONG STRONG password and restrict port 8080 access to only trusted machines.

**3. Can this tooling support monitoring an individual host on its own, and remain useful when a central SIEM solution is down, unavailable, or not yet built?**

Yes in a way, Zabbix needs its own server running to show the dashboard so if it goes down you lose visibility. However the agent keeps collecting data locally so once the connection comes back you will retain the data. One major worry I have is its necessity when we have a functional SEIM solution. I will dig a little into Wazuh (as the example SEIM) and see if it is worth bringing up Zabbix in the competition as a supplementary tool.

**4. Does the approach scale to many hosts? Can you run several independent sessions or consoles across distinct systems at once, and what begins to break down as the host count grows?**

It seems to scale well for our deployment sizes. One Zabbix server can monitor many hosts and you can view them all at once too. Over time alert noise may increase which may be a concern. However for our purposes, we shouldnt worry about things breaking as the host count goes up. Zabbix is designed to handle that load as long as we have the necessary resources. 