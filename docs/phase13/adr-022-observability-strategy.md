# ADR 022: Observability Strategy for Hybrid GitOps

## Context

The platform now spans local K3s and AWS EKS with GitOps reconciliation, Zero Trust access, and IaC-driven lifecycle automation.

At this maturity level, we still lacked a full observability picture:

1. No central metrics trend visibility for cluster and workload health.
2. No centralized log aggregation across pods.
3. No external uptime validation from outside our own infrastructure.

The primary constraint is hardware: local K3s runs on a Proxmox VM with limited memory.

## Decision

We adopt a two-layer observability model:

1. Whitebox (internal): Prometheus, Loki, and Grafana on local K3s, deployed via ArgoCD.
2. Blackbox (external): CloudWatch Synthetics canary on AWS, managed by OpenTofu.

### Capacity Rationale (4 GB to 6 GB)

Before deploying observability workloads, the K3s VM memory is increased from 4096 MB to 6144 MB.

Sizing rationale:

| Component | Estimated Memory |
|---|---:|
| K3s platform baseline | ~1.6 Gi |
| Observability stack baseline | ~650 Mi |
| OS + safety buffer | ~400 Mi |
| **Total required baseline** | **~2.65 Gi** |

This leaves approximately 3.5 Gi headroom on a 6 Gi VM for query spikes and maintenance operations while preserving the project's Efficiency First principle.

### Lifecycle Coupling Decision

The CloudWatch canary lifecycle is coupled to EKS lifecycle:

1. Canary resources are created only when `enable_eks = true`.
2. Canary resources are destroyed when EKS is disabled or destroyed.
3. Canary alerts are wired into the existing `infrastructure-lab-budget-alerts` SNS topic for unified FinOps and reliability signal handling.

This avoids idle monitoring spend during EKS teardown windows and keeps cost control aligned with Phase 12 lifecycle operations.

## Consequences

### Positive

1. Internal and external observability become explicit, versioned, and reproducible.
2. Resource-constrained whitebox telemetry remains bounded by strict requests and limits.
3. External uptime failures generate centralized notifications in existing SNS alert channels.
4. Lifecycle coupling prevents orphaned canary spend during off periods.

### Negative

1. Additional operational complexity across Kubernetes, Cloudflare, and AWS observability services.
2. Two monitoring surfaces require documentation and routine verification.
3. One canary validates two endpoints per run, so endpoint-specific root-cause isolation may require log inspection.

## Status

Accepted and implemented in Phase 13.
