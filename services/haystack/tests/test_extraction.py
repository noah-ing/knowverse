"""
Tests for document extraction endpoints.
"""
import pytest
import base64


class TestPDFExtraction:
    """Tests for /extract/pdf endpoint."""

    def test_pdf_extraction_endpoint_exists(self, client):
        """Test that PDF extraction endpoint exists."""
        # Create a minimal test file
        response = client.post(
            "/extract/pdf",
            files={"file": ("test.pdf", b"fake pdf content", "application/pdf")}
        )
        # Should handle invalid PDF gracefully
        assert response.status_code in [200, 400, 422]

    def test_pdf_extraction_requires_file(self, client):
        """Test that PDF extraction requires a file."""
        response = client.post("/extract/pdf")
        assert response.status_code == 422


class TestExcelExtraction:
    """Tests for /extract/excel endpoint."""

    def test_excel_extraction_endpoint_exists(self, client):
        """Test that Excel extraction endpoint exists."""
        response = client.post(
            "/extract/excel",
            files={"file": ("test.xlsx", b"fake excel content", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")}
        )
        assert response.status_code in [200, 400, 422]


class TestDocxExtraction:
    """Tests for /extract/docx endpoint."""

    def test_docx_extraction_endpoint_exists(self, client):
        """Test that DOCX extraction endpoint exists."""
        response = client.post(
            "/extract/docx",
            files={"file": ("test.docx", b"fake docx content", "application/vnd.openxmlformats-officedocument.wordprocessingml.document")}
        )
        assert response.status_code in [200, 400, 422]


class TestAutoExtraction:
    """Tests for /extract/auto endpoint."""

    def test_auto_extraction_endpoint_exists(self, client):
        """Test that auto extraction endpoint exists."""
        response = client.post(
            "/extract/auto",
            files={"file": ("test.txt", b"This is plain text content", "text/plain")}
        )

        if response.status_code == 404:
            pytest.skip("Auto extraction endpoint not implemented")

        assert response.status_code in [200, 400, 422]


class TestChunking:
    """Tests for /chunk endpoint."""

    def test_chunk_text(self, client, sample_text):
        """Test text chunking."""
        response = client.post(
            "/chunk",
            json={
                "content": sample_text * 10,  # Make it longer
                "chunk_size": 100,
                "chunk_overlap": 20
            }
        )

        if response.status_code == 404:
            pytest.skip("Chunk endpoint not implemented")

        assert response.status_code == 200
        data = response.json()
        assert "chunks" in data
        assert isinstance(data["chunks"], list)

    def test_chunk_with_strategy(self, client, sample_text):
        """Test chunking with different strategies."""
        for strategy in ["fixed", "sentence", "semantic"]:
            response = client.post(
                "/chunk",
                json={
                    "content": sample_text * 10,
                    "chunk_size": 100,
                    "chunking_strategy": strategy
                }
            )

            if response.status_code == 404:
                pytest.skip("Chunk endpoint not implemented")

            assert response.status_code == 200
