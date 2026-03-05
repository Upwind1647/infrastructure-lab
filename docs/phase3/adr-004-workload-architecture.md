# ADR 004: Container Workload Architecture & Process Management

## Context

We are migrating the FastAPI application from a native `systemd` + `venv` deployment to a containerized architecture. We need to define the structural design of the Docker image and how the container's lifecycle is managed on the resource-constrained Proxmox host.

## Decisions

### 1. Multi-Stage Docker Builds
* **Decision:** We use a two-stage build process (`builder` and `runner`).
* **Justification:** The `builder` stage is responsible for fetching dependencies and compiling packages. The `runner` stage only copies the fully assembled virtual environment. This reduces the final image footprint and minimizes the attack surface by excluding compiler tools (like `gcc`) from the production environment.

### 2. Unprivileged Container Execution
* **Decision:** The application runs as a dedicated, non-root user (`appuser`) inside the container.
* **Justification:** Running workloads as `root` inside a container violates the Principle of Least Privilege. By creating a specific user and group (`appgroup`) without login shells, we mitigate the risk of container breakout vulnerabilities.

### 3. Custom Watchdog vs. Docker Restart Policies
* **Decision:** Instead of relying on Docker's native `restart: always` policy, we manage the container lifecycle using a custom Python script (`watchdog.py`) wrapped in a `systemd` unit.
* **Justification:** This acts as a "Poor Man's Kubelet". Rather than just ensuring the Docker process is running, the watchdog actively polls the application's HTTP `/health` endpoint. If the FastAPI application deadlocks but the container process stays alive, the watchdog will detect the timeout, destroy the container, and spin up a fresh instance.

### 4. Separation of Concerns (Day 0 vs Day 1)
* **Decision:** We strictly separate host provisioning from application deployment.
* **Justification:** Infrastructure dependencies (like installing Docker and UFW) are handled by `setup_me.sh` (running as `root`). The actual workload deployment and `.env` generation are handled by `deploy.sh` (running as unprivileged `adminsetup`). This prevents privilege escalation during routine deployments.
