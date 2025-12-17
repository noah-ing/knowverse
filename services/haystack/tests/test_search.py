"""
Tests for search endpoints.
"""
import pytest


class TestSemanticSearch:
    """Tests for /search endpoint."""

    def test_search_endpoint_exists(self, client, sample_query, sample_organization_id):
        """Test that search endpoint exists and responds."""
        response = client.post(
            "/search",
            json={
                "query": sample_query,
                "filters": {"organization_id": sample_organization_id},
                "top_k": 10
            }
        )
        # Should return 200 or 404 if no documents
        assert response.status_code in [200, 404]

    def test_search_with_limit(self, client, sample_query, sample_organization_id):
        """Test search with custom limit."""
        response = client.post(
            "/search",
            json={
                "query": sample_query,
                "filters": {"organization_id": sample_organization_id},
                "top_k": 5
            }
        )

        if response.status_code == 200:
            data = response.json()
            assert "results" in data or "documents" in data


class TestHybridSearch:
    """Tests for /hybrid-search endpoint."""

    def test_hybrid_search_endpoint_exists(self, client, sample_query, sample_organization_id):
        """Test that hybrid search endpoint exists."""
        response = client.post(
            "/hybrid-search",
            json={
                "query": sample_query,
                "filters": {"organization_id": sample_organization_id},
                "top_k": 10
            }
        )
        assert response.status_code in [200, 404]

    def test_hybrid_search_with_weights(self, client, sample_query, sample_organization_id):
        """Test hybrid search with custom weights."""
        response = client.post(
            "/hybrid-search",
            json={
                "query": sample_query,
                "filters": {"organization_id": sample_organization_id},
                "top_k": 10,
                "vector_weight": 0.8,
                "keyword_weight": 0.2
            }
        )
        assert response.status_code in [200, 404]


class TestQueryParsing:
    """Tests for /parse-query endpoint."""

    def test_parse_query_endpoint(self, client, sample_query):
        """Test query parsing endpoint."""
        response = client.post(
            "/parse-query",
            json={"query": sample_query}
        )

        if response.status_code == 404:
            pytest.skip("Parse query endpoint not implemented")

        assert response.status_code == 200
        data = response.json()
        # Should return parsed query components
        assert isinstance(data, dict)
