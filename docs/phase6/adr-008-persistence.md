## Context & Objective
The K3s clusters are currently ephemeral. If a pod crashes or the node reboots, we lose all Redis data.
We need to separate storage from compute. To fix this, we will set up a local NVMe-backed PV for Redis and run a disaster recovery drill to ensure that we can actually restore our data.

## Decision
We implement a local Persistent Volume (PV) and Persistent Volume Claim (PVC) using a `hostPath` configuration. Additionally, we will establish a Kubernetes CronJob for automated backups to simulate a disaster recovery protocol (DR).

## Consequences

### Positive
* **Cost Efficiency:** $0 cost. We utilize existing NVMe storage on the Proxmox host instead of cloud volumes.
* **Performance:** Local NVMe ensures ultra-low latency for Redis operations, avoiding network-attached storage bottlenecks.
* **Resilience:** The data survives pod evictions and container restarts.

### Negative
* **Node Lock-in:** `hostPath` volumes tie the pod to a specific physical node. In a multi-node cluster, this would prevent the pod from failing over to another node with its data intact.
* **Manual DR:** Backups and disaster recovery drills require custom CronJobs and manual intervention, lacking the automated snapshot features of managed cloud databases.
