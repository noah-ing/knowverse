//! Configuration management for the document processor

use serde::Deserialize;
use std::env;

/// Service configuration
#[derive(Debug, Clone, Deserialize)]
pub struct Config {
    /// Server host
    pub host: String,
    /// Server port
    pub port: u16,
    /// Maximum file size in MB
    pub max_file_size_mb: usize,
    /// Temporary directory for processing
    pub temp_dir: String,
    /// Enable WASM sandboxing
    pub sandbox_enabled: bool,
    /// Maximum processing time per document (seconds)
    pub timeout_seconds: u64,
    /// Default chunk size (tokens)
    pub default_chunk_size: usize,
    /// Default chunk overlap (tokens)
    pub default_chunk_overlap: usize,
}

impl Config {
    /// Load configuration from environment variables
    pub fn from_env() -> anyhow::Result<Self> {
        Ok(Config {
            host: env::var("DOCPROC_HOST").unwrap_or_else(|_| "0.0.0.0".to_string()),
            port: env::var("DOCPROC_PORT")
                .unwrap_or_else(|_| "8002".to_string())
                .parse()?,
            max_file_size_mb: env::var("MAX_FILE_SIZE_MB")
                .unwrap_or_else(|_| "100".to_string())
                .parse()?,
            temp_dir: env::var("TEMP_DIR").unwrap_or_else(|_| "/tmp/docproc".to_string()),
            sandbox_enabled: env::var("SANDBOX_ENABLED")
                .unwrap_or_else(|_| "true".to_string())
                .parse()?,
            timeout_seconds: env::var("TIMEOUT_SECONDS")
                .unwrap_or_else(|_| "60".to_string())
                .parse()?,
            default_chunk_size: env::var("DEFAULT_CHUNK_SIZE")
                .unwrap_or_else(|_| "512".to_string())
                .parse()?,
            default_chunk_overlap: env::var("DEFAULT_CHUNK_OVERLAP")
                .unwrap_or_else(|_| "64".to_string())
                .parse()?,
        })
    }
}

impl Default for Config {
    fn default() -> Self {
        Config {
            host: "0.0.0.0".to_string(),
            port: 8002,
            max_file_size_mb: 100,
            temp_dir: "/tmp/docproc".to_string(),
            sandbox_enabled: true,
            timeout_seconds: 60,
            default_chunk_size: 512,
            default_chunk_overlap: 64,
        }
    }
}
