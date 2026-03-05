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
- [AWS Clickops Deployment](phase2/aws-clickops-deployment.md)

### Phase 3 — Containerization
Cloud-Native Builds & GHCR
- [Containerization](phase3/containerization.md)

---

## Tech Stack

`Proxmox` · `Debian LXC` · `Bash` · `Systemd` · `FastAPI` · `UFW` · `GitHub Actions` · `MkDocs Material` · `Docker`

---

## Quick Start

```bash
# 1. Run the hardening script (Creates user, sets up UFW, and fetches GitHub SSH keys)
lxc exec admin-box -- bash /root/setup_me.sh

# 2. SSH into the container using the newly provisioned user
ssh adminsetup@<container-ip>

# 3. Clone the repository and set up the application environment
git clone https://github.com/Upwind1647/infrastructure-lab.git
cd infrastructure-lab
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

# 4. Install and start the Systemd service
sudo cp deploy/status-api.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now status-api.service

# 5. Verify application is running locally and reachable via UFW
curl localhost:8000
```