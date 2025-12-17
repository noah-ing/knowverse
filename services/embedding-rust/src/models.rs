//! ONNX model loading and inference for sentence embeddings

use crate::config::Config;
use crate::error::{EmbeddingError, Result};
use ndarray::{Array1, Array2, Axis};
use ort::{GraphOptimizationLevel, Session, SessionBuilder};
use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::Arc;
use tokenizers::Tokenizer;
use tokio::sync::RwLock;

/// Supported embedding models with their configurations
#[derive(Debug, Clone, serde::Serialize)]
pub struct ModelInfo {
    pub id: String,
    pub name: String,
    pub dimension: usize,
    pub max_tokens: usize,
    pub description: String,
    pub loaded: bool,
}

/// Available models configuration
const MODELS: &[(&str, &str, usize, usize, &str)] = &[
    (
        "all-MiniLM-L6-v2",
        "all-MiniLM-L6-v2",
        384,
        256,
        "Fast, lightweight model for general-purpose embeddings",
    ),
    (
        "all-mpnet-base-v2",
        "all-mpnet-base-v2",
        768,
        384,
        "High-quality embeddings, best for semantic search",
    ),
    (
        "bge-small-en-v1.5",
        "BAAI/bge-small-en-v1.5",
        384,
        512,
        "BGE small model, excellent quality/speed ratio",
    ),
    (
        "bge-base-en-v1.5",
        "BAAI/bge-base-en-v1.5",
        768,
        512,
        "BGE base model, high quality embeddings",
    ),
    (
        "bge-large-en-v1.5",
        "BAAI/bge-large-en-v1.5",
        1024,
        512,
        "BGE large model, best quality (slower)",
    ),
];

/// A loaded embedding model with tokenizer and ONNX session
pub struct LoadedModel {
    pub info: ModelInfo,
    pub tokenizer: Tokenizer,
    pub session: Session,
}

impl LoadedModel {
    /// Generate embeddings for a batch of texts
    pub fn embed(&self, texts: &[String]) -> Result<Vec<Vec<f32>>> {
        if texts.is_empty() {
            return Ok(vec![]);
        }

        // Tokenize all texts
        let encodings = self
            .tokenizer
            .encode_batch(texts.to_vec(), true)
            .map_err(|e| EmbeddingError::TokenizationError(e.to_string()))?;

        // Find max length for padding
        let max_len = encodings
            .iter()
            .map(|e| e.get_ids().len())
            .max()
            .unwrap_or(0)
            .min(self.info.max_tokens);

        let batch_size = texts.len();

        // Prepare input tensors with padding
        let mut input_ids: Vec<i64> = Vec::with_capacity(batch_size * max_len);
        let mut attention_mask: Vec<i64> = Vec::with_capacity(batch_size * max_len);
        let mut token_type_ids: Vec<i64> = Vec::with_capacity(batch_size * max_len);

        for encoding in &encodings {
            let ids = encoding.get_ids();
            let mask = encoding.get_attention_mask();
            let len = ids.len().min(max_len);

            // Add tokens (truncate if needed)
            input_ids.extend(ids[..len].iter().map(|&x| x as i64));
            attention_mask.extend(mask[..len].iter().map(|&x| x as i64));
            token_type_ids.extend(std::iter::repeat(0i64).take(len));

            // Pad if needed
            let pad_len = max_len - len;
            if pad_len > 0 {
                input_ids.extend(std::iter::repeat(0i64).take(pad_len));
                attention_mask.extend(std::iter::repeat(0i64).take(pad_len));
                token_type_ids.extend(std::iter::repeat(0i64).take(pad_len));
            }
        }

        // Create ndarray tensors
        let input_ids =
            Array2::from_shape_vec((batch_size, max_len), input_ids).map_err(|e| {
                EmbeddingError::InferenceError(format!("Failed to create input_ids tensor: {}", e))
            })?;

        let attention_mask =
            Array2::from_shape_vec((batch_size, max_len), attention_mask).map_err(|e| {
                EmbeddingError::InferenceError(format!(
                    "Failed to create attention_mask tensor: {}",
                    e
                ))
            })?;

        let token_type_ids =
            Array2::from_shape_vec((batch_size, max_len), token_type_ids).map_err(|e| {
                EmbeddingError::InferenceError(format!(
                    "Failed to create token_type_ids tensor: {}",
                    e
                ))
            })?;

        // Run inference
        let outputs = self
            .session
            .run(ort::inputs![
                "input_ids" => input_ids.view(),
                "attention_mask" => attention_mask.view(),
                "token_type_ids" => token_type_ids.view(),
            ]?)
            .map_err(|e| EmbeddingError::InferenceError(format!("ONNX inference failed: {}", e)))?;

        // Extract embeddings from output (last_hidden_state)
        // Shape: (batch_size, seq_len, hidden_size)
        let output = outputs
            .get("last_hidden_state")
            .or_else(|| outputs.get("sentence_embedding"))
            .ok_or_else(|| {
                EmbeddingError::InferenceError("No embedding output found".to_string())
            })?;

        let output_tensor = output.try_extract_tensor::<f32>().map_err(|e| {
            EmbeddingError::InferenceError(format!("Failed to extract output tensor: {}", e))
        })?;

        let output_view = output_tensor.view();
        let shape = output_view.shape();

        // Mean pooling over sequence length
        let embeddings: Vec<Vec<f32>> = if shape.len() == 3 {
            // Shape: (batch, seq_len, hidden)
            let hidden_size = shape[2];
            (0..batch_size)
                .map(|i| {
                    let seq_embedding: Vec<f32> = (0..hidden_size)
                        .map(|h| {
                            let sum: f32 = (0..shape[1])
                                .map(|s| output_view[[i, s, h]])
                                .sum();
                            sum / shape[1] as f32
                        })
                        .collect();
                    normalize(&seq_embedding)
                })
                .collect()
        } else if shape.len() == 2 {
            // Already pooled: (batch, hidden)
            (0..batch_size)
                .map(|i| {
                    let embedding: Vec<f32> = (0..shape[1]).map(|h| output_view[[i, h]]).collect();
                    normalize(&embedding)
                })
                .collect()
        } else {
            return Err(EmbeddingError::InferenceError(format!(
                "Unexpected output shape: {:?}",
                shape
            )));
        };

        Ok(embeddings)
    }

