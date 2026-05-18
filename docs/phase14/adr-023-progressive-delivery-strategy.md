# ADR 023: Progressive Delivery Strategy

## Context

The platform currently deploys status-api by standard Kubernetes rolling updates. This does not provide automated metric-gated promotion or rollback behavior and does not close the DORA feedback loop into Grafana.

Phase 14 introduces Argo Rollouts, deployment event ingestion and DORA reporting based on PostgreSQL data.

## Decision

1. Use Argo Rollouts for progressive delivery in both clusters.
2. Keep traffic strategy environment-specific:
   1. EKS uses ingress-nginx traffic routing.
   2. K3s uses replica-weight canary progression.
3. Use token-protected deployment event ingestion endpoint at /api/deployments.
4. Treat migrations with an expand/contract policy:
   1. Pre-rollout migrations are additive-only.
   2. Contract migrations are executed after successful promotion in a later release.
5. Persist deployment events in PostgreSQL:
   1. EKS uses AWS RDS.
   2. K3s uses a local PostgreSQL StatefulSet.

## Consequences

### Positive

1. Canary promotion decisions become metric-driven.
2. Automated rollback reduces release blast radius.
3. Deployment Frequency and Lead Time for Changes can be computed from stored events.
4. Expand/contract policy lowers schema incompatibility risk during mixed-version canaries.

### Negative

1. Operational complexity increases across ArgoCD, Argo Rollouts, and observability integration.
2. Additional secret management is required for deployment-event tokens and datasource credentials.
3. Rollout health customization is mandatory in ArgoCD to avoid Unknown health status.

## Status

Accepted for Phase 14 implementation.
