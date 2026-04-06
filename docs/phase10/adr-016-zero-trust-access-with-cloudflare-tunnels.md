# ADR 016: Zero Trust Access with Cloudflare Tunnels

## Context

Internal platform services like ArgoCD should not be exposed through inbound home-router NAT rules or directly published Ingress endpoints.

Our current state has two distinct service classes:

1. Public product surfaces (for example `lab.northlift.net`) that are intentionally internet-accessible.
2. Internal operator surfaces (for example `argocd.lab.northlift.net`) that should require stronger access controls and should not depend on inbound router exposure.

With Cloudflare DNS automation already established, we need a complementary zero-trust connectivity model that:

1. Uses outbound-only encrypted tunnels from cluster to Cloudflare edge.
2. Enforces identity-aware access controls before any request reaches internal services.
3. Preserves GitOps reconciliation and repeatable bootstrap.

We evaluated these options:

1. Keep direct ingress exposure with IP allowlists.
2. Add VPN-only access for operators.
3. Use Cloudflare Tunnel with Cloudflare Access (GitHub OAuth) for internal hostnames.

## Decision

We adopt Cloudflare Tunnel for internal service access and enforce Cloudflare Access policies using GitHub OAuth.

Implementation details:

- Deploy tunnel connector via ArgoCD Application `cloudflare-tunnel` using the official Cloudflare Helm chart.
- Run `replicaCount: 2` for high availability.
- Configure ingress routing in chart values:
  - `argocd.lab.northlift.net -> http://argocd-server.argocd.svc.cluster.local:80`
  - fallback behavior remains `http_status:404` via chart-generated ConfigMap rule.
- Store tunnel credentials as a SealedSecret in `gitops/secrets` and reference it with `cloudflare.secretName`.
- Disable direct ArgoCD ingress in the ArgoCD Helm values to enforce tunnel-only exposure.

### Service Classification

| Class | Exposure Model | Examples | Control Boundary |
| --- | --- | --- | --- |
| Public | Public DNS + Kubernetes Ingress | `lab.northlift.net` (status-api) | TLS + application auth |
| Tunnel-only | Cloudflare Tunnel hostname + Access policy | `argocd.lab.northlift.net` | Cloudflare Access (GitHub OAuth) + internal service |
| Internal-only | No public DNS and no external route | Redis, cert-manager, sealed-secrets | Cluster network + Kubernetes RBAC |

## Operational Workflow

### Cloudflare setup (Dashboard or CLI)

1. Create tunnel `lab-internal-services`.
2. Add hostname route for `argocd.lab.northlift.net` to `http://argocd-server.argocd.svc.cluster.local:80`.
3. Configure Cloudflare Access application for `argocd.lab.northlift.net`.
4. Add an allow policy constrained to approved GitHub identities.

CLI reference flow:

```bash
cloudflared tunnel login
cloudflared tunnel create lab-internal-services
cloudflared tunnel route dns lab-internal-services argocd.lab.northlift.net
```

Then configure the Access application and GitHub OAuth policy in Cloudflare Zero Trust (Dashboard), or via API/Terraform if your account automation is already in place.

### Seal credentials for GitOps

Generate a namespace-scoped SealedSecret for the tunnel credentials JSON:

```bash
kubectl create secret generic cloudflare-tunnel-credentials \
  --namespace cloudflare-tunnel \
  --from-file=credentials.json=./credentials.json \
  --dry-run=client -o json | kubeseal \
  --controller-name sealed-secrets \
  --controller-namespace kube-system \
  --format yaml > gitops/secrets/cloudflare-tunnel-credentials-sealedsecret.yaml
```

Commit only the resulting SealedSecret manifest. Do not commit plaintext credentials.

## Consequences

### Positive

- Removes dependency on inbound router exposure for internal operator endpoints.
- Adds identity-aware access checks before traffic reaches ArgoCD.
- Keeps connectivity and access controls declarative alongside existing GitOps assets.

### Negative

- Introduces a new control-plane dependency on Cloudflare Tunnel and Access availability.
- Requires secure lifecycle management for tunnel credentials and rotation procedures.
- Misconfigured Access policy can either overexpose or unintentionally block operator access.

## Status

Accepted and implemented in Phase 10 with Cloudflare Tunnel and Access controls for internal hostnames.
