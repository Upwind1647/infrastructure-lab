# ADR 007: Infrastructure as Code for Proxmox

## Context
We need to provision a Debian VM for K3s on our Proxmox host.

## Decision
We will use **OpenTofu** with the `bpg/proxmox` provider to declaratively provision the K3s Virtual Machine.

## Consequences
* **Positive:** Complete reproducibility. The VM configuration (CPU, RAM, network) is version-controlled and peer-reviewed. We avoid "configuration drift" in our homelab.
* **Negative:** Requires initial setup of Proxmox API tokens and an underlying Cloud-Init template.
