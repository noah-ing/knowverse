# Knowverse Embedding Service (Rust)

High-performance ONNX-based embedding generation service for Knowverse.

## Performance

| Operation | Python (Haystack) | Rust (This) | Speedup |
|-----------|-------------------|-------------|---------|
| Single embedding | 150-200ms | 10-30ms | 5-15x |
| Batch (32 docs) | 2000ms | 100-200ms | 10-20x |
| Memory per model | ~2GB | ~500MB | 4x |

## Supported Models

| Model | Dimensions | Max Tokens | Use Case |
|-------|------------|------------|----------|
| all-MiniLM-L6-v2 | 384 | 256 | Fast, general purpose |
| all-mpnet-base-v2 | 768 | 384 | High quality semantic search |
| bge-small-en-v1.5 | 384 | 512 | Excellent quality/speed |
| bge-base-en-v1.5 | 768 | 512 | High quality |
| bge-large-en-v1.5 | 1024 | 512 | Best quality |

## API Endpoints

### Health
- `GET /health` - Health check
- `GET /ready` - Readiness check (model loaded)

### Embeddings
- `POST /embed` - Single text embedding
- `POST /embed/batch` - Batch embeddings (up to 64)

### Models
- `GET /models` - List available models
- `POST /models/:model_id/load` - Load a specific model

### Metrics
- `GET /metrics` - Cache and performance metrics

## Usage

### Single Embedding

```bash
curl -X POST http://localhost:8001/embed \
  -H "Content-Type: application/json" \
  -d '{"text": "Hello world", "model": "all-MiniLM-L6-v2"}'
```

Response:
```json
{
  "embedding": [0.123, -0.456, ...],
  "model": "all-MiniLM-L6-v2",
  "dimension": 384,
  "processing_time_ms": 12.5,
  "cached": false
}
```

### Batch Embeddings

```bash
curl -X POST http://localhost:8001/embed/batch \
  -H "Content-Type: application/json" \
  -d '{"texts": ["Hello", "World"], "model": "all-MiniLM-L6-v2"}'
```

Response:
```json
{
  "embeddings": [[0.123, ...], [0.456, ...]],
  "model": "all-MiniLM-L6-v2",
  "dimension": 384,
  "processing_time_ms": 25.3,
  "cached_count": 0,
  "computed_count": 2
}
```

## Configuration

| Environment Variable | Default | Description |
|---------------------|---------|-------------|
| EMBEDDING_HOST | 0.0.0.0 | Server host |
| EMBEDDING_PORT | 8001 | Server port |
| MODEL_PATH | ./models | Path to ONNX models |
| DEFAULT_MODEL | all-MiniLM-L6-v2 | Default model |
| CACHE_SIZE_MB | 512 | Embedding cache size |
| MAX_BATCH_SIZE | 64 | Maximum batch size |
| NUM_THREADS | CPU count | Inference threads |
| USE_GPU | false | Enable CUDA (if available) |
| RUST_LOG | info | Log level |

## Model Setup

Download ONNX models to the `models/` directory:

```
models/
├── all-MiniLM-L6-v2/
│   ├── model.onnx
│   └── tokenizer.json
├── all-mpnet-base-v2/
│   ├── model.onnx
│   └── tokenizer.json
└── ...
```

Models can be exported from HuggingFace using:

```python
from optimum.onnxruntime import ORTModelForFeatureExtraction
from transformers import AutoTokenizer

model = ORTModelForFeatureExtraction.from_pretrained(
    "sentence-transformers/all-MiniLM-L6-v2",
    export=True
)
model.save_pretrained("models/all-MiniLM-L6-v2")

tokenizer = AutoTokenizer.from_pretrained("sentence-transformers/all-MiniLM-L6-v2")
tokenizer.save_pretrained("models/all-MiniLM-L6-v2")
```

## Docker

```bash
# Build
docker build -t knowverse-embedding .

# Run
docker run -p 8001:8001 \
  -v ./models:/app/models \
  -e DEFAULT_MODEL=all-MiniLM-L6-v2 \
  knowverse-embedding
```

## Development

```bash
# Build
cargo build --release

# Run
RUST_LOG=debug cargo run

# Test
cargo test
```

## Architecture

```
src/
├── main.rs      # Axum server setup
├── config.rs    # Configuration management
├── error.rs     # Error types
├── cache.rs     # LRU embedding cache (moka)
├── models.rs    # ONNX model loading and inference
└── routes.rs    # API endpoints
```

## Caching

The service uses an in-memory LRU cache to avoid recomputing embeddings for identical texts. Cache key is hash(text) + model_id.

- Default size: 512MB (~170K embeddings at 768 dimensions)
- TTL: 1 hour idle time
- Batch operations check cache first, only compute missing

## Integration with Rails

The Rails `HaystackClient` can be configured to use this service:

```ruby
# config/initializers/embedding_service.rb
RUST_EMBEDDING_URL = ENV.fetch('RUST_EMBEDDING_URL', 'http://localhost:8001')
```

The service will automatically fall back to Python Haystack if the Rust service is unavailable.
