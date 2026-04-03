# ADR 009: Ingress Controller and Automated TLS

## Context

The Status API requires a secure entry point from outside the K3s cluster. We need an Ingress Controller to route external HTTP and HTTPS traffic to our internal Kubernetes Services, as well as a mechanism to automate the provisioning and rotation of TLS certificates.

We evaluated two approaches for the Ingress Controller:

1. **Nginx Ingress Controller:** The industry standard, but requires deploying additional pods and webhooks into the cluster.
2. **Traefik Ingress Controller:** Natively packaged and enabled by default in our K3s distribution.

## Decision

Furthermore, we will install cert-manager to handle automated TLS certificate provisioning. We will use a self-signed issuer for initial local validation, followed by a migration to Let's Encrypt.

## Consequences

### Positive

* **Resource Efficiency:** Traefik is already embedded in our K3s setup. Using it avoids the CPU and memory overhead of deploying a separate Nginx controller on our resource-constrained Proxmox host.
* **Zero-Maintenance Overhead:** `cert-manager` eliminates manual certificate rotation, significantly reducing operational toil.
* **Security by Default:** We enforce HTTPS for all external traffic, adhering to strict security baselines before exposing any workloads.

### Negative

* **Cluster Complexity:** Adding `cert-manager` introduces new Custom Resource Definitions (CRDs) like `ClusterIssuer` and `Certificate` into the cluster state.
