import os
from fastapi.testclient import TestClient
from app import app

client = TestClient(app)


def test_read_root():
    response = client.get("/")
    expected_env = os.getenv("APP_ENV", "local")

    assert response.status_code == 200
    assert response.json() == {
        "message": "Hello from the Infrastructure Lab!",
        "env": expected_env,
    }


def test_health_check():
    response = client.get("/health")
    assert response.status_code == 200


def test_metrics_endpoint():
    response = client.get("/metrics")
    assert response.status_code == 200
    assert "cpu_usage" in response.json()
