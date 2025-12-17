"""
Tests for health check endpoints.
"""
import pytest


def test_health_endpoint(client):
    """Test the /health endpoint returns healthy status."""
    response = client.get("/health")
    assert response.status_code == 200

    data = response.json()
    assert data["status"] == "healthy"
    assert "version" in data


def test_root_endpoint(client):
    """Test the root endpoint returns service info."""
    response = client.get("/")
    assert response.status_code == 200

    data = response.json()
    assert "service" in data
    assert "knowverse" in data["service"].lower() or "haystack" in data["service"].lower()
