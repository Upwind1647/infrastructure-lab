# Cloud Infrastructure

This repository serves as a project to showcase modern infrastructure provisioning, security hardening, and cloud-native deployments. It is designed to be fully reproducible, secure by default, and treated as Infrastructure as Code (IaC).

## Project Phases

### Phase 1: On-Premise (Completed)
Automating the provisioning of an Admin Box using Proxmox LXC.
* **OS:** Debian 12
* **Automation:** Bash scripting for zero-touch provisioning.
* **Security:** Automating user creation and privilege escalation management.
  * SSH Hardening (disabled root login & password auth, enforced auth via SSH keys).
  * UFW configured as default drop with rate-limited SSH.
* **Workload:** Deploying a containerized Python FastAPI service managed via `systemd`.

### Phase 2: Cloud Architecture & Networking
Designing and provisioning an AWS Virtual Private Cloud (VPC) with strict network segmentation (Public/Private Subnets) using Terraform.

### Phase 3: Cloud-Native Workloads
Deploying a lightweight Kubernetes distribution (K3s) into the private subnets and exposing services via an Ingress controller.

---

## Current Tech Stack
* **Infrastructure:** Proxmox VE, AWS
* **IaC & Automation:** Terraform, Bash, GitOps
* **Containerization & Orchestration:** Docker, systemd, K3s
* **Backend:** Python, FastAPI, Uvicorn

---

## Quickstart

**1. Bootstrap the Server:**
```bash
apt update && apt install -y curl && curl -O https://raw.githubusercontent.com/Upwind1647/infrastructure-lab/main/scripts/setup_me.sh && bash setup_me.sh
``` 

**2. Restore the Application**
```bash
git clone git@github.com:Upwind1647/infrastructure-lab.git && cd infrastructure-lab
python3 -m venv .venv && source .venv/bin/activate && pip install -r requirements.txt
sudo cp deploy/status-api.service /etc/systemd/system/ && sudo systemctl daemon-reload && sudo systemctl enable --now status-api.service
```