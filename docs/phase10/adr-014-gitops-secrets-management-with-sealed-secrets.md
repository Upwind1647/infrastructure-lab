# ADR 014: GitOps Secrets Management with Sealed Secrets

## Context

The cluster currently depends on a manual, out-of-band secret creation step for the Cloudflare DNS API token used by cert-manager DNS-01 solvers.

This creates four problems:

1. Cluster bootstrap is not fully reproducible from Git.
2. Sensitive values cannot be tracked declaratively in the same workflow as the rest of the platform.
3. Manual secret creation introduces drift and operator variance.
4. Future workloads (for example external-dns) cannot safely reuse the same GitOps path for secret delivery.

We evaluated the following options:

1. Keep manual `kubectl create secret` workflows.
2. Store plain Kubernetes Secrets in Git (base64 only).
3. Use SOPS with Age/GPG and decrypt in-cluster.
4. Use External Secrets Operator with an external secrets backend.
5. Use Bitnami Sealed Secrets with encrypted manifests stored in Git.

## Decision

We adopt Bitnami Sealed Secrets for Kubernetes secret delivery in this lab.

Implementation details:

- Deploy the Sealed Secrets controller via ArgoCD Application `sealed-secrets` with sync-wave `0`.
- Pin Helm chart version for deterministic installs.
- Run controller in `kube-system` with release/controller name `sealed-secrets`.
- Add ArgoCD Application `platform-secrets` with sync-wave `1` that reconciles `gitops/secrets`.
- Store Cloudflare token as two separate SealedSecret manifests:
  - `cloudflare-api-token-secret` in namespace `cert-manager`
  - `cloudflare-api-token-secret` in namespace `external-dns`
- Keep cert-manager `ClusterIssuer` references unchanged (`name: cloudflare-api-token-secret`, `key: api-token`).

This model keeps encrypted payloads in Git while preserving namespace scoping and full GitOps reconciliation.

## Operational Workflow

### Bootstrap

1. Install ArgoCD.
2. Apply the root app (`gitops/apps/root.yaml`).
3. ArgoCD auto-discovers child apps, including `sealed-secrets` and `platform-secrets`.
4. SealedSecret resources unseal into runtime Kubernetes Secrets.

### Create or rotate a sealed token

Use the currently active token value and generate namespace-scoped ciphertext for each target namespace.

```bash
TOKEN="<CLOUDFLARE_API_TOKEN>"

kubectl create secret generic cloudflare-api-token-secret \
  --namespace cert-manager \
  --from-literal=api-token="$TOKEN" \
  --dry-run=client -o json | kubeseal \
  --controller-name sealed-secrets \
  --controller-namespace kube-system \
  --format yaml > gitops/secrets/cloudflare-api-token-cert-manager-sealedsecret.yaml

kubectl create secret generic cloudflare-api-token-secret \
  --namespace external-dns \
  --from-literal=api-token="$TOKEN" \
  --dry-run=client -o json | kubeseal \
  --controller-name sealed-secrets \
  --controller-namespace kube-system \
  --format yaml > gitops/secrets/cloudflare-api-token-external-dns-sealedsecret.yaml
```

Commit only SealedSecret output files. Never commit plaintext Secret manifests.

## Disaster Recovery: Sealed Secrets Master Key Backup

The Sealed Secrets private key is required to decrypt existing SealedSecret resources. If it is lost, current encrypted manifests become unrecoverable.

Backup procedure:

```bash
kubectl -n kube-system get secret \
  -l sealedsecrets.bitnami.com/sealed-secrets-key=active \
  -o yaml > sealed-secrets-master-key.yaml
```

Then encrypt the backup file offline with authenticated tooling (for example `age` or `gpg`) and store it outside this repository in offline media.

Do not use `openssl enc -aes-256-cbc` for this backup workflow, because it does not provide authenticated encryption and ciphertext tampering may go undetected.

If `age` or `gpg` is not configured yet, set up one of those tools before creating the offline encrypted backup.

Store the encrypted artifact and any recovery credentials separately in offline locations.

Restore procedure (break-glass):

```bash
kubectl -n kube-system apply -f sealed-secrets-master-key.yaml
kubectl -n kube-system rollout restart deploy/sealed-secrets
```

## Consequences

### Positive

- Enables encrypted secret storage in Git without exposing plaintext values.
- Removes manual secret bootstrap steps from cluster provisioning.
- Preserves a single pull-based GitOps workflow managed by ArgoCD.
- Supports future namespace-specific secret expansion (for example external-dns).

### Negative

- Adds a controller and CRDs that require lifecycle management.
- Introduces key management responsibilities and backup obligations.
- Reusing one Cloudflare token across two namespaces increases blast radius until token separation is introduced.

## Status

Accepted and implemented in the Phase 10 GitOps workflow.
