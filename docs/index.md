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
- [ADR-010: DNS-01 Challenge and Cloudflare Delegation](phase7/adr-010-dns01.md)

### Phase 8: Package Management
Migrate Kubernetes manifests into a Helm chart.
- [ADR-011: Helm Package Management](phase8/adr-011-helm-packaging.md)
- [ADR-012: Migrate Redis to Helm](phase8/adr-012-redis-helm.md)

### Phase 9: GitOps
Establish ArgoCD as the pull-based control plane and migrate Helm releases to declarative Applications.
- [ADR-013: GitOps with ArgoCD](phase9/adr-013-gitops-argocd.md)

### Phase 10: GitOps Secrets & Zero Trust Access
Establish encrypted secret delivery with Bitnami Sealed Secrets, automate DNS routing with external-dns, and classify services as public, tunnel-only, or internal-only.
- [ADR-014: GitOps Secrets Management with Sealed Secrets](phase10/adr-014-gitops-secrets-management-with-sealed-secrets.md)
- [ADR-015: Automated DNS Management with External-DNS](phase10/adr-015-automated-dns-management-with-external-dns.md)
- [ADR-016: Zero Trust Access with Cloudflare Tunnels](phase10/adr-016-zero-trust-access-with-cloudflare-tunnels.md)

### Phase 11: Cloudflare IaC
Close the final manual Cloudflare gap by managing tunnel routing, Access applications, and Access policies as code with OpenTofu and GitHub Actions.
- [ADR-018: Cloudflare Infrastructure as Code](phase11/adr-018-cloudflare-iac.md)

### Phase 12: Hybrid GitOps and EKS FinOps
Extend the platform into a Hub-and-Spoke multi-cluster model where on-prem ArgoCD manages both local K3s and AWS EKS with explicit FinOps controls.
- [ADR-019: Hybrid GitOps and Multi-Cluster Architecture](phase12/adr-019-hybrid-gitops-multi-cluster-architecture.md)
- [ADR-020: EKS Provisioning and FinOps Strategy](phase12/adr-020-eks-provisioning-finops-strategy.md)
- [ADR-021: Ingress Controller Strategy per Environment](phase12/adr-021-ingress-controller-strategy-per-environment.md)

### Phase 13: Full-Picture Observability
Add a constrained in-cluster whitebox stack (Prometheus, Loki, Grafana) and a lifecycle-coupled AWS blackbox canary layer for external uptime validation.
- [Observability Runbook](phase13/observability.md)
- [ADR-022: Observability Strategy for Hybrid GitOps](phase13/adr-022-observability-strategy.md)

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