    /// Generate embedding for a single text
    pub fn embed_single(&self, text: &str) -> Result<Vec<f32>> {
        let embeddings = self.embed(&[text.to_string()])?;
        embeddings.into_iter().next().ok_or_else(|| {
            EmbeddingError::InferenceError("No embedding generated".to_string())
        })
    }
}

/// L2 normalize a vector
fn normalize(vec: &[f32]) -> Vec<f32> {
    let norm: f32 = vec.iter().map(|x| x * x).sum::<f32>().sqrt();
    if norm > 0.0 {
        vec.iter().map(|x| x / norm).collect()
    } else {
        vec.to_vec()
    }
}

/// Registry of available and loaded models
pub struct ModelRegistry {
    models: HashMap<String, ModelInfo>,
    loaded: Arc<RwLock<HashMap<String, Arc<LoadedModel>>>>,
    model_path: PathBuf,
    num_threads: usize,
}

impl ModelRegistry {
    /// Create a new model registry and optionally load the default model
    pub async fn new(config: &Config) -> Result<Self> {
        let mut models = HashMap::new();

        for (id, name, dim, max_tokens, desc) in MODELS {
            models.insert(
                id.to_string(),
                ModelInfo {
                    id: id.to_string(),
                    name: name.to_string(),
                    dimension: *dim,
                    max_tokens: *max_tokens,
                    description: desc.to_string(),
                    loaded: false,
                },
            );
        }

        let registry = ModelRegistry {
            models,
            loaded: Arc::new(RwLock::new(HashMap::new())),
            model_path: PathBuf::from(&config.model_path),
            num_threads: config.num_threads,
        };

        // Load default model if it exists
        let default_model_path = registry.model_path.join(&config.default_model);
        if default_model_path.exists() {
            tracing::info!("Loading default model: {}", config.default_model);
            if let Err(e) = registry.load_model(&config.default_model).await {
                tracing::warn!("Failed to load default model: {}", e);
            }
        } else {
            tracing::info!(
                "Default model not found at {:?}, will load on first request",
                default_model_path
            );
        }

        Ok(registry)
    }

    /// Get list of available models
    pub fn available_models(&self) -> Vec<ModelInfo> {
        self.models.values().cloned().collect()
    }

    /// Get model info
    pub fn get_model_info(&self, model_id: &str) -> Option<ModelInfo> {
        self.models.get(model_id).cloned()
    }

    /// Check if a model is loaded
    pub async fn is_loaded(&self, model_id: &str) -> bool {
        self.loaded.read().await.contains_key(model_id)
    }

    /// Load a model
    pub async fn load_model(&self, model_id: &str) -> Result<()> {
        // Check if model exists in registry
        let model_info = self
            .models
            .get(model_id)
            .ok_or_else(|| EmbeddingError::ModelNotFound(model_id.to_string()))?
            .clone();

        // Check if already loaded
        if self.is_loaded(model_id).await {
            return Ok(());
        }

        let model_dir = self.model_path.join(model_id);

        // Load tokenizer
        let tokenizer_path = model_dir.join("tokenizer.json");
        let tokenizer = Tokenizer::from_file(&tokenizer_path).map_err(|e| {
            EmbeddingError::ModelLoadError(format!(
                "Failed to load tokenizer from {:?}: {}",
                tokenizer_path, e
            ))
        })?;

        // Load ONNX model
        let onnx_path = model_dir.join("model.onnx");
        let session = SessionBuilder::new()?
            .with_optimization_level(GraphOptimizationLevel::Level3)?
            .with_intra_threads(self.num_threads)?
            .commit_from_file(&onnx_path)
            .map_err(|e| {
                EmbeddingError::ModelLoadError(format!(
                    "Failed to load ONNX model from {:?}: {}",
                    onnx_path, e
                ))
            })?;

        let loaded_model = Arc::new(LoadedModel {
            info: ModelInfo {
                loaded: true,
                ..model_info
            },
            tokenizer,
            session,
        });

        // Store in registry
        self.loaded
            .write()
            .await
            .insert(model_id.to_string(), loaded_model);

        tracing::info!("Model {} loaded successfully", model_id);
        Ok(())
    }

    /// Get a loaded model for inference
    pub async fn get_model(&self, model_id: &str) -> Result<Arc<LoadedModel>> {
        // Try to get loaded model
        if let Some(model) = self.loaded.read().await.get(model_id) {
            return Ok(Arc::clone(model));
        }

        // Try to load it
        self.load_model(model_id).await?;

        // Get it again
        self.loaded
            .read()
            .await
            .get(model_id)
            .cloned()
            .ok_or_else(|| EmbeddingError::ModelNotLoaded(model_id.to_string()))
    }

    /// Unload a model to free memory
    pub async fn unload_model(&self, model_id: &str) {
        self.loaded.write().await.remove(model_id);
        tracing::info!("Model {} unloaded", model_id);
    }
}
