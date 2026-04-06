# ADR 017: ArgoCD Self-Management and GitOps Maturity

## Context

ArgoCD is currently installed by `scripts/install_argocd.sh` using imperative Helm commands.

That bootstrap works, but Day-2 configuration changes in ArgoCD values were not continuously reconciled from Git. In practice, updates to ArgoCD settings required manual `helm upgrade` execution.

This created a remaining drift gap in an otherwise pull-based platform:

- Git was not the active reconciler for ArgoCD's own Helm values.
- Manual operations were required for ArgoCD configuration evolution.
- Configuration drift could persist silently if operators forgot manual upgrades.

We need ArgoCD to reconcile its own configuration after bootstrap while preserving a deterministic recovery path if ArgoCD is unavailable.

## Decision

We adopt ArgoCD self-management for Day-2 operations.

Implementation details:

- Add `gitops/apps/argocd.yaml` as a child Application managed by the root App of Apps.
- Set `argocd.argoproj.io/sync-wave: "-1"` so ArgoCD config reconciliation executes before other app waves.
- Use ArgoCD multi-source for the ArgoCD app:
  - Helm chart source: `argo-cd` from `https://argoproj.github.io/argo-helm`
  - Values source: `$values/gitops/argocd-values.yaml` from this repository
- Enable automated sync with prune and self-heal.
- Require `ServerSideApply=true` for safe adoption of already-existing Helm-managed resources.

### Feynman Check: Is there a chicken-and-egg problem?

Yes, and the boundary is intentional.

ArgoCD self-management controls ArgoCD configuration, not ArgoCD existence.

- Day-0 / break-glass: `scripts/install_argocd.sh` performs initial `helm upgrade --install` and remains the recovery mechanism if ArgoCD is down.
- Day-2: `gitops/apps/argocd.yaml` and `gitops/argocd-values.yaml` drive ongoing reconciliation from Git.

This preserves operability under failure while still eliminating manual Day-2 drift.

## Why Sync Wave -1

The root app auto-discovers child Applications in `gitops/apps/*.yaml`.

Using sync-wave `-1` for `argocd` ensures ArgoCD's own settings reconcile before wave `0` and higher platform apps (for example `sealed-secrets`, `cert-manager`, and workload apps).

This ordering reduces control-plane churn and avoids late reconciliation of ArgoCD behavior while other apps are actively syncing.

## Why ServerSideApply=true Is Required

At adoption time, ArgoCD reconciles resources that were originally created via bootstrap Helm install.

`ServerSideApply=true` improves coexistence with pre-existing field ownership and reduces replacement/thrash behavior when ArgoCD takes over management of the same objects.

Without it, first sync can produce ownership conflicts or noisy patch behavior on fields previously managed outside ArgoCD.

## Operational Workflow

### 1. Bootstrap (Day-0 and break-glass)

```bash
bash scripts/install_argocd.sh
kubectl apply -f gitops/apps/root.yaml
```

### 2. Safe adoption (first self-management sync)

Before committing `gitops/apps/argocd.yaml`, verify the already deployed chart version:

```bash
helm list -n argocd
```

Set `spec.sources[0].targetRevision` in `gitops/apps/argocd.yaml` to that exact deployed chart version.

This makes first sync an adoption/no-op reconcile rather than an implicit upgrade.

### 3. Upgrades after adoption

Only after the app is `Synced` and `Healthy`, bump `targetRevision` in a separate commit to perform controlled upgrades.

### 4. Day-2 change model

- Change ArgoCD settings by editing `gitops/argocd-values.yaml`.
- Push to Git.
- Let ArgoCD auto-sync.
- Do not run manual `helm upgrade` for routine Day-2 config changes.

## Consequences

### Positive

- ArgoCD configuration enters the same reconciled GitOps loop as the rest of the platform.
- Drift from manual Day-2 Helm operations is removed.
- Adoption is safer by pinning first sync to deployed chart version.
- Ordering guarantees are explicit through sync-wave `-1`.

### Negative

- Operational model now has a strict boundary that teams must understand (bootstrap vs Day-2).
- Misconfigured ArgoCD self-app can affect control-plane stability.
- Chart upgrades require deliberate version bump commits rather than ad-hoc CLI upgrades.

## Status

Accepted and implemented in Phase 10 as the GitOps maturity step for ArgoCD operations.
