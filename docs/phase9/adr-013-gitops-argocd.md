# ADR 013: GitOps with ArgoCD for Kubernetes Delivery

## Context

Our Kubernetes workloads are currently packaged as Helm charts but deployed imperatively with manual commands.

This model creates operational gaps:

- Drift can accumulate between Git and the live cluster.
- Rollouts depend on operator access and timing.
- Recovery from accidental kubectl changes is manual.
- Promotion to a future hybrid footprint (including EKS) has no pull-based control plane.

We evaluated three approaches:

1. Continue with imperative Helm commands (`helm upgrade --install`) from operator terminals.
2. Adopt FluxCD and model chart reconciliation with Flux controllers.
3. Adopt ArgoCD with an App of Apps topology and Helm chart sources.

## Decision

We adopt ArgoCD as the GitOps controller for this platform.

- ArgoCD is installed in the local K3s cluster via Helm with explicit resource requests and limits.
- ArgoCD UI is published through Traefik Ingress at `argocd.lab.northlift.net` with cert-manager TLS.
- A root Application (`gitops/apps/root.yaml`) manages child Applications:
  - `cert-manager` (cert-manager controller release)
  - `cluster-issuers` (ClusterIssuers configuration)
  - `redis` (stateful Redis release)
  - `status-api` (API release)
- Child Applications enable automated sync with prune and self-heal.
- CI updates `helm/status-api/values-prod.yaml` image tag after successful image push, and ArgoCD reconciles deployments from Git.

We reject imperative Helm as the steady-state model because it cannot enforce continuous reconciliation. We reject Flux for this phase because ArgoCD provides a simpler operator experience for this lab through built-in application health views, sync history, and Helm-native workflows already used in the repository.

## Consequences

### Positive

- Git becomes the single source of truth for desired cluster state.
- Drift correction is automatic through self-heal and periodic reconciliation.
- Bootstrap is standardized to a single root apply operation.
- Existing Helm charts are reused without rewriting workloads.
- The same pull-based operating model can be extended to EKS in later phases.

### Negative

- ArgoCD introduces additional control-plane components that must be monitored and upgraded.
- Public UI exposure requires tighter security controls (credential rotation and optional ingress restrictions).
- Cert-manager and DNS-01 token management become a hard prerequisite for TLS readiness.
- CI write-back to Git requires loop-prevention guards and branch permission governance.
