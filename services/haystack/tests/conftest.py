"""
Pytest configuration and fixtures for Haystack service tests.
"""
import pytest
from fastapi.testclient import TestClient
import sys
import os

# Add app to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from app.main import app


@pytest.fixture
def client():
    """Create a test client for the FastAPI application."""
    return TestClient(app)


@pytest.fixture
def sample_text():
    """Sample text for embedding generation."""
    return "Machine learning is a subset of artificial intelligence that enables systems to learn from data."


@pytest.fixture
def sample_texts():
    """Sample texts for batch operations."""
    return [
        "Machine learning algorithms improve through experience.",
        "Neural networks are inspired by biological neurons.",
        "Deep learning uses multiple layers for feature extraction."
    ]


@pytest.fixture
def sample_query():
    """Sample search query."""
    return "What are the applications of machine learning?"


@pytest.fixture
def sample_organization_id():
    """Sample organization ID."""
    return 1


@pytest.fixture
def sample_pdf_content():
    """Sample PDF-like content (base64 placeholder)."""
    # In real tests, this would be actual PDF bytes
    return b"%PDF-1.4 fake content"


@pytest.fixture
def sample_embedding():
    """Sample 768-dimensional embedding."""
    import random
    return [random.random() for _ in range(768)]


@pytest.fixture
def sample_embeddings():
    """Sample batch of embeddings."""
    import random
    return [
        [random.random() for _ in range(768)]
        for _ in range(5)
    ]
