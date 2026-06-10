## Fully-Privilege-Docker-Install.sh

**Functionality/Description:** Detects the host OS family, installs Docker if needed, and deploys Falco as a fully privileged container with all necessary host path mounts. Optionally accepts a `falco_rules.local.yaml` path to mount custom rules into the container.

**Use Case During Event:** Run at the start of a round on any Linux machine to get Falco up and running quickly - pair with `falco_rules.local.yaml` for custom detection coverage.

**Risk Assessment:** Medium - `--privileged` mode gives the container broad host kernel access, and the `docker rm -f` step will forcefully remove any existing container with the same name.

---

## Least-Privilege-Docker-Install.sh

**Functionality/Description:** Same core logic as `fully-privilege-docker-install.sh` but attempts to deploy Falco using a minimal capability set (`SYS_ADMIN`, `SYS_PTRACE`, `NET_ADMIN`, etc.) instead of `--privileged`. **Currently broken - rules are not correctly firing or loading.**

**Use Case During Event:** Do not use during the event - fall back to `fully-privilege-docker-install.sh` until this script is fixed and validated.

**Risk Assessment:** High- script is non-functional in its current state.

---

## falco_rules.local.yaml

**Functionality/Description:** Custom Falco rules file covering authentication file tampering, cron/PAM/SSH config modifications, `/bin` integrity, reverse shell detection, and suspicious inbound/outbound connections.

**Use Case During Event:** Supply this file when prompted by `fully-privilege-docker-install.sh` to layer competition-relevant detections on top of Falco's defaults.

**Risk Assessment:** Low - read-only rules file with no system changes, though INFO-level rules like `/bin binary executed` and `Login success recorded` will generate significant alert volume and may need tuning.