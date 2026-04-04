# ADR 012: First-Party Helm Chart for Stateful Workloads

## Context
During the migration to Helm (Phase 8), we recognized that managing our Redis database via raw YAML manifests prevents essential operational features like versioning, dry-runs, and `helm rollback`.
We evaluated three approaches for managing our stateful database:
1. **Raw YAML:** Keep the existing manifests (rejected due to lack of lifecycle management).
2. **Third-Party Chart (Bitnami Redis):** The industry standard for deploying Redis on Kubernetes.
3. **First-Party Chart:** Wrapping our highly customized, existing StatefulSet and Backup CronJob into a dedicated `helm/redis/` chart.

## Decision
We decided to build a **First-Party Helm Chart** for Redis.
While the Bitnami chart is the industry standard, it is highly complex, abstract, and built to support Sentinel, clustering, and generic cloud PVCs. Our environment is a resource-constrained Proxmox homelab where we specifically engineered a lightweight setup using K3s `local-path` on NVMe and a custom CronJob for DR. Rebuilding this exact constraint-driven architecture within the massive Bitnami values structure would add unnecessary bloat and reduce our understanding of the underlying mechanics.

### Rejected Alternative: Raw YAML

Raw manifests were rejected because they provide no release history, no dry-run packaging workflow, and no native rollback mechanism. For stateful workloads, this creates unnecessary operational risk during change windows.

### Rejected Alternative: Bitnami Redis Chart

Bitnami Redis was rejected for this lab because it optimizes for generic enterprise scenarios that exceed our scope and resource budget. Specifically:

- It introduces a much larger values surface area than our focused single-node design needs.
- It adds abstraction layers that make backup and restore behavior harder to audit for this project.
- It shifts day-2 operations toward upstream chart semantics instead of our explicit first-party DR contract.

### Why First-Party Helm Fits This Lab

Our first-party chart keeps the operational contract explicit and reviewable:

- StatefulSet lifecycle and PVC behavior are versioned in one dedicated chart.
- Backup schedule and retention are controlled through chart values.
- Redis remains independently releasable from the status API, preserving low blast radius during rollbacks.

## Consequences

### Positive
* **Operational Maturity:** We gain Helm's native versioning, `helm upgrade`, and `helm rollback` capabilities for our database.
* **Full Control:** We maintain exact control over our tailored NVMe backup logic and resource limits.
* **Educational Value:** Building a stateful chart from scratch reinforces deep Kubernetes primitives (StatefulSets, Headless Services, PVC binding).

### Negative
* **Maintenance Burden:** We are responsible for patching, updating, and maintaining the chart templates, rather than relying on the open-source community.
