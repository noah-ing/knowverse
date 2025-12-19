import logging
import os
import json
import numpy as np
import psycopg2
from collections import OrderedDict
from typing import List, Dict, Optional, Tuple, Union
from functools import lru_cache
from sentence_transformers import SentenceTransformer, losses, InputExample
from torch.utils.data import DataLoader
from config.settings import (
    EMBEDDING_MODEL_NAME, EMBEDDING_MODELS, DEFAULT_DOMAIN,
    DOMAIN_MODEL_CACHE_SIZE, ENABLE_DOMAIN_DETECTION,
    DOMAIN_DETECTION_THRESHOLD, ENABLE_MODEL_FINETUNING,
    MODEL_TRAINING_BATCH_SIZE, MODEL_TRAINING_EPOCHS, MODEL_SAVE_PATH,
    DB_CONNECTION_STRING
)

# OpenAI embedding support
try:
    from openai import OpenAI
    OPENAI_AVAILABLE = True
except ImportError:
    OPENAI_AVAILABLE = False

OPENAI_EMBEDDING_MODELS = {
    'ada002': {'name': 'text-embedding-ada-002', 'dimension': 1536},
    'text-embedding-3-small': {'name': 'text-embedding-3-small', 'dimension': 1536},
    'text-embedding-3-large': {'name': 'text-embedding-3-large', 'dimension': 3072},
}

logger = logging.getLogger(__name__)

# Ensure model save path exists
if not os.path.exists(MODEL_SAVE_PATH):
    os.makedirs(MODEL_SAVE_PATH, exist_ok=True)

