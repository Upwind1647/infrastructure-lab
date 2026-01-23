# Admin Box & Service Architecture

## 1. Architecture Decision

### LXC Control Plane
* Proxmox LXC Containers instead of VM.
* --> because of overhead

### Systemd App-Management
* Systemd Unit Files
* --> because of logging and restart policy

## 2. Implementation Details

### Service Configuration
in Python .venv because of isolation

**Path:** `/etc/systemd/system/broken-app.service`

```ini
[Unit]
Description=Broken App Service
After=network.target

[Service]
# Security: App runs as unprivileged user
User=yuwen
Group=yuwen

# Environment Isolation
WorkingDirectory=/home/yuwen/devops-app
Environment="APP_ENV=production"

# Execution using Virtual Environment Interpreter
ExecStart=/home/yuwen/devops-app/.venv/bin/python app.py

# Resilience
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target

## 3. Pow

### Command:
sudo systemctl status broken-app

* broken-app.service - Broken App Service
     Loaded: loaded (/etc/systemd/system/broken-app.service; enabled; preset: enabled)
     Active: active (running) since Thu 2026-01-22 20:29:55 UTC
   Main PID: 1751 (python)
      Tasks: 1 (limit: 37143)
     Memory: 28.7M
     CGroup: /system.slice/broken-app.service
             `-1751 /home/yuwen/devops-app/.venv/bin/python app.py
