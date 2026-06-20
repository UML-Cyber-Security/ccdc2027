# Automating LogonTracer with Ansible  
Author: Irakli and Ofir\
Automating LogonTracer with Ansible 

For LogonTracer to be useful, it needs to regularly ingest the security logs of every Windows machine. Since manually uploading and updating logs regularly is unrealistic, this automation handles the entire process end-to-end every 30 minutes using a cron job.

The goal of this playbook is to automatically collect logs from every Windows machine joined to the same domain where the Active Directory (AD) collects each system's logs through a log subscription. This also collects the logs of the AD itself. When the logs are collected it first copies them onto the machine running the Ansible playbook, then onto the Linux machine running LogonTracer. There, the files are moved into the LogonTracer Docker container and uploaded using the built-in LogonTracer script. This is the basic overview.

# Automation Structure

The automation is broken in to two playbooks as to be able to run the main actions (1.get the needed logs to a folder 2.get them to logontracer) separately. They are both triggered by a cron job playbook as follows:
 

## 1. Cron Scheduling (Local Machine)

A cron job is installed on the Ansible controller that runs the following script **every 30 minutes**:

`/home/user/ansible/run.sh`

> [!NOTE]
> This triggers the playbooks to extract the files from the Windows systems, and then uses another playbook to upload and ingest them into LogonTracer.


## 2. Export Logs on AD - extract.yml

This play is executed first. It exports the filtered Security Logs that LogonTracer needs.  
Files created:

- `AD_Local_<timestamp>.evtx`
- `Forwarded_<timestamp>.evtx`

Saved to:

`C:\Logs\Combined`

## 3. Find and Fetch EVTX Logs (Windows AD) - upload.yml

### **Locate Latest Logs**

The play searches in:

`C:\Logs\Combined`

for the newest:

- `AD_Local_*.evtx`
- `Forwarded_*.evtx`

These contain filtered Security logs from the Domain Controller and from all Windows machines via the log subscription.

### **Fetch Logs to Controller**

Both EVTX files are fetched to the Ansible controller at:

`/tmp/logontracer/`

The fetched paths are stored for use in the upload stage.


## 4. Upload to LogonTracer and Run Import

### **Host and Container Preparation**

The play ensures required directories exist both on the Linux host and inside the LogonTracer Docker container:

- `/opt/logontracer/incoming`
- `/usr/local/src/LogonTracer/incoming`

### **Copy EVTX Files**

The controller copies the AD_Local and Forwarded EVTX files to the host, then into the container using `docker cp`.

### **Trigger Ingestion**

The LogonTracer import is executed inside the container:

`logontracer.py -e ad_local.evtx forwarded.evtx -z -5 -u neo4j -p password -s localhost`

This updates the LogonTracer Neo4j database with new login activity to be viewable in webview.
