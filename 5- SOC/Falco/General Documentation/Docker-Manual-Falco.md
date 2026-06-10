# Falco Docker Deployment (Manual Steps)

## Prerequisites
- Root or sudo access on the host.
- Kernel headers for the running kernel (required for Falco's kernel driver):
  - Ubuntu/Debian: `sudo apt install -y linux-headers-$(uname -r)`
  - RHEL/Fedora: `sudo dnf install -y kernel-devel kernel-headers`
  - openSUSE: `sudo zypper install -y kernel-default-devel`

## Install Docker Engine
### Ubuntu
```
sudo apt update
sudo apt install -y docker.io
sudo systemctl enable --now docker
```

### Debian
```
sudo apt update
sudo apt install -y docker.io
sudo systemctl enable --now docker
```

### RHEL
```
sudo yum install -y docker
sudo systemctl enable --now docker
```

### Fedora
```
sudo dnf install -y docker
sudo systemctl enable --now docker
```

### openSUSE
```
sudo zypper install -y docker
sudo systemctl enable --now docker
```

## Pull the Falco Image
```
sudo docker pull falcosecurity/falco:latest
```

## Least Privileged Deployment
```
sudo docker run -d --name falco-least-privileged \
  --cap-drop=all \
  --cap-add=SYS_ADMIN \
  --cap-add=SYS_RESOURCE \
  --cap-add=SYS_PTRACE \
  --cap-add=NET_ADMIN \
  --cap-add=NET_RAW \
  --cap-add=DAC_READ_SEARCH \
  -v /var/run/docker.sock:/host/var/run/docker.sock \
  -v /dev:/host/dev \
  -v /proc:/host/proc:ro \
  -v /boot:/host/boot:ro \
  -v /lib/modules:/host/lib/modules:ro \
  -v /usr:/host/usr:ro \
  -v /etc:/host/etc:ro \
  --restart unless-stopped \
  falcosecurity/falco:latest
```

## Fully Privileged Deployment
```
sudo docker run -d --name falco-fully-privileged \
  --privileged \
  -v /var/run/docker.sock:/host/var/run/docker.sock \
  -v /dev:/host/dev \
  -v /proc:/host/proc:ro \
  -v /boot:/host/boot:ro \
  -v /lib/modules:/host/lib/modules:ro \
  -v /usr:/host/usr:ro \
  -v /etc:/host/etc:ro \
  --restart unless-stopped \
  falcosecurity/falco:latest
```

## Validate
```
sudo docker ps
sudo docker logs -f falco-least-privileged
```
