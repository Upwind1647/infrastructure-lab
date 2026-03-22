# Infrastructure Lab

---

## Project Phases

### Phase 1: Local Infrastructure
Provision and harden a Debian LXC container on Proxmox. Deploy a Python application managed by systemd.

- [Admin Box Setup](phase1/admin-box.md)
- [ADR-001: Hardening Script](phase1/adr-001-hardening-script.md)

### Phase 2: Cloud Architecture
Design an AWS VPC with network segmentation.
- [Network Architecture](phase2/network.md)
- [AWS Clickops Deployment](phase2/aws-clickops-deployment.md)

### Phase 3: Containerization
Cloud-Native Builds & GHCR
- [Containerization](phase3/containerization.md)
- [ADR-004: Workload Architecture](phase3/adr-004-workload-architecture.md)

### Phase 4: Infrastructure as Code (IaC)
Transition from manual ClickOps to fully automated, declarative provisioning using OpenTofu. Introduction of a stateful persistence layer.
- [Infrastructure as Code](phase4/infrastructure-as-code.md)
- [ADR-005: Managed Database](phase4/adr-005-managed-database.md)

### Phase 5: Orchestration
Lightweight Kubernetes (K3s) on a Proxmox VM, IaC for Proxmox, and workload orchestration.
- [ADR-006: Lightweight Kubernetes (K3s) on Proxmox VM](phase5/adr-006-k3s.md)
- [K3s Architecture on Proxmox VM](phase5/k3s-architecture.md)
- [ADR-007: IaC for Proxmox](phase5/adr-007-proxmox-iac.md)
- [Kubernetes](phase5/kubernetes.md)

### Phase 6: Persistence & Data Ops
Stateful workloads, dynamic provisioning and disaster recovery.
- [ADR-008: Redis Persistence & DR](phase6/adr-008-persistence.md)
- [Redis & Disaster Recovery](phase6/redis-dr.md)

### Phase 7: Ingress
Expose the Status API via HTTPS using the built-in Traefik Ingress Controller and automate TLS with cert-manager.
- [ADR-009: Ingress and Automated TLS](phase7/adr-009-ingress-tls.md)
- [Kubernetes Port-Forwarding: Debugging](phase7/port-forwarding.md)

---

## Tech Stack

`Proxmox` · `Debian LXC` · `Bash` · `systemd` · `FastAPI` · `UFW` · `GitHub Actions` · `uv` · `Docker`

---

## Quick Start

```bash
# 1. Run the hardening script (Creates user, sets up UFW, and fetches GitHub SSH keys)
lxc exec admin-box -- bash /root/setup_me.sh

# 2. SSH into the container using the newly provisioned user
ssh adminsetup@<container-ip>

# 3. Clone the repository and run the automated deployment
git clone https://github.com/Upwind1647/infrastructure-lab.git
cd infrastructure-lab
bash scripts/deploy.sh

# 4. Verify application is running locally via Docker and reachable via UFW
curl localhost:8000
```
