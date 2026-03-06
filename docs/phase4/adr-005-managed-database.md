# ADR 005: Managed Database (AWS RDS) vs. Self-Hosted EC2

## Context

Moving into Phase 4, the application requires a stateful persistence layer (Database). We need to provision a PostgreSQL database within our isolated `Data Subnet A` (`10.200.9.0/24`).
We evaluated two approaches for hosting this database:

1.  **Self-Hosted:** Provisioning a raw EC2 instance and managing the PostgreSQL installation via bash/systemd.
2.  **Managed Service:** Utilizing AWS Relational Database Service (RDS).

## Decision

We will use **AWS RDS PostgreSQL** (`db.t3.micro`) as our persistence layer.

## Consequences

### Positive

* **Zero-Maintenance Overhead:** AWS RDS handles automated backups, point-in-time recovery, and minor version patching automatically.
* **High Availability Readiness:** Moving to a Multi-AZ deployment in the future requires only a single boolean flag change in our IaC codebase (`multi_az = true`), rather than engineering complex replication clusters.
* **Security by Default:** Data-at-rest encryption (`storage_encrypted = true`) is natively integrated with AWS KMS.

### Negative

* **Cost Management:** A continuously running RDS instance consumes our credit budget faster than a comparable EC2 instance.
* **Vendor Lock-In:** Using RDS ties our persistence architecture explicitly to the AWS API, unlike a self-hosted container which could be moved to Proxmox.

### Mitigation (The Kill Switch)
To mitigate the risk of accidental billing in our lab environment, the IaC configuration explicitly sets `skip_final_snapshot = true`. This ensures `tofu destroy` executes cleanly without hanging on mandatory backup processes, allowing daily teardowns to save costs.
