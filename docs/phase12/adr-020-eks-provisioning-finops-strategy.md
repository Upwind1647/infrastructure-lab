# ADR 020: EKS Provisioning and FinOps Strategy

## Context

Hybrid GitOps in Phase 12 requires an AWS Kubernetes spoke that is:

1. Operationally simple to provision and destroy.
2. Cost-bounded for a lab environment.
3. Safe enough to avoid accidental always-on spend.

This phase also introduces cloud workload continuity requirements (`status-api-cloud`) and secret management choices for multi-cluster Sealed Secrets.

## Decision

### EKS Provisioning Baseline

1. Use a managed EKS control plane.
2. Use one managed node group with `t3.medium` and scaling bounds `min=1`, `max=2`.
3. Enable IAM OIDC provider for IRSA prerequisites.
4. Expose cluster metadata outputs (endpoint, CA data, kubeconfig context alias) for ArgoCD registration.

### FinOps Guardrails

1. Define monthly AWS Budget in Terraform with SNS email notifications.
2. Trigger alerts at 80% (warning) and 100% (critical) of the configured monthly cap.
3. Keep EKS apply as a manual operator action (no CI auto-apply).
4. Use lifecycle operations (`up`/`down`) to support weekend-only runtime and reduce idle spend.

### Budget Verification Gate (Mandatory)

Before the first EKS apply in any environment:

1. Confirm the SNS subscription email is in `Confirmed` state.
2. Confirm both budget notifications are active (80% and 100%).
3. Only then proceed with `tofu apply` for EKS resources.

### Cost Model

Target operating profile is approximately **2.50 EUR per active day** for a minimal footprint, with explicit caveats:

1. Prices vary by region, control-plane billing, and network traffic.
2. Weekend-only lifecycle is part of the model; always-on operation will exceed the target.
3. Budget alerting is detection, not enforcement.

### Sealed Secrets Key-Sharing Strategy

| Option | Description | Pros | Cons |
|---|---|---|---|
| A (Chosen) | Reuse on-prem Sealed Secrets master key in EKS | Fast migration, no immediate reseal campaign | Shared blast radius for compromise and rotation |
| B | Dedicated EKS key and reseal all secrets | Stronger isolation per cluster | Higher operational overhead and migration complexity |

We choose **Option A** for Phase 12 speed and simplicity, and document Option B as a future hardening path.

Operational key-sharing sequence for Option A:

```bash
kubectl -n kube-system get secret \
	-l sealedsecrets.bitnami.com/sealed-secrets-key \
	-o yaml > /tmp/sealed-secrets-master-key.yaml

kubectl --context=aws-eks-prod -n kube-system apply -f /tmp/sealed-secrets-master-key.yaml
```

### Why EKS Apply Stays Manual

1. Cost-sensitive infrastructure changes need explicit human confirmation after reviewing budget state.
2. Cloud apply can create irreversible billing/resource side effects if misconfigured.
3. Plan-only CI provides review visibility without accidental drift-triggered provisioning.

## Consequences

### Positive

1. Cloud cluster provisioning is reproducible and reviewable.
2. Budget notifications provide early warning before runaway spend.
3. Manual apply preserves a human control gate for high-cost changes.
4. Option A enables rapid cross-cluster secret portability in this phase.

### Negative

1. Budget alarms do not block spend automatically.
2. Manual apply increases operational dependency on runbook discipline.
3. Option A increases shared secret-key blast radius across environments.
4. Weekend-only lifecycle can delay troubleshooting outside active windows.

## Status

Accepted and implemented in Phase 12.
