# Redis & Disaster Recovery

## 1. Concepts over Tools: StatefulSets vs. Deployments
Unlike stateless FastAPI pods, our Redis database requires a network identity and persistent storage. So, we deploy it as a `StatefulSet`.

* **Headless Service:** A standard Kubernetes `Service` distributes traffic using round-robin load balancing. For database setups, direct connections to specific pods (e.g., `redis-0`) are required. A Headless Service (`clusterIP: None`) disables load balancing and provides direct DNS records for each individual pod in the format `<pod-name>.<service-name>`.
* **Dynamic Provisioning (`local-path`):** Instead of manually creating Persistent Volumes (PVs), we utilize the built-in `local-path` StorageClass in K3s. Kubernetes automatically provisions a node-local storage directory when the pod starts, driven by the `volumeClaimTemplates` configuration.

## 2. Disaster Recovery Strategy (RDB)
In our homelab environment, we deliberately opted against AOF. We rely on RDB (Redis Database) snapshots to minimize I/O load on the Proxmox host.

### The Backup CronJob
A daily Kubernetes `CronJob` automates the backup workflow:
1. **Init-Container (`busybox`):** Before the backup executes, a lightweight `busybox` container adjusts the directory permissions on the mounted NVMe path, ensuring the `redis` user has the necessary write access.
2. **Redis Export (`redis-cli --rdb`):** The main container connects to `redis-service` and exports an RDB snapshot directly to a timestamped file in `/backup`.
3. **Retention & Rotation:** The script promotes the timestamped backup to `dump.rdb` (latest pointer) and prunes old `dump-*.rdb` files after 30 days to prevent disk exhaustion.

### Restore Procedure
In the event of severe data loss, the restore procedure is as follows:
1. Scale the Redis pod to zero replicas (`kubectl scale statefulset redis --replicas=0`).
2. On the K3s node, select a healthy backup from `/mnt/nvme-backups`.
3. Copy it into the Redis data directory that backs the `redis-data` PVC (the `local-path` volume mounted at `/data` in the Redis container) and name it `dump.rdb`.
4. Adjust file ownership to the Redis user (`sudo chown 999:999 dump.rdb`).
5. Scale the pod back to one replica. Since AOF is explicitly disabled, Redis will load the injected `dump.rdb` file during boot.
