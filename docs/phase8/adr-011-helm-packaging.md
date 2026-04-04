# ADR 011: Helm for Kubernetes Package Management

## Context

Our Kubernetes workloads currently consist of static YAML manifests for the Deployment, Service, Ingress and Redis StatefulSet. Managing these files across multiple environments (Homelab vs. AWS) leads to copy-paste duplication and configuration drift, as values like image tags, replica counts, domain names and resource limits are hardcoded directly into the manifests.

We evaluated three approaches:

1. **Continue with static manifests** and use `kustomize` overlays for environment-specific values.
2. **Introduce Helm v3** as the industry-standard package manager to template our manifests.
3. **Adopt Helm v4** for Server-Side Apply (SSA) and the updated OCI-native dependency model.

## Decision

We choose Helm v4 specifically over v3 because its Server-Side Apply (SSA) engine aligns with ArgoCD's reconciliation model, avoiding the field-ownership conflicts that the legacy 3-way strategic merge patch can produce in GitOps workflows.

We will deploy the chart manually first to fully understand the templating mechanics before introducing GitOps automation in a later phase.

## Consequences

### Positive

- **DRY Principle:** A single set of templates serves both the Homelab and AWS environments. Environment differences are expressed entirely in `values.yaml` and `values-prod.yaml`, not in the templates themselves.
- **Versioned Releases:** `helm install` and `helm upgrade` create named, versioned releases with a built-in rollback capability (`helm rollback`), replacing the stateless `kubectl apply` workflow.
- **Server-Side Apply (SSA):** Helm v4 delegates via SSA. This eliminates field-ownership conflicts (e.g., ArgoCD + Helm operating on the same resource), making the stack more robust for our upcoming GitOps integration.
- **GitOps Readiness:** Helm v4 is fully supported by ArgoCD.

### Negative

- **Template Complexity:** Go-Templating syntax (pipelines, `range`, `with`) introduces a new DSL on top of YAML, increasing cognitive overhead for contributors unfamiliar with the syntax.
- **Debugging Overhead:** Rendering errors in templates can produce cryptic failure messages, requiring `helm template --debug` as a mandatory validation step before any apply.

### Design Choice: Multi-Chart Architecture (Blast Radius)
We explicitly separated our workloads into **multiple, isolated Helm charts** (e.g., `helm/status-api/` and `helm/redis/`) rather than using subcharts.
* **Separation of Concerns:** Stateful infrastructure (databases) has a completely different lifecycle, risk profile, and update frequency than stateless APIs.
* By managing them as completely independent Helm releases, we prevent accidental database deletion or disruption during routine API rollbacks, strictly minimizing the blast radius.

### Operational Model: Independent Releases

- **Stateless release:** `status-api-lab` is managed independently and can be upgraded or rolled back without touching Redis objects.
- **Stateful release:** `redis-lab` is managed in its own release cycle so database changes can follow tighter review windows.
- **Verification expectation:** `helm ls` should always show two releases for this stack (`status-api-lab` and `redis-lab`) to confirm blast-radius isolation is preserved.