class ModelRegistry:
    """Registry to manage and cache embedding models"""
    
    def __init__(self, cache_size=DOMAIN_MODEL_CACHE_SIZE):
        self.models = OrderedDict()
        self.cache_size = cache_size
        self.default_model_specs = EMBEDDING_MODELS
        logger.info(f"Initialized ModelRegistry with cache size {cache_size}")
    
    def get_model(self, model_name: str = 'base', domain: str = DEFAULT_DOMAIN, organization_id: Optional[int] = None) -> SentenceTransformer:
        """
        Get a model from the registry or load it if not cached.
        
        Args:
            model_name: Base model name (mini, small, base, large, xl)
            domain: Domain name for domain-specific models
            organization_id: Organization ID for tenant-specific models
            
        Returns:
            SentenceTransformer model instance
        """
        # Create a unique key for the model
        if domain == DEFAULT_DOMAIN:
            # For general domain, we just use the model name
            key = model_name
        else:
            # For domain-specific models, include domain and org id
            key = f"{domain}/{model_name}" 
            if organization_id:
                key = f"{key}/{organization_id}"
        
        # Return cached model if available
        if key in self.models:
            # Move to end to mark as recently used
            self.models.move_to_end(key)
            logger.debug(f"Using cached model: {key}")
            return self.models[key]
        
        # Load model (either base model or domain-specific fine-tuned model)
        try:
            # Check if we have a fine-tuned model
            if domain != DEFAULT_DOMAIN:
                model_path = self._get_domain_model_path(domain, model_name, organization_id)
                if os.path.exists(model_path):
                    logger.info(f"Loading domain-specific model from {model_path}")
                    model = SentenceTransformer(model_path)
                    logger.info(f"Domain model loaded successfully with dimension: {model.get_sentence_embedding_dimension()}")
                else:
                    # Fall back to base model if domain model doesn't exist
                    logger.info(f"Domain model not found, falling back to base model: {model_name}")
                    base_model_name = self.default_model_specs.get(model_name, EMBEDDING_MODEL_NAME)
                    model = SentenceTransformer(base_model_name)
            else:
                # Load base model
                base_model_name = self.default_model_specs.get(model_name, EMBEDDING_MODEL_NAME)
                logger.info(f"Loading base embedding model: {base_model_name}")
                model = SentenceTransformer(base_model_name)
                logger.info(f"Base model loaded successfully with dimension: {model.get_sentence_embedding_dimension()}")
            
            # Add to cache
            self.models[key] = model
            
            # Remove oldest item if cache is full
            if len(self.models) > self.cache_size:
                self.models.popitem(last=False)
                
            return model
            
        except Exception as e:
            logger.error(f"Error loading embedding model: {str(e)}")
            raise RuntimeError(f"Failed to load embedding model: {str(e)}")
    
    def _get_domain_model_path(self, domain: str, model_name: str, organization_id: Optional[int] = None) -> str:
        """Get the path to a domain-specific model"""
        if organization_id:
            return os.path.join(MODEL_SAVE_PATH, f"{domain}_{model_name}_{organization_id}")
        return os.path.join(MODEL_SAVE_PATH, f"{domain}_{model_name}")
    
    def get_domain_model_info(self, domain: str, organization_id: Optional[int] = None) -> Dict:
        """Get information about available domain models"""
        models_info = {}
        
        # Check database for domain model information
        if organization_id:
            try:
                with psycopg2.connect(DB_CONNECTION_STRING) as conn:
                    with conn.cursor() as cur:
                        cur.execute("""
                            SELECT name, base_model, dimension, version, configuration, performance_metrics
                            FROM domain_embedding_models
                            WHERE domain = %s AND organization_id = %s AND active = true
                        """, (domain, organization_id))
                        rows = cur.fetchall()
                        for row in rows:
                            name, base_model, dimension, version, config, metrics = row
                            models_info[name] = {
                                'base_model': base_model,
                                'dimension': dimension,
                                'version': version,
                                'configuration': config,
                                'performance_metrics': metrics,
                                'path': self._get_domain_model_path(domain, base_model, organization_id)
                            }
            except Exception as e:
                logger.error(f"Error fetching domain model info: {str(e)}")
        
        return models_info
    
    def fine_tune_model(self, 
                        base_model_name: str,
                        domain: str, 
                        training_data: List[Tuple[str, str, float]],  # [(text1, text2, similarity), ...]
                        organization_id: Optional[int] = None) -> Dict:
        """
        Fine-tune a model for a specific domain
        
        Args:
            base_model_name: Base model name to fine-tune
            domain: Domain name
            training_data: List of tuples (text1, text2, similarity_score)
            organization_id: Optional organization ID
            
        Returns:
            Dict with fine-tuning metrics
        """
        if not ENABLE_MODEL_FINETUNING:
            logger.warning("Model fine-tuning is disabled in configuration")
            return {'status': 'error', 'message': 'Model fine-tuning is disabled'}
        
        try:
            # Load base model
            base_model = self.get_model(base_model_name, DEFAULT_DOMAIN)
            
            # Prepare training examples
            train_examples = [
                InputExample(texts=[t1, t2], label=score)
                for t1, t2, score in training_data
            ]
            
            # Create data loader
            train_dataloader = DataLoader(
                train_examples, 
                shuffle=True, 
                batch_size=MODEL_TRAINING_BATCH_SIZE
            )
            
            # Define loss
            train_loss = losses.CosineSimilarityLoss(base_model)
            
            # Train model
            logger.info(f"Fine-tuning model for domain: {domain}")
            base_model.fit(
                train_objectives=[(train_dataloader, train_loss)],
                epochs=MODEL_TRAINING_EPOCHS,
                show_progress_bar=True
            )
            
            # Save model
            model_path = self._get_domain_model_path(domain, base_model_name, organization_id)
            base_model.save(model_path)
            logger.info(f"Domain model saved to {model_path}")
            
            # Clear existing model from cache to reload fine-tuned version
            key = f"{domain}/{base_model_name}"
            if organization_id:
                key = f"{key}/{organization_id}"
            if key in self.models:
                del self.models[key]
            
            # Return metrics
            metrics = {
                'status': 'success',
                'training_examples': len(training_data),
                'epochs': MODEL_TRAINING_EPOCHS,
                'model_path': model_path
            }
            
            return metrics
            
        except Exception as e:
            logger.error(f"Error fine-tuning model: {str(e)}")
            return {'status': 'error', 'message': str(e)}

# Initialize global model registry
model_registry = ModelRegistry(cache_size=DOMAIN_MODEL_CACHE_SIZE)

