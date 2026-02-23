import os
import sys
import logging
import json
from contextlib import asynccontextmanager

from fastapi import FastAPI, Response
import uvicorn


# JSON Formatter for Logging
class JsonFormatter(logging.Formatter):
    def format(self, record):
        log_record = {
            "level": record.levelname,  # e.g. INFO, ERROR
            "message": record.getMessage(),  # Log message content
            "module": record.module,  # Module name that logged the event
            "timestamp": self.formatTime(record),  # Timestamp
        }
        return json.dumps(log_record)  # Convert dict to JSON


# Create a logger for the app "StatusAPI"
logger = logging.getLogger("StatusAPI")

# Set up logging to the terminal
handler = logging.StreamHandler(sys.stdout)
handler.setFormatter(JsonFormatter())  # Use JsonFormatter
logger.addHandler(handler)
logger.setLevel(logging.INFO)  # Default log level set to INFO

# Reads the "APP_ENV" to determine the current environment
APP_ENV = os.getenv("APP_ENV")


# Application Lifespan Event Management
@asynccontextmanager
async def lifespan(app: FastAPI):
    if not APP_ENV:
        # Check for environment variable
        logger.critical("FATAL: APP_ENV not set! Exiting.")
        raise SystemExit(1)

    # Log the startup event with the current environment
    logger.info("Application starting in %s mode.", APP_ENV)
    yield

    # Log the shutdown event
    logger.info("Application shutting down.")


# Initialize FastAPI and attach lifespan handler
app = FastAPI(lifespan=lifespan)


# API Route Definitions
@app.get("/")
def read_root():
    logger.info("Root endpoint accessed.")
    return {"message": "Hello from the Infrastructure Lab!", "env": APP_ENV}


@app.get("/health")
def health_check():
    return Response(status_code=200)


@app.get("/metrics")
def metrics():
    return {"cpu_usage": 12, "memory_usage": "45MB", "requests_total": 105}


# Application entrypoint
if __name__ == "__main__":
    # If the script is run directly start an ASGI server using uvicorn.
    # Binds to all interfaces on port 8000.
    uvicorn.run(app, host="0.0.0.0", port=8000)
