//! WASM sandbox manager for secure document processing
//!
//! Uses Wasmtime to provide isolated execution environments for
//! document parsing, preventing malicious content from affecting
//! the host system.

use crate::config::Config;
use crate::error::{DocProcError, Result};
use std::path::PathBuf;
use std::sync::Arc;
use tokio::sync::Semaphore;

/// Manages WASM sandboxes for document processing
pub struct SandboxManager {
    /// Whether sandboxing is enabled
    enabled: bool,
    /// Temporary directory for processing
    temp_dir: PathBuf,
    /// Maximum concurrent processing tasks
    semaphore: Arc<Semaphore>,
    /// Processing timeout in seconds
    timeout_seconds: u64,
}

impl SandboxManager {
    /// Create a new sandbox manager
    pub fn new(config: &Config) -> Result<Self> {
        // Create temp directory if it doesn't exist
        let temp_dir = PathBuf::from(&config.temp_dir);
        std::fs::create_dir_all(&temp_dir)?;

        // Allow up to 4 concurrent document processing tasks
        let semaphore = Arc::new(Semaphore::new(4));

        Ok(SandboxManager {
            enabled: config.sandbox_enabled,
            temp_dir,
            semaphore,
            timeout_seconds: config.timeout_seconds,
        })
    }

    /// Get a processing permit (limits concurrency)
    pub async fn acquire_permit(&self) -> Result<tokio::sync::SemaphorePermit<'_>> {
        self.semaphore
            .acquire()
            .await
            .map_err(|e| DocProcError::SandboxError(format!("Failed to acquire permit: {}", e)))
    }

    /// Get the temp directory path
    pub fn temp_dir(&self) -> &PathBuf {
        &self.temp_dir
    }

    /// Get the processing timeout
    pub fn timeout_seconds(&self) -> u64 {
        self.timeout_seconds
    }

    /// Check if sandboxing is enabled
    pub fn is_enabled(&self) -> bool {
        self.enabled
    }

    /// Create a temporary file for processing
    pub fn create_temp_file(&self, extension: &str) -> Result<tempfile::NamedTempFile> {
        tempfile::Builder::new()
            .suffix(&format!(".{}", extension))
            .tempfile_in(&self.temp_dir)
            .map_err(|e| DocProcError::IoError(e))
    }
}

/// Security context for document processing
#[derive(Debug, Clone)]
pub struct SecurityContext {
    /// Maximum memory usage (bytes)
    pub max_memory: usize,
    /// Maximum execution time (milliseconds)
    pub max_execution_time: u64,
    /// Allow network access
    pub allow_network: bool,
    /// Allow file system access
    pub allow_filesystem: bool,
}

impl Default for SecurityContext {
    fn default() -> Self {
        SecurityContext {
            max_memory: 256 * 1024 * 1024, // 256MB
            max_execution_time: 30000,      // 30 seconds
            allow_network: false,
            allow_filesystem: false,
        }
    }
}
