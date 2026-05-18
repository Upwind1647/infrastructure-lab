import os
import redis
from sqlalchemy import delete
from unittest.mock import patch

import pytest
from fastapi.testclient import TestClient

os.environ.setdefault("DATABASE_URL", "sqlite:///./tests/test_status_api.db")
os.environ.setdefault("DEPLOY_EVENT_TOKEN", "test-token")

from app import app
from db import Base, SessionLocal, engine
from models import DeploymentEvent

client = TestClient(app)  # FastAPI test client


@pytest.fixture(autouse=True)
def reset_deployment_events_table():
    Base.metadata.create_all(bind=engine)
    with SessionLocal() as db:
        db.execute(delete(DeploymentEvent))
        db.commit()
    yield


def test_read_root():
    # Test root endpoint returns message and env
    response = client.get("/")
    expected_env = os.getenv("APP_ENV", "local")

    assert response.status_code == 200
    assert response.json() == {
        "message": "Hello from the Infrastructure Lab!",
        "env": expected_env,
    }


def test_health_check():
    # Test health endpoint returns 200
    response = client.get("/health")
    assert response.status_code == 200


def test_metrics_endpoint():
    # Test metrics endpoint has Prometheus output
    response = client.get("/metrics")
    assert response.status_code == 200
    assert "text/plain" in response.headers["content-type"]
    assert "http_requests_total" in response.text


@patch("app.redis_client.incr")
def test_hits_endpoint_success(mock_incr):
    # Test /hits returns hits from Redis
    mock_incr.return_value = 42

    response = client.get("/hits")

    assert response.status_code == 200
    assert response.json() == {"message": "Redis is working", "hits": 42}


@patch("app.redis_client.incr")
def test_hits_endpoint_failure(mock_incr):
    # Test /hits returns 503 if Redis fails
    mock_incr.side_effect = redis.exceptions.ConnectionError("Mocked connection error")

    response = client.get("/hits")

    assert response.status_code == 503
    assert response.json() == {"detail": "Redis connection failed"}


def test_create_deployment_event_success():
    payload = {
        "git_sha": "4c9802b",
        "committed_at": "2026-04-13T12:00:00+00:00",
        "environment": "production",
        "status": "success",
    }

    response = client.post(
        "/api/deployments",
        json=payload,
        headers={"X-Deploy-Token": "test-token"},
    )

    assert response.status_code == 201
    body = response.json()
    assert body["git_sha"] == payload["git_sha"]
    assert body["environment"] == payload["environment"]
    assert body["status"] == payload["status"]
    assert "deployed_at" in body


def test_create_deployment_event_requires_valid_token():
    payload = {
        "git_sha": "4c9802b",
        "committed_at": "2026-04-13T12:00:00+00:00",
        "environment": "production",
        "status": "success",
    }

    response = client.post(
        "/api/deployments",
        json=payload,
        headers={"X-Deploy-Token": "wrong-token"},
    )

    assert response.status_code == 401
    assert response.json() == {"detail": "Invalid deployment token"}


def test_create_deployment_event_rejects_invalid_sha():
    payload = {
        "git_sha": "bad-sha",
        "committed_at": "2026-04-13T12:00:00+00:00",
        "environment": "production",
        "status": "success",
    }

    response = client.post(
        "/api/deployments",
        json=payload,
        headers={"X-Deploy-Token": "test-token"},
    )

    assert response.status_code == 422


def test_create_deployment_event_is_idempotent_for_duplicate_payload():
    payload = {
        "git_sha": "4c9802b",
        "committed_at": "2026-04-13T12:00:00+00:00",
        "environment": "production",
        "status": "success",
    }

    first = client.post(
        "/api/deployments",
        json=payload,
        headers={"X-Deploy-Token": "test-token"},
    )
    second = client.post(
        "/api/deployments",
        json=payload,
        headers={"X-Deploy-Token": "test-token"},
    )
    listed = client.get("/api/deployments")

    assert first.status_code == 201
    assert second.status_code == 201
    assert listed.status_code == 200
    assert len(listed.json()) == 1
