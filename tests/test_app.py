import os
import redis
from unittest.mock import patch
from fastapi.testclient import TestClient
from app import app

client = TestClient(app)  # FastAPI test client


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
    # Test metrics endpoint has cpu_usage
    response = client.get("/metrics")
    assert response.status_code == 200
    assert "cpu_usage" in response.json()


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