class DomainDetector:
    """
    Detect the appropriate domain for a query
    """
    
    def __init__(self, organization_id: Optional[int] = None):
        self.organization_id = organization_id
        self.domains_cache = {}
        self.threshold = DOMAIN_DETECTION_THRESHOLD
    
    def _get_available_domains(self) -> List[str]:
        """Get list of available domains for the organization"""
        if self.organization_id in self.domains_cache:
            return self.domains_cache[self.organization_id]
        
        domains = [DEFAULT_DOMAIN]  # Always include the default domain
        
        # Query database for available domains
        if self.organization_id:
            try:
                with psycopg2.connect(DB_CONNECTION_STRING) as conn:
                    with conn.cursor() as cur:
                        cur.execute("""
                            SELECT DISTINCT domain 
                            FROM domain_embedding_models 
                            WHERE organization_id = %s AND active = true
                        """, (self.organization_id,))
                        rows = cur.fetchall()
                        for row in rows:
                            if row[0] != DEFAULT_DOMAIN and row[0] not in domains:
                                domains.append(row[0])
            except Exception as e:
                logger.error(f"Error fetching available domains: {str(e)}")
        
        # Cache the result
        self.domains_cache[self.organization_id] = domains
        return domains
    
    def _calculate_domain_similarity(self, query: str, domain: str) -> float:
        """
        Calculate similarity between query and domain
        For now, we use a simple keyword-based approach
        In a full implementation, this would use a more sophisticated model
        """
        # Get domain info - in full implementation, we'd extract domain keywords
        # from the domain models and documents
        try:
            with psycopg2.connect(DB_CONNECTION_STRING) as conn:
                with conn.cursor() as cur:
                    cur.execute("""
                        SELECT configuration
                        FROM domain_embedding_models
                        WHERE domain = %s AND organization_id = %s AND active = true
                        LIMIT 1
                    """, (domain, self.organization_id))
                    row = cur.fetchone()
                    if row and row[0] and 'keywords' in row[0]:
                        keywords = row[0]['keywords']
                        
                        # Simple keyword matching
                        query_lower = query.lower()
                        matches = sum(1 for keyword in keywords if keyword.lower() in query_lower)
                        return min(matches / max(1, len(keywords) * 0.3), 1.0)
        except Exception as e:
            logger.error(f"Error in domain similarity calculation: {str(e)}")
        
        return 0.1  # Low default similarity
    
    def detect_domain(self, query: str) -> Tuple[str, float]:
        """
        Detect the most appropriate domain for a query
        
        Args:
            query: The search query
            
        Returns:
            Tuple of (domain_name, confidence_score)
        """
        if not ENABLE_DOMAIN_DETECTION:
            return DEFAULT_DOMAIN, 1.0
        
        if not query or not self.organization_id:
            return DEFAULT_DOMAIN, 1.0
        
        domains = self._get_available_domains()
        if len(domains) <= 1:
            return DEFAULT_DOMAIN, 1.0
        
        # Calculate similarity for each domain
        domain_scores = {}
        for domain in domains:
            if domain == DEFAULT_DOMAIN:
                domain_scores[domain] = 0.5  # Default gets a medium score
            else:
                domain_scores[domain] = self._calculate_domain_similarity(query, domain)
        
        # Get domain with highest score
        best_domain = max(domain_scores.items(), key=lambda x: x[1])
        domain_name, confidence = best_domain
        
        # Return default domain if no strong match
        if confidence < self.threshold and domain_name != DEFAULT_DOMAIN:
            logger.debug(f"Confidence {confidence} below threshold {self.threshold}, falling back to default domain")
            return DEFAULT_DOMAIN, 1.0 - confidence
        
        logger.debug(f"Detected domain '{domain_name}' with confidence {confidence}")
        return domain_name, confidence

def get_embedding_model(model_name: str = 'base', domain: str = DEFAULT_DOMAIN, organization_id: Optional[int] = None) -> SentenceTransformer:
    """
    Get an embedding model instance (from registry).
    Uses sentence-transformers library with the configured model.
    
    Args:
        model_name: Base model name (mini, small, base, large, xl)
        domain: Domain name for domain-specific models
        organization_id: Organization ID for tenant-specific models
    """
    return model_registry.get_model(model_name, domain, organization_id)

def get_embedding_dimension(model_name: str = 'base') -> int:
    """
    Get the dimension of the embedding vectors for a model
    
    Args:
        model_name: Base model name
    """
    return get_embedding_model(model_name).get_sentence_embedding_dimension()

def generate_embeddings(texts: List[str], model_name: str = 'base', domain: str = DEFAULT_DOMAIN, organization_id: Optional[int] = None) -> np.ndarray:
    """
    Generate embeddings for a list of texts.
    
    Args:
        texts: List of strings to generate embeddings for
        model_name: Base model name (mini, small, base, large, xl)
        domain: Domain name for domain-specific models
        organization_id: Organization ID for tenant-specific models
        
    Returns:
        List of embedding vectors
    """
    if not texts:
        return []
    
    model = get_embedding_model(model_name, domain, organization_id)
    embeddings = model.encode(texts)
    return embeddings

