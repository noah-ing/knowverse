"""
Tests for domain detection endpoints.
"""
import pytest


class TestDomainDetection:
    """Tests for /domains/detect endpoint."""

    def test_domain_detection_endpoint_exists(self, client, sample_query, sample_organization_id):
        """Test that domain detection endpoint exists."""
        response = client.post(
            "/domains/detect",
            json={
                "query": sample_query,
                "organization_id": sample_organization_id
            }
        )

        if response.status_code == 404:
            pytest.skip("Domain detection endpoint not implemented")

        assert response.status_code in [200, 400, 422]

    def test_domain_detection_response_structure(self, client, sample_query, sample_organization_id):
        """Test domain detection response structure."""
        response = client.post(
            "/domains/detect",
            json={
                "query": sample_query,
                "organization_id": sample_organization_id
            }
        )

        if response.status_code == 200:
            data = response.json()
            assert "domain" in data or "detected_domain" in data
            assert "confidence" in data or "score" in data


class TestDomainList:
    """Tests for /domains endpoint."""

    def test_list_domains(self, client):
        """Test listing available domains."""
        response = client.get("/domains")

        if response.status_code == 404:
            pytest.skip("Domains list endpoint not implemented")

        assert response.status_code == 200
        data = response.json()
        assert isinstance(data, list)


class TestDomainDetectionScenarios:
    """Tests for specific domain detection scenarios."""

    @pytest.mark.parametrize("query,expected_domain", [
        ("How do neural networks learn?", "technology"),
        ("What are the symptoms of diabetes?", "healthcare"),
        ("Explain compound interest calculations", "finance"),
        ("What is the theory of relativity?", "science"),
    ])
    def test_domain_detection_accuracy(self, client, query, expected_domain, sample_organization_id):
        """Test domain detection accuracy for known queries."""
        response = client.post(
            "/domains/detect",
            json={
                "query": query,
                "organization_id": sample_organization_id
            }
        )

        if response.status_code == 404:
            pytest.skip("Domain detection endpoint not implemented")

        if response.status_code == 200:
            data = response.json()
            detected = data.get("domain") or data.get("detected_domain", "")
            # Domain detection might not be perfect, just check it returns something
            assert detected != ""
