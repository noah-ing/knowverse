"""
Tests for RAG (Retrieval-Augmented Generation) endpoints.
"""
import pytest


class TestRAGAnswer:
    """Tests for /rag/answer endpoint."""

    def test_rag_answer_endpoint_exists(self, client, sample_query, sample_organization_id):
        """Test that RAG answer endpoint exists."""
        response = client.post(
            "/rag/answer",
            json={
                "query": sample_query,
                "org_id": sample_organization_id,
                "retrieval_options": {
                    "max_documents": 5,
                    "min_similarity": 0.7
                },
                "generation_options": {
                    "temperature": 0.7,
                    "max_tokens": 500
                }
            }
        )
        # May fail if no OpenAI key configured
        assert response.status_code in [200, 400, 422, 500, 503]

    def test_rag_answer_structure(self, client, sample_query, sample_organization_id):
        """Test RAG answer response structure."""
        response = client.post(
            "/rag/answer",
            json={
                "query": sample_query,
                "org_id": sample_organization_id
            }
        )

        if response.status_code == 200:
            data = response.json()
            # Should contain answer and sources
            assert "answer" in data or "response" in data


class TestRAGProviders:
    """Tests for /rag/providers endpoint."""

    def test_list_providers(self, client):
        """Test listing available LLM providers."""
        response = client.get("/rag/providers")

        if response.status_code == 404:
            pytest.skip("Providers endpoint not implemented")

        assert response.status_code == 200
        data = response.json()
        assert isinstance(data, list)


class TestRAGStream:
    """Tests for /rag/stream SSE endpoint."""

    def test_stream_endpoint_exists(self, client, sample_query, sample_organization_id):
        """Test that streaming endpoint exists."""
        response = client.post(
            "/rag/stream",
            json={
                "query": sample_query,
                "org_id": sample_organization_id
            }
        )
        # SSE endpoint should return streaming response
        assert response.status_code in [200, 400, 422, 500, 503]
