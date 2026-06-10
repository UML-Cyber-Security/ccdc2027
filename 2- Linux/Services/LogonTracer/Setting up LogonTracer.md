# Setting up LogonTracer
Author: Ofir and Irakli\
Setting up LogonTracer


## LogonTracer installation:
### On a clean Linux machine, first install Docker:
```
sudo apt update
sudo apt install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin
sudo systemctl enable docker
sudo systemctl start docker
```

### Install Docker Compose:
```
sudo apt install -y docker-compose-plugin
```
### Install Git:
```
sudo apt update
sudo apt install -y git
```
### Clone the LogonTracer repository:
```
git clone https://github.com/JPCERTCC/LogonTracer.git
cd LogonTracer/docker-compose
```
### Edit the docker-compose.yml file, change localhost: 
```YAML
environment:
  - LTHOSTNAME=localhost
```
To your VM's IP


### Run:
```
sudo docker network create neo4j-network
sudo docker compose build
sudo docker compose up -d
```

You can now access the logonTracer (might need a port forward) at `http://<IP_ADRESSS>:8080`

you can upload logs to LogonTracer thoough the web UI, or you could move the logs file to the machine where LogonTrace is hosted and run the following python command to upload the logs.
```
python3 logontracer.py -e [EVTX File] -z [TIME Zone] -u [USERNAME] -p [PASSWORD] -s [IP Address]
```
