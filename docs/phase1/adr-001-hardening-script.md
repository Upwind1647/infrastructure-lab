# ADR 001: Use of Bash Scripts for Initial Server Hardening

## Context

We are provisioning a "Admin Box" as a lightweight LXC container (Debian) on a Proxmox host with resource limits (512 MB RAM). The objective is to establish a baseline security configuration before deploying applications.

We evaluated two approaches for configuration management:

1.  **Ansible**

2.  **Bash Scripting**

## Decision

We will use **Bash scripts** to provision and harden the initial LXC container.

## Consequences

### Positive

* **Resource Efficiency:** Bash is native to Debian. It requires no additional agent installation, Python dependencies, or control node overhead, aligning with our strict hardware constraints.

* **Zero-Dependency Bootstrap:** The container can be set up immediately without external package repositories or Python environments being pre-configured.

### Negative

* **Complexity & Maintenance:** Ensuring that the script can run multiple times without side effects requires manual logic, which is error-prone compared to Ansible's declarative modules.

* **Scalability:** This approach does not scale well to multiple nodes.

* **Readability:** Bash scripts can become difficult to read and debug as logic complexity increases.
