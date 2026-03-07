import os
from fastapi.testclient import TestClient
from app import app

os.environ["APP_ENV"] = "testing"

client = TestClient(app)


def test_read_root():
    response = client.get("/")
    assert response.status_code == 200
    assert response.json() == {
        "message": "Hello from the Infrastructure Lab!",
        "env": "testing",
    }


def test_health_check():
    response = client.get("/health")
    assert response.status_code == 200


def test_metrics_endpoint():
    response = client.get("/metrics")
    assert response.status_code == 200
    assert "cpu_usage" in response.json()
