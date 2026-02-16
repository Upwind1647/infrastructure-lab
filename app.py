import os
import sys
import logging
import json
from fastapi import FastAPI, Response
import uvicorn


# JSON Logging Setup
# JSON for log aggregation tools
class JsonFormatter(logging.Formatter):
    def format(self, record):
        log_record = {
            "level": record.levelname,
            "message": record.getMessage(),
            "module": record.module,
            "timestamp": self.formatTime(record),
        }
        return json.dumps(log_record)


logger = logging.getLogger("StatusAPI")
handler = logging.StreamHandler(sys.stdout)
handler.setFormatter(JsonFormatter())
logger.addHandler(handler)
logger.setLevel(logging.INFO)

app = FastAPI()

# Crash Logic
# demands an environment variable to start --> without setting APP_ENV, it dies.
APP_ENV = os.getenv("APP_ENV")
if not APP_ENV:
    logger.critical("FATAL: APP_ENV environment variable not set! Exiting.")
    sys.exit(1)

logger.info(f"Application starting in {APP_ENV} mode.")


@app.get("/")
def read_root():
    logger.info("Root endpoint accessed")
    return {"message": "Hello from the Ryzen Lab!", "env": APP_ENV}


@app.get("/health")
def health_check():
    # Simple health check
    return Response(status_code=200)


@app.get("/metrics")
def metrics():
    # Mock metrics for Prometheus integration
    return {"cpu_usage": 12, "memory_usage": "45MB", "requests_total": 105}


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
