import os
import sys
import logging
import json
from contextlib import asynccontextmanager
from datetime import timezone
from typing import Generator

from fastapi import Depends, FastAPI, Header, HTTPException, Query, Response, status
from prometheus_fastapi_instrumentator import Instrumentator
import redis
from sqlalchemy import select, text
from sqlalchemy.exc import IntegrityError, SQLAlchemyError
from sqlalchemy.orm import Session
import uvicorn

from db import DATABASE_URL, Base, SessionLocal, engine
from models import DeploymentEvent
from schemas import DeploymentEventCreate, DeploymentEventRead


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
APP_ENV = os.getenv("APP_ENV", "local")

# Redis Config
REDIS_HOST = os.getenv("REDIS_HOST", "localhost")
redis_client = redis.Redis(
    host=REDIS_HOST,
    port=6379,
    db=0,
    decode_responses=True,
    socket_connect_timeout=2,
    socket_timeout=2,
    health_check_interval=30,
)


def get_deploy_event_token() -> str:
    return os.getenv("DEPLOY_EVENT_TOKEN", "")


def get_db() -> Generator[Session, None, None]:
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


# Application Lifespan Event Management
@asynccontextmanager
async def lifespan(app: FastAPI):
    # Log the startup event with the current environment
    logger.info("Application starting in %s mode.", APP_ENV)

    try:
        redis_client.ping()
    except redis.exceptions.RedisError as exc:
        logger.warning("Redis unavailable at startup (%s): %s", REDIS_HOST, exc)

    if DATABASE_URL.startswith("sqlite"):
        Base.metadata.create_all(bind=engine)

    try:
        with engine.connect() as connection:
            connection.execute(text("SELECT 1"))
    except SQLAlchemyError as exc:
        logger.warning("Database unavailable at startup: %s", exc)

    yield

    # Log the shutdown event
    logger.info("Application shutting down.")


# Initialize FastAPI and attach lifespan handler
app = FastAPI(lifespan=lifespan)
instrumentator = Instrumentator(excluded_handlers=["/metrics"])
instrumentator.instrument(app).expose(app, endpoint="/metrics", include_in_schema=False)


# API Route Definitions
@app.get("/")
def read_root():
    logger.info("Root endpoint accessed.")
    return {"message": "Hello from the Infrastructure Lab!", "env": APP_ENV}


@app.get("/health")
def health_check():
    return Response(status_code=200)


# Count endpoint hits using Redis
@app.get("/hits")
def read_hits():
    try:
        hits = redis_client.incr("visitor_hits")  # Increment hit counter
        return {"message": "Redis is working", "hits": hits}
    except redis.exceptions.ConnectionError:  # Redis unavailable
        logger.error("Failed to connect to Redis at %s", REDIS_HOST)
        raise HTTPException(
            status_code=503, detail="Redis connection failed"
        )  # Raise an HTTP 503 error if there is a Redis connection failure
    except redis.exceptions.RedisError as exc:
        logger.error("Redis operation failed: %s", exc)
        raise HTTPException(status_code=503, detail="Redis unavailable")


@app.post(
    "/api/deployments",
    response_model=DeploymentEventRead,
    status_code=status.HTTP_201_CREATED,
)
def create_deployment_event(
    payload: DeploymentEventCreate,
    db: Session = Depends(get_db),
    deploy_token: str | None = Header(default=None, alias="X-Deploy-Token"),
):
    expected_token = get_deploy_event_token()
    if not expected_token:
        raise HTTPException(
            status_code=503,
            detail="Deployment event token is not configured",
        )
    if deploy_token != expected_token:
        raise HTTPException(status_code=401, detail="Invalid deployment token")

    committed_at = payload.committed_at
    if committed_at.tzinfo is None:
        committed_at = committed_at.replace(tzinfo=timezone.utc)

    event = DeploymentEvent(
        git_sha=payload.git_sha,
        committed_at=committed_at,
        environment=payload.environment,
        status=payload.status,
    )
    db.add(event)

    try:
        db.commit()
        db.refresh(event)
        return event
    except IntegrityError:
        db.rollback()
        existing = db.scalar(
            select(DeploymentEvent).where(
                DeploymentEvent.git_sha == payload.git_sha,
                DeploymentEvent.environment == payload.environment,
                DeploymentEvent.status == payload.status,
                DeploymentEvent.committed_at == committed_at,
            )
        )
        if existing is None:
            raise HTTPException(status_code=409, detail="Duplicate deployment event")
        return existing
    except SQLAlchemyError as exc:
        db.rollback()
        logger.error("Failed to persist deployment event: %s", exc)
        raise HTTPException(status_code=503, detail="Database is unavailable")


@app.get("/api/deployments", response_model=list[DeploymentEventRead])
def list_deployment_events(
    db: Session = Depends(get_db),
    limit: int = Query(default=50, ge=1, le=500),
    environment: str | None = Query(default=None, min_length=2, max_length=64),
):
    query = (
        select(DeploymentEvent)
        .order_by(DeploymentEvent.deployed_at.desc())
        .limit(limit)
    )
    if environment:
        query = query.where(DeploymentEvent.environment == environment)
    return list(db.scalars(query).all())


# Application entrypoint
if __name__ == "__main__":
    # If the script is run directly start an ASGI server using uvicorn.
    # Binds to all interfaces on port 8000.
    uvicorn.run(app, host="0.0.0.0", port=8000)
