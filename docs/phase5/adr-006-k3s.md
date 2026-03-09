# ADR 006: Lightweight Kubernetes (K3s) on Proxmox VM

## Context
We need a Kubernetes environment for our FastAPI application. The Proxmox host is resource-constrained (Ryzen 5, 4 Cores). We evaluated using standard Kubernetes (K8s) versus K3s, and LXC containers versus a full Virtual Machine (VM).

## Decision
We will provision a dedicated Debian Virtual Machine (VM) on Proxmox and install **K3s** (Lightweight Kubernetes).

## Consequences
* **Positive:** K3s reduces overhead compared to K8s, fitting our CPU limits. Using a VM instead of an LXC container ensures proper kernel isolation required for Kubernetes networking (CNI) and cgroups.
* **Negative:** A VM has slightly higher base memory and boot-time overhead than an LXC container.
