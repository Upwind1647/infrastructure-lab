# ADR 008: Persistence & DR

## Context
The K3s clusters are currently ephemeral. If a pod crashes or the node reboots, we lose all Redis data.
We need to separate storage from compute. To fix this, we will set up a local NVMe-backed PV for Redis and run a disaster recovery drill to ensure that we can actually restore our data.

## Decision
We implement persistence using dynamic volume provisioning via the K3s `local-path` StorageClass, which automatically manages local directory-backed volumes.

## Consequences

### Positive
* **Cost Efficiency:** $0 cost. We utilize existing NVMe storage on the Proxmox host instead of cloud volumes.
* **Performance:** Node-local `local-path` volumes avoid network-attached storage overhead for Redis data in this single-node setup.
* **Resilience:** The data survives pod evictions and container restarts.

### Negative
* **Node Lock-in:** `local-path` uses node-local storage, so the Redis data volume is still tied to a specific node. In a multi-node cluster, this would prevent the pod from failing over with data unless a shared storage layer is introduced.
* **Manual DR:** Backups and disaster recovery drills require custom CronJobs and manual intervention, lacking the automated snapshot features of managed cloud databases.

### AOF vs. RDB Persistence
During our manual Disaster Recovery Drill, we identified a conflict between AOF and our automated RDB restore flow. If `--appendonly yes` is active, Redis prioritizes the AOF log over an injected `dump.rdb` during pod restart, causing restored data to be ignored.

**Mitigation:** For this environment, we disabled AOF (`--appendonly no`). We rely on a daily CronJob that exports backups with `redis-cli --rdb` to `/mnt/nvme-backups`, maintains a `dump.rdb` latest pointer, and prunes `dump-*.rdb` files older than 30 days. This raises the RPO to 24 hours, but it improves the RTO because recovery becomes a straightforward file replacement procedure into the Redis PVC path.
