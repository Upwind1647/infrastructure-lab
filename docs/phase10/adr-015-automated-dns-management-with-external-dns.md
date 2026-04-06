# ADR 015: Automated DNS Management with External-DNS

## Context

Public application exposure in the homelab currently requires manual DNS mapping when new Ingress hostnames are introduced. In practice this often means local hosts file updates before endpoints become reachable.

This model conflicts with our GitOps objectives:

1. DNS state is not reconciled from Git.
2. Onboarding and promotion workflows are slower because routing depends on manual operator steps.
3. Deleting an Ingress does not automatically remove stale DNS records.

Foundational prerequisites already exist in this repository:

- ADR 010 delegated `northlift.net` to Cloudflare for DNS automation.
- ADR 014 introduced Sealed Secrets and already prepared a namespace-scoped Cloudflare token for `external-dns`.

We evaluated three approaches:

1. Continue manual DNS or hosts file mapping.
2. Use static wildcard records and accept coarse routing control.
3. Deploy external-dns in-cluster and reconcile DNS records from Kubernetes Ingress resources.

## Decision

We adopt external-dns using the official Helm chart repository and manage it through ArgoCD App of Apps.

Implementation details:

- Create ArgoCD Application `external-dns` in `gitops/apps/external-dns.yaml` with sync-wave `3`.
- Shift `status-api` Application sync-wave to `4` so DNS automation is established before workload sync.
- Use the official chart source:
  - repo: `https://kubernetes-sigs.github.io/external-dns/`
  - chart: `external-dns`
- Configure Cloudflare with sealed token authentication:
  - secret name: `cloudflare-api-token-secret`
  - key: `api-token`
  - namespace: `external-dns`
  - environment variable: `CF_API_TOKEN`
- Enforce critical DNS ownership and safety values:
  - `domainFilters: [northlift.net]`
  - `policy: sync`
  - `txtOwnerId: "k3s-homelab"`
  - `txtPrefix: "_edns."`
  - Cloudflare proxy enabled via chart-compatible argument `cloudflare-proxied=true`

Operational behavior:

1. When an Ingress with a hostname under `northlift.net` is created or updated, external-dns reconciles the corresponding DNS record in Cloudflare.
2. When that Ingress is removed, external-dns removes the managed DNS record because policy is set to `sync`.
3. Cloudflare proxying is enabled for managed records to avoid exposing direct home endpoint details where applicable.

## Consequences

### Positive

- Eliminates manual hosts file operations for public ingress routes.
- DNS lifecycle (create, update, delete) is driven by declarative Kubernetes state.
- Improves GitOps reproducibility by keeping routing behavior in-cluster and continuously reconciled.
- Uses TXT ownership metadata to reduce cross-controller record contention.
- Enables globally resolvable endpoints such as `lab.northlift.net` without local machine overrides.

### Negative

- Introduces an additional controller that must be monitored and upgraded.
- Adds runtime dependency on Cloudflare API availability and rate limits.
- `policy: sync` can remove records if scope boundaries are misconfigured.
- Shared Cloudflare token reuse across components still carries blast-radius concerns until token separation is introduced.

## Status

Accepted and implemented in the Phase 10 GitOps workflow.
