import os
import time
import socket
import subprocess
from datetime import datetime

CONTAINER_NAME = "status-api"
IMAGE_TAG = "your-registry/status-api:local" # Wird später durch den SHA ersetzt
LOG_FILE = "watchdog.log"
CHECK_INTERVAL = 5

def log_event(message):
    timestamp = datetime.now().isoformat()
    log_line = f"[{timestamp}] {message}\n"
    print(log_line.strip())
    with open(LOG_FILE, "a") as f:
        f.write(log_line)

def start_container():
    log_event("Starting container...")
    subprocess.run(["docker", "rm", "-f", CONTAINER_NAME],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    result = subprocess.run([
        "docker", "run", "-d", "--name", CONTAINER_NAME,
        "-p", "8000:8000", "-e", "APP_ENV=production", IMAGE_TAG
    ], capture_output=True, text=True)

    if result.returncode != 0:
        log_event(f"ERROR: Container start failed: {result.stderr}")
        return False
    log_event(f"Container started: {result.stdout.strip()[:12]}")
    return True

def check_health():
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.settimeout(2)
            s.connect(("localhost", 8000))
            s.sendall(b"GET /health HTTP/1.0\r\nHost: localhost\r\n\r\n")
            response = s.recv(1024).decode("utf-8")
            return "200 OK" in response
    except Exception:
        return False

def run_watchdog():
    log_event("Watchdog started. Acting as Poor Man's Kubelet.")
    start_container()
    
    while True:
        time.sleep(CHECK_INTERVAL)
        is_healthy = check_health()
        
        if not is_healthy:
            log_event("CRITICAL: Health check failed or timeout. Restarting pod/container...")
            start_container()
            # Gib dem Container kurz Zeit zum Hochfahren
            time.sleep(3) 

if __name__ == "__main__":
    run_watchdog()