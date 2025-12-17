"""
Pytest configuration and fixtures for Haystack service tests.
"""
import pytest
import sys
import os
from unittest.mock import MagicMock, patch, AsyncMock

# Add app to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

# Set test environment variables before any imports
os.environ.setdefault('REDIS_URL', 'redis://localhost:6379/0')
os.environ.setdefault('QDRANT_URL', 'http://localhost:6333')
os.environ.setdefault('OPENAI_API_KEY', 'test-key')
os.environ.setdefault('ENVIRONMENT', 'test')


def _create_mock_modules():
    """Create mock modules for heavy dependencies."""
    # Mock document store
    mock_document_store = MagicMock()
    mock_document_store.get_document_store.return_value = MagicMock()

    # Mock embeddings module
    mock_embeddings = MagicMock()
    mock_embeddings.get_embedding_model.return_value = MagicMock()
    mock_embeddings.generate_embeddings.return_value = [0.1] * 768
    mock_embeddings.detect_query_domain.return_value = {
        "domain": "general",
        "confidence": 0.9,
        "alternatives": {}
    }
    mock_embeddings.get_available_domains.return_value = [
        {"domain": "general", "description": "General domain", "model_count": 1}
    ]
    mock_embeddings.fine_tune_domain_model.return_value = MagicMock()
    mock_embeddings.model_registry = MagicMock()

    # Mock search module
    mock_search = MagicMock()
    mock_search.get_retriever.return_value = MagicMock()
    mock_search_pipeline = MagicMock()
    mock_search_pipeline.run.return_value = {"documents": []}
    mock_search.get_search_pipeline.return_value = mock_search_pipeline
    mock_search.get_qa_pipeline.return_value = MagicMock()
    mock_hybrid_searcher = MagicMock()
    mock_hybrid_searcher.search.return_value = {"documents": []}
    mock_search.get_hybrid_searcher.return_value = mock_hybrid_searcher

    # Mock visualization
    mock_visualization = MagicMock()
    mock_dimension_reducer = MagicMock()
    mock_dimension_reducer.reduce.return_value = MagicMock(tolist=lambda: [[0.1, 0.2]], shape=(1, 2))
    mock_visualization.DimensionReduction.return_value = mock_dimension_reducer
    mock_cluster_analyzer = MagicMock()
    mock_cluster_analyzer.cluster.return_value = {"clusters": [], "num_clusters": 0}
    mock_visualization.ClusterAnalysis.return_value = mock_cluster_analyzer

    # Mock query parser
    mock_query_parser = MagicMock()
    mock_parser_instance = MagicMock()
    mock_parser_instance.parse.return_value = {
        "vector_query": "test",
        "keyword_query": "test",
        "exact_phrases": [],
        "required_terms": [],
        "excluded_terms": [],
        "boosted_terms": {},
        "keywords": ["test"],
        "complexity": "simple",
        "weights": {"vector": 0.5, "keyword": 0.5}
    }
    mock_query_parser.QueryParser.return_value = mock_parser_instance

    # Mock retrieval
    mock_retrieval = MagicMock()
    mock_retrieval.retrieve_and_rank.return_value = []
    mock_retrieval.get_context_retriever.return_value = MagicMock()

    # Mock generation with LLM registry
    mock_generation = MagicMock()
    mock_llm = MagicMock()
    mock_llm.generate.return_value = "Test answer"
    mock_llm.stream = AsyncMock(return_value=iter(["Test", " ", "answer"]))
    mock_llm_registry = MagicMock()
    mock_llm_registry.get_llm.return_value = mock_llm
    mock_llm_registry.get_available_providers.return_value = ["openai", "anthropic"]
    mock_llm_registry.get_default_provider.return_value = "openai"
    mock_generation.llm_registry = mock_llm_registry

    # Mock health router
    mock_health = MagicMock()
    mock_health.router = MagicMock()

    # Mock extractors
    mock_extractors = MagicMock()
    mock_extractors.extract_text_from_pdf.return_value = {
        "success": True,
        "content": "Test PDF content",
        "total_pages": 1,
        "total_tables": 0,
        "metadata": {},
        "extraction_method": "test",
        "total_chars": 16,
        "total_words": 3,
        "errors": []
    }
    mock_extractors.extract_text_from_docx.return_value = {
        "success": True,
        "content": "Test DOCX content",
        "total_paragraphs": 1,
        "total_tables": 0,
        "metadata": {},
        "total_chars": 17,
        "total_words": 3,
        "errors": []
    }
    mock_extractors.extract_text_from_excel.return_value = {
        "success": True,
        "content": "Test Excel content",
        "total_sheets": 1,
        "total_rows": 1,
        "total_tables": 1,
        "metadata": {"sheet_names": ["Sheet1"]},
        "extraction_method": "test",
        "errors": []
    }

    # Mock config settings
    mock_settings = MagicMock()
    mock_settings.DEBUG = False
    mock_settings.ENVIRONMENT = "test"
    mock_settings.DEFAULT_DOMAIN = "general"
    mock_settings.EMBEDDING_MODELS = {}
    mock_settings.API_HOST = "0.0.0.0"
    mock_settings.API_PORT = 8000

    return {
        'app.document_store': mock_document_store,
        'app.embeddings': mock_embeddings,
        'app.search': mock_search,
        'app.visualization': mock_visualization,
        'app.query_parser': mock_query_parser,
        'app.retrieval': mock_retrieval,
        'app.generation': mock_generation,
        'app.health': mock_health,
        'app.extractors': mock_extractors,
        'config.settings': mock_settings,
    }


@pytest.fixture
def client():
    """Create a test client for the FastAPI application."""
    from fastapi.testclient import TestClient

    # Create mocks
    mocks = _create_mock_modules()

    # Patch all modules before importing app
    with patch.dict(sys.modules, mocks):
        # Also patch individual imports
        with patch('app.document_store.get_document_store', mocks['app.document_store'].get_document_store), \
             patch('app.embeddings.get_embedding_model', mocks['app.embeddings'].get_embedding_model), \
             patch('app.embeddings.generate_embeddings', mocks['app.embeddings'].generate_embeddings), \
             patch('app.embeddings.detect_query_domain', mocks['app.embeddings'].detect_query_domain), \
             patch('app.embeddings.get_available_domains', mocks['app.embeddings'].get_available_domains), \
             patch('app.search.get_search_pipeline', mocks['app.search'].get_search_pipeline), \
             patch('app.search.get_hybrid_searcher', mocks['app.search'].get_hybrid_searcher):

            # Force reload the app module with mocks
            if 'app.main' in sys.modules:
                del sys.modules['app.main']

            from app.main import app
            return TestClient(app, raise_server_exceptions=False)


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
