import os
from pathlib import Path
from dotenv import load_dotenv

# Load environment variables from .env file
env_path = Path(__file__).parent.parent / '.env'
if env_path.exists():
    load_dotenv(dotenv_path=env_path)

# API settings
API_HOST = os.getenv('API_HOST', '0.0.0.0')
API_PORT = int(os.getenv('API_PORT', '8000'))
DEBUG = os.getenv('DEBUG', 'False').lower() == 'true'
ENVIRONMENT = os.getenv('ENVIRONMENT', 'development')

# Database settings for PostgreSQL with pgvector
DB_HOST = os.getenv('DB_HOST', 'localhost')
DB_PORT = int(os.getenv('DB_PORT', '5432'))
DB_NAME = os.getenv('DB_NAME', 'knowverse_development')
DB_USER = os.getenv('DB_USER', 'postgres')
DB_PASSWORD = os.getenv('DB_PASSWORD', 'postgres')
DB_SCHEMA = os.getenv('DB_SCHEMA', 'public')

# Database connection string
DB_CONNECTION_STRING = f"postgresql://{DB_USER}:{DB_PASSWORD}@{DB_HOST}:{DB_PORT}/{DB_NAME}"

# JWT authentication settings
SECRET_KEY = os.getenv('SECRET_KEY', 'your-secret-key-for-jwt-tokens')
ALGORITHM = os.getenv('ALGORITHM', 'HS256')
ACCESS_TOKEN_EXPIRE_MINUTES = int(os.getenv('ACCESS_TOKEN_EXPIRE_MINUTES', '60'))

# Haystack settings
EMBEDDING_MODEL_NAME = os.getenv('EMBEDDING_MODEL_NAME', 'sentence-transformers/multi-qa-mpnet-base-dot-v1')
RETRIEVER_TOP_K = int(os.getenv('RETRIEVER_TOP_K', '10'))
MAX_DOCUMENT_SIZE = int(os.getenv('MAX_DOCUMENT_SIZE', '100000'))  # Maximum document size in characters
DOCUMENT_STORE_TYPE = os.getenv('DOCUMENT_STORE_TYPE', 'pgvector')  # 'pgvector' or 'in_memory'

# Search performance settings
MAX_SEARCH_TIME_MS = int(os.getenv('MAX_SEARCH_TIME_MS', '100'))  # Maximum search time in milliseconds for early termination

# Embedding model configurations
EMBEDDING_MODELS = {
    'mini': 'sentence-transformers/all-MiniLM-L6-v2',           # 384 dimensions
    'small': 'sentence-transformers/all-mpnet-base-v2',         # 768 dimensions
    'base': 'sentence-transformers/multi-qa-mpnet-base-dot-v1', # 1024 dimensions (default)
    'large': 'sentence-transformers/all-roberta-large-v1',      # 1536 dimensions
    'xl': 'sentence-transformers/nli-mpnet-base-v2'             # 2048 dimensions (approximated)
}

# Domain-specific embedding settings
DEFAULT_DOMAIN = 'general'
ENABLE_DOMAIN_DETECTION = os.getenv('ENABLE_DOMAIN_DETECTION', 'true').lower() == 'true'
DOMAIN_DETECTION_THRESHOLD = float(os.getenv('DOMAIN_DETECTION_THRESHOLD', '0.7'))
DOMAIN_MODEL_CACHE_SIZE = int(os.getenv('DOMAIN_MODEL_CACHE_SIZE', '5'))

# Model fine-tuning settings
ENABLE_MODEL_FINETUNING = os.getenv('ENABLE_MODEL_FINETUNING', 'false').lower() == 'true'
MODEL_TRAINING_BATCH_SIZE = int(os.getenv('MODEL_TRAINING_BATCH_SIZE', '32'))
MODEL_TRAINING_EPOCHS = int(os.getenv('MODEL_TRAINING_EPOCHS', '3'))
MODEL_SAVE_PATH = os.getenv('MODEL_SAVE_PATH', 'models/domain_models')

# LLM Provider Settings
OPENAI_API_KEY = os.getenv('OPENAI_API_KEY', '')
ANTHROPIC_API_KEY = os.getenv('ANTHROPIC_API_KEY', '')
ENABLE_LOCAL_LLM = os.getenv('ENABLE_LOCAL_LLM', 'false').lower() == 'true'
LOCAL_LLM_PATH = os.getenv('LOCAL_LLM_PATH', 'meta-llama/Llama-2-7b-chat-hf')

# LLM Configuration
DEFAULT_LLM_PROVIDER = os.getenv('DEFAULT_LLM_PROVIDER', 'openai')
DEFAULT_OPENAI_MODEL = os.getenv('DEFAULT_OPENAI_MODEL', 'gpt-4')
DEFAULT_ANTHROPIC_MODEL = os.getenv('DEFAULT_ANTHROPIC_MODEL', 'claude-3-haiku-20240307')
MAX_RAG_CONTEXT_DOCUMENTS = int(os.getenv('MAX_RAG_CONTEXT_DOCUMENTS', '5'))
