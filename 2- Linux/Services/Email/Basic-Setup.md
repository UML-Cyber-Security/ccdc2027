# Postfix and Dovecot Install + Config + Thunderbird Setup

WHAT THIS IS:  
Configuring TLS setup for a Postfix + Dovecot email enviornment. Setup on a Linux Debian machine. 


## 1. Install Postfix and Dovecot
This part can be followed by the official docs. 


## 2. Secure the Services

The following will be applied:
 - Offline storage with encryption
 - Disable plain text authentication methods
 - Enable TLS encryption

### 2.1 Offline Storage with Encryption

This is **not** active by default. The easiest way to implement this is to force Thunderbird or Mutt to encrypt their emails. In Thunderbird settings, go to email settings, E-E Encryption, Generate a new PGP key, check "Require encryption by default". 


### 2.2 Disable Plain Text Auth

Edit ```/etc/dovecot/conf.d/10-auth.conf```
```
disable_plaintext_auth = yes
```

### 2.3 Setup/Enable TLS

Import or generate self-signed cert pair:

```
sudo install -d -m 0755 /etc/ssl/mail
sudo openssl req -x509 -newkey rsa:4096 -sha256 -days 825 -nodes \
  -keyout /etc/ssl/private/mailserver.key \
  -out /etc/ssl/certs/mailserver.crt \
  -subj "/CN=mail.example.com"
sudo chown root:root /etc/ssl/private/mailserver.key /etc/ssl/certs/mailserver.crt
sudo chmod 0400 /etc/ssl/private/mailserver.key
sudo chmod 0644 /etc/ssl/certs/mailserver.crt
```


Edit the ```/etc/postfix/master.cf```

Uncomment following lines:
```
submission inet n       -       n       -       -       smtpd
  -o syslog_name=postfix/submission
  -o smtpd_tls_security_level=encrypt
  -o smtpd_sasl_auth_enable=yes
  -o smtpd_tls_auth_only=yes
```

Then, in the ```/etc/postfix/main.cf```
```
# General TLS Settings
smtpd_tls_cert_file = /etc/ssl/certs/mailserver.crt
smtpd_tls_key_file = /etc/ssl/private/mailserver.key
smtpd_tls_security_level = may
smtpd_tls_auth_only = yes

smtp_tls_security_level = may

smtpd_sasl_type = dovecot
smtpd_sasl_path = private/auth
smtpd_sasl_auth_enable = yes
```

For Dovecot, edit ```/etc/dovecot/conf.d/10-ssl.conf```. Also, leaving these default *might* still work?
```
ssl = required
ssl_cert = </etc/ssl/certs/mailserver.crt
ssl_key = </etc/ssl/private/mailserver.key
```


In ```/etc/dovecot/conf.d/10-master.conf``` uncomment:
```
service auth {
  unix_listener /var/spool/postfix/private/auth {
    mode = 0660
    user = postfix
    group = postfix
  }
}
```


## 3. Configure Thunderbird

Without Thunderbird, easiest way to send and recieve emails would be through:
```sudo apt install mutt```

Mutt config at ```~/.muttrc```

```
set realname = "Your Name"
set from = "user@chefops.com"
set use_from = yes
set envelope_from = yes

# IMAP (Receiving)
set imap_user = "user@chefops.com"
set imap_pass = "yourpassword"
set folder = "imap://192.168.4.211:143/"
set spoolfile = "+INBOX"

# SMTP (Sending)
set smtp_url = "smtp://user@chefops.com@192.168.4.211:587/"
set smtp_pass = "yourpassword"
set ssl_starttls = yes
set ssl_force_tls = yes

# Ignore certificate errors (since you're using snakeoil)
set ssl_verify_dates = no
set ssl_verify_host = no
```

### For Thunderbird

```sudo apt install thunderbird```

Select Manual Configuration

Incoming Server:  
Protocol: IMAP  
Hostname: (Email server hostname)  
Port: 143  
Connection Security: STARTTLS  
Auth Method: Normal Password  
Username: (Email server user)  

Outgoing Server:  
Hostname: (Email server hostname)  
Port: 587  
Connection Security: STARTTLS  
Auth Method: Normal Password  
Username: (Email server user)  


