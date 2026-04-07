# ADR 021: Ingress Controller Strategy per Environment

## Context

Phase 7 standardized ingress on local K3s using the built-in Traefik controller.

Phase 12 introduces a cost-controlled EKS spoke (`aws-eks-prod`) that is created and destroyed frequently as part of the FinOps lifecycle from ADR-020.

`status-api-cloud` requires a production ingress path for `aws.northlift.net` with cert-manager and external-dns integration, but EKS does not include Traefik by default.

We need an ingress decision that:

1. Works with GitOps wave ordering and fast bootstrap.
2. Supports cert-manager and external-dns without extra control-plane complexity.
3. Fits the weekend teardown model and minimizes rebuild overhead.

## Decision

We use different ingress controllers per environment:

1. Keep Traefik on local K3s (`in-cluster`) where it is already integrated and operationally stable.
2. Use ingress-nginx on EKS (`aws-eks-prod`) with Ingress class `nginx`.

Rationale:

1. ingress-nginx is a direct Kubernetes ingress controller deployment that integrates cleanly with cert-manager and external-dns.
2. It avoids introducing ALB controller and IRSA-specific integration work for this phase.
3. Lower bootstrap complexity reduces failure points during frequent EKS recreate cycles.

Implementation alignment:

1. `status-api-cloud` explicitly sets `ingress.className: nginx`.
2. EKS receives dedicated ArgoCD applications for `ingress-nginx-aws`, `cert-manager-aws`, and `cluster-issuers-aws`.
3. Existing local Traefik and local issuer flow remain unchanged.

## Consequences

### Positive

1. Environment-specific tooling is explicit and documented instead of implicitly inherited.
2. EKS ingress bootstrap becomes deterministic for GitOps waves and ephemeral rebuilds.
3. cert-manager and external-dns dependencies are satisfied without ALB/IRSA onboarding overhead.
4. Local K3s remains unchanged, preserving existing operational knowledge.

### Negative

1. Two ingress controllers now exist across the platform, increasing documentation and runbook scope.
2. Future policy hardening must be validated against both Traefik and ingress-nginx behaviors.
3. A future migration to ALB/IRSA may be required if EKS traffic scale or AWS-native requirements increase.

## Status

Accepted and implemented in Phase 12.
