"""
Tests for embedding generation endpoints.
"""
import pytest


class TestEmbeddingGeneration:
    """Tests for /embeddings/generate endpoint."""

    def test_generate_embedding_success(self, client, sample_text):
        """Test successful embedding generation."""
        response = client.post(
            "/embeddings/generate",
            json={"text": sample_text}
        )
        assert response.status_code == 200

        data = response.json()
        assert "embedding" in data
        assert isinstance(data["embedding"], list)
        assert len(data["embedding"]) > 0
        assert "dimension" in data

    def test_generate_embedding_with_model(self, client, sample_text):
        """Test embedding generation with specific model."""
        response = client.post(
            "/embeddings/generate",
            json={
                "text": sample_text,
                "model_name": "all-MiniLM-L6-v2"
            }
        )
        assert response.status_code == 200

        data = response.json()
        # MiniLM produces 384-dimensional embeddings
        assert data["dimension"] == 384

    def test_generate_embedding_empty_text(self, client):
        """Test embedding generation with empty text."""
        response = client.post(
            "/embeddings/generate",
            json={"text": ""}
        )
        # Should either return error or handle gracefully
        assert response.status_code in [200, 400, 422]

    def test_generate_embedding_long_text(self, client):
        """Test embedding generation with long text."""
        long_text = "Machine learning " * 1000  # Very long text
        response = client.post(
            "/embeddings/generate",
            json={"text": long_text}
        )
        assert response.status_code == 200

        data = response.json()
        assert "embedding" in data

    def test_embedding_normalization(self, client, sample_text):
        """Test that embeddings are normalized (L2 norm ~ 1)."""
        response = client.post(
            "/embeddings/generate",
            json={"text": sample_text}
        )
        assert response.status_code == 200

        data = response.json()
        embedding = data["embedding"]

        # Calculate L2 norm
        import math
        norm = math.sqrt(sum(x**2 for x in embedding))

        # Should be close to 1.0 for normalized embeddings
        assert 0.99 <= norm <= 1.01


class TestBatchEmbeddings:
    """Tests for batch embedding generation."""

    def test_batch_embeddings(self, client, sample_texts):
        """Test batch embedding generation."""
        response = client.post(
            "/embeddings/batch",
            json={"texts": sample_texts}
        )

        if response.status_code == 404:
            pytest.skip("Batch endpoint not implemented")

        assert response.status_code == 200
        data = response.json()
        assert "embeddings" in data
        assert len(data["embeddings"]) == len(sample_texts)
