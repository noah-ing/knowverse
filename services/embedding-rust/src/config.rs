//! Configuration management for the embedding service

use serde::Deserialize;
use std::env;

/// Service configuration
#[derive(Debug, Clone, Deserialize)]
pub struct Config {
    /// Server host
    pub host: String,
    /// Server port
    pub port: u16,
    /// Path to model files
    pub model_path: String,
    /// Default model to use
    pub default_model: String,
    /// Cache size in MB
    pub cache_size_mb: u64,
    /// Maximum batch size
    pub max_batch_size: usize,
    /// Number of inference threads
    pub num_threads: usize,
    /// Enable GPU acceleration (CUDA)
    pub use_gpu: bool,
}

impl Config {
    /// Load configuration from environment variables
    pub fn from_env() -> anyhow::Result<Self> {
        Ok(Config {
            host: env::var("EMBEDDING_HOST").unwrap_or_else(|_| "0.0.0.0".to_string()),
            port: env::var("EMBEDDING_PORT")
                .unwrap_or_else(|_| "8001".to_string())
                .parse()?,
            model_path: env::var("MODEL_PATH").unwrap_or_else(|_| "./models".to_string()),
            default_model: env::var("DEFAULT_MODEL")
                .unwrap_or_else(|_| "all-MiniLM-L6-v2".to_string()),
            cache_size_mb: env::var("CACHE_SIZE_MB")
                .unwrap_or_else(|_| "512".to_string())
                .parse()?,
            max_batch_size: env::var("MAX_BATCH_SIZE")
                .unwrap_or_else(|_| "64".to_string())
                .parse()?,
            num_threads: env::var("NUM_THREADS")
                .unwrap_or_else(|_| num_cpus::get().to_string())
                .parse()?,
            use_gpu: env::var("USE_GPU")
                .unwrap_or_else(|_| "false".to_string())
                .parse()?,
        })
    }
}

impl Default for Config {
    fn default() -> Self {
        Config {
            host: "0.0.0.0".to_string(),
            port: 8001,
            model_path: "./models".to_string(),
            default_model: "all-MiniLM-L6-v2".to_string(),
            cache_size_mb: 512,
            max_batch_size: 64,
            num_threads: 4,
            use_gpu: false,
        }
    }
}
