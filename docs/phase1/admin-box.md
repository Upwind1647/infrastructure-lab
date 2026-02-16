# Admin Box Provisioning & Service Architecture

This document details the architectural decisions and implementation steps for the initial "Admin Box". This instance serves as the primary control plane for local operations and hosts the prototype application.

## 1. Architectural Decisions

### Compute Layer: Proxmox LXC
* **Decision:** Use Linux Containers (LXC) instead of Virtual Machines (VM).
* **Context:** The host hardware is resource-constrained (Ryzen 5, limited RAM).
* **Justification:** LXC containers share the host kernel, resulting in significantly lower memory overhead (~50MB vs ~500MB for a full VM) and faster boot times. This aligns with our "Efficiency First" principle.

### Process Management: Systemd
* **Decision:** Manage the application using native Systemd Unit Files.
* **Justification:**
    * **Resilience:** Automatic restart policies (`Restart=always`) ensure high availability without external supervisors (like Docker or SupervisorD).
    * **Observability:** Native integration with `journald` captures `stdout`/`stderr` logs automatically.
    * **Standardization:** Uses the standard Linux init system, reducing dependency on third-party tools.

---

## 2. Implementation Details

### User & Security Context
The application runs under a dedicated, unprivileged service user to adhere to the Principle of Least Privilege.

* **User:** `adminsetup`
* **Home:** `/home/adminsetup`
* **Authentication:** SSH Key-only (Password authentication disabled via `setup_me.sh`).

### Service Configuration
The FastAPI application is deployed within a Python Virtual Environment (`.venv`) to ensure dependency isolation from the system Python.

**File Path:** `/etc/systemd/system/status-api.service`

```ini
[Unit]
Description=Status API
After=network.target

[Service]
# User & Group
User=adminsetup
Group=adminsetup

# Working Directory
WorkingDirectory=/home/adminsetup/infrastructure-lab

# env.
Environment="APP_ENV=production"

# Python-Interpreter  VENV
ExecStart=/home/adminsetup/infrastructure-lab/.venv/bin/python app.py

# Restart Logic
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
```

---

## 3. Verification & Operational Status

To verify the correct deployment and operational state of the service.

### Service Status
Verify that the Systemd unit is loaded and active.

**Command:**
```bash
sudo systemctl status broken-app
```

**Output**
```text
status-api.service - Status API
     Loaded: loaded (/etc/systemd/system/status-api.service; enabled; preset: enabled)
     Active: active (running) since Mon 2026-02-16 14:35:00 CET; 10min ago
   Main PID: 1823 (python)
      Tasks: 1 (limit: 37143)
     Memory: 45.2M
        CPU: 120ms
     CGroup: /system.slice/status-api.service
             └─1823 /home/adminsetup/infrastructure-lab/.venv/bin/python app.py
```

### Application Response
The application expects the APP_ENV variable to be injected by Systemd. We verify this by curling the local endpoint.

**Command**
```bash
curl localhost:8000
```

**Output**
```json
{"message":"Hello from the Ryzen Lab!","env":"production"}
```