def detect_query_domain(query: str, organization_id: Optional[int] = None) -> Tuple[str, float]:
    """
    Detect the most appropriate domain for a query
    
    Args:
        query: The search query
        organization_id: Organization ID for tenant-specific domain detection
        
    Returns:
        Tuple of (domain_name, confidence_score)
    """
    detector = DomainDetector(organization_id)
    return detector.detect_domain(query)

def fine_tune_domain_model(
    base_model_name: str,
    domain: str,
    training_data: List[Tuple[str, str, float]],
    organization_id: Optional[int] = None
) -> Dict:
    """
    Fine-tune a model for a specific domain
    
    Args:
        base_model_name: Base model name to fine-tune
        domain: Domain name
        training_data: List of tuples (text1, text2, similarity_score)
        organization_id: Optional organization ID
        
    Returns:
        Dict with fine-tuning metrics
    """
    return model_registry.fine_tune_model(base_model_name, domain, training_data, organization_id)

def get_embedding(text: str, model_name: str = 'base', domain: str = DEFAULT_DOMAIN, organization_id: Optional[int] = None) -> np.ndarray:
    """
    Generate embedding for a single text string.
    Compatibility wrapper for single text embedding generation.
    
    Args:
        text: Text string to generate embedding for
        model_name: Base model name (mini, small, base, large, xl)
        domain: Domain name for domain-specific models
        organization_id: Organization ID for tenant-specific models
        
    Returns:
        Embedding vector as numpy array
    """
    if not text:
        logger.warning("Empty text provided to get_embedding")
        # Return zero vector with proper dimension
        model = get_embedding_model(model_name, domain, organization_id)
        dim = model.get_sentence_embedding_dimension()
        return np.zeros(dim)
    
    model = get_embedding_model(model_name, domain, organization_id)
    embedding = model.encode([text])[0]  # encode returns array, get first element
    return embedding

def get_available_domains(organization_id: Optional[int] = None) -> List[str]:
    """
    Get list of available domains for an organization

    Args:
        organization_id: Organization ID

    Returns:
        List of domain names
    """
    detector = DomainDetector(organization_id)
    return detector._get_available_domains()


# OpenAI Embedding Functions
_openai_client = None

def get_openai_client():
    """Get or create OpenAI client"""
    global _openai_client
    if _openai_client is None:
        if not OPENAI_AVAILABLE:
            raise RuntimeError("OpenAI package not installed")
        api_key = os.getenv('OPENAI_API_KEY')
        if not api_key:
            raise RuntimeError("OPENAI_API_KEY not set")
        _openai_client = OpenAI(api_key=api_key)
    return _openai_client


def get_openai_embedding(text: str, model: str = 'ada002') -> np.ndarray:
    """
    Generate embedding using OpenAI API.

    Args:
        text: Text to embed
        model: Model key (ada002, text-embedding-3-small, text-embedding-3-large)

    Returns:
        Embedding vector as numpy array
    """
    if not text:
        model_info = OPENAI_EMBEDDING_MODELS.get(model, OPENAI_EMBEDDING_MODELS['ada002'])
        return np.zeros(model_info['dimension'])

    model_info = OPENAI_EMBEDDING_MODELS.get(model, OPENAI_EMBEDDING_MODELS['ada002'])
    model_name = model_info['name']

    try:
        client = get_openai_client()
        response = client.embeddings.create(
            input=text,
            model=model_name
        )
        embedding = response.data[0].embedding
        return np.array(embedding)
    except Exception as e:
        logger.error(f"OpenAI embedding error: {e}")
        raise


def get_openai_embeddings(texts: List[str], model: str = 'ada002') -> np.ndarray:
    """
    Generate embeddings for multiple texts using OpenAI API.

    Args:
        texts: List of texts to embed
        model: Model key

    Returns:
        Array of embedding vectors
    """
    if not texts:
        return np.array([])

    model_info = OPENAI_EMBEDDING_MODELS.get(model, OPENAI_EMBEDDING_MODELS['ada002'])
    model_name = model_info['name']

    try:
        client = get_openai_client()
        response = client.embeddings.create(
            input=texts,
            model=model_name
        )
        embeddings = [item.embedding for item in response.data]
        return np.array(embeddings)
    except Exception as e:
        logger.error(f"OpenAI embeddings error: {e}")
        raise
