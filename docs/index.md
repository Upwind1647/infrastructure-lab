# Infrastructure Lab

---

## Project Phases

### Phase 1 — Local Infrastructure
Provision and harden a Debian LXC container on Proxmox. Deploy a Python application managed by Systemd.

- [Admin Box Setup](phase1/admin-box.md)
- [ADR-001: Hardening Script](phase1/adr-001-hardening-script.md)

### Phase 2 — Cloud Architecture
Design an AWS VPC with network segmentation.

- [Network Architecture](phase2/network.md)

---

## Tech Stack

`Proxmox` · `Debian LXC` · `Bash` · `Systemd` · `FastAPI` · `UFW` · `GitHub Actions` · `MkDocs Material`

---

## Quick Start

```bash
# 1. Copy your SSH public key into the container
lxc file push ~/.ssh/id_ed25519.pub admin-box/home/adminsetup/.ssh/authorized_keys

# 2. Run the hardening script
lxc exec admin-box -- bash /root/setup_me.sh

# 3. Verify
ssh adminsetup@<container-ip>
curl localhost:8000
