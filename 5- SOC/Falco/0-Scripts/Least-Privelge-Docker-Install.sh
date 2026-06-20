#!/usr/bin/env bash
set -euo pipefail

# LEAST PRIVELEGE INSTALL SCRIPT, BROKEN!

# Installs a Falco service on the host machine, through a docker container
# Script can be paired with a "rules file", specified after running the script
# Rules not correctly firing/loading

FALCO_IMAGE="${FALCO_IMAGE:-falcosecurity/falco:latest}"
FALCO_CONTAINER_NAME="${FALCO_CONTAINER_NAME:-falco-least-privileged}"
FALCO_RESTART_POLICY="${FALCO_RESTART_POLICY:-unless-stopped}"
FALCO_VOLUME_MOUNTS=(
  "/var/run/docker.sock:/host/var/run/docker.sock"
  "/dev:/host/dev"
  "/proc:/host/proc:ro"
  "/boot:/host/boot:ro"
  "/lib/modules:/host/lib/modules:ro"
  "/usr:/host/usr:ro"
  "/etc:/host/etc:ro"
)

run() {
  if [[ "${EUID}" -ne 0 ]]; then
    sudo "$@"
  else
    "$@"
  fi
}

detect_os_family() {
  if [[ ! -r /etc/os-release ]]; then
    echo "Unsupported distribution. Supported: Debian/Ubuntu, RHEL/Fedora, openSUSE." >&2
    exit 1
  fi

  # shellcheck disable=SC1091
  . /etc/os-release
  local id_like="${ID_LIKE:-}"
  local id="${ID:-}"

  case " ${id} ${id_like} " in
    *" debian "*|*" ubuntu "*)
      echo "Debian"
      ;;
    *" rhel "*|*" fedora "*|*" centos "*|*" rocky "*|*" almalinux "*)
      echo "RedHat"
      ;;
    *" suse "*|*" sles "*|*" opensuse "*)
      echo "Suse"
      ;;
    *)
      echo "Unsupported distribution. Supported: Debian/Ubuntu, RHEL/Fedora, openSUSE." >&2
      exit 1
      ;;
  esac
}

install_docker() {
  local os_family
  os_family="$(detect_os_family)"

  case "${os_family}" in
    Debian)
      run apt-get update
      run apt-get install -y docker.io python3-docker
      ;;
    RedHat)
      if command -v dnf >/dev/null 2>&1; then
        run dnf install -y docker python3-docker
      else
        run yum install -y docker python3-docker
      fi
      ;;
    Suse)
      run zypper install -y docker python3-docker
      ;;
  esac
}

start_docker() {
  if command -v systemctl >/dev/null 2>&1; then
    run systemctl enable --now docker
  else
    run service docker start
  fi
}

deploy_falco() {
  local volume_args=()
  local vol
  for vol in "${FALCO_VOLUME_MOUNTS[@]}"; do
    volume_args+=("-v" "${vol}")
  done

  run docker pull "${FALCO_IMAGE}"
  run docker rm -f "${FALCO_CONTAINER_NAME}" >/dev/null 2>&1 || true

  run docker run -d \
    --name "${FALCO_CONTAINER_NAME}" \
    --cap-drop=all \
    --cap-add=SYS_ADMIN \
    --cap-add=SYS_RESOURCE \
    --cap-add=SYS_PTRACE \
    --cap-add=NET_ADMIN \
    --cap-add=NET_RAW \
    --cap-add=DAC_READ_SEARCH \
    "${volume_args[@]}" \
    --restart "${FALCO_RESTART_POLICY}" \
    "${FALCO_IMAGE}"
}

install_docker
start_docker
deploy_falco
