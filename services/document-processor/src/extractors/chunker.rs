//! Text chunking for embedding generation

use crate::error::Result;
use serde::{Deserialize, Serialize};
use unicode_segmentation::UnicodeSegmentation;

/// Text chunker for splitting documents into embedding-friendly chunks
pub struct TextChunker {
    chunk_size: usize,
    chunk_overlap: usize,
}

/// A chunk of text with metadata
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TextChunk {
    /// Chunk content
    pub content: String,
    /// Chunk index
    pub index: usize,
    /// Start character offset in original text
    pub start_offset: usize,
    /// End character offset in original text
    pub end_offset: usize,
    /// Estimated token count
    pub token_count: usize,
}

/// Chunking strategy
#[derive(Debug, Clone, Copy, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum ChunkStrategy {
    /// Split by fixed token count with overlap
    #[default]
    FixedSize,
    /// Split by sentences, respecting boundaries
    Sentence,
    /// Split by paragraphs
    Paragraph,
    /// Split by semantic sections (headings)
    Semantic,
}

impl TextChunker {
    /// Create a new chunker
    pub fn new(chunk_size: usize, chunk_overlap: usize) -> Self {
        TextChunker {
            chunk_size,
            chunk_overlap,
        }
    }

    /// Chunk text using the specified strategy
    pub fn chunk(&self, text: &str, strategy: ChunkStrategy) -> Result<Vec<TextChunk>> {
        match strategy {
            ChunkStrategy::FixedSize => self.chunk_fixed_size(text),
            ChunkStrategy::Sentence => self.chunk_by_sentence(text),
            ChunkStrategy::Paragraph => self.chunk_by_paragraph(text),
            ChunkStrategy::Semantic => self.chunk_semantic(text),
        }
    }

    /// Fixed-size chunking with overlap
    fn chunk_fixed_size(&self, text: &str) -> Result<Vec<TextChunk>> {
        let words: Vec<&str> = text.split_whitespace().collect();
        let mut chunks = Vec::new();
        let mut i = 0;
        let mut chunk_index = 0;

        while i < words.len() {
            let end = (i + self.chunk_size).min(words.len());
            let chunk_words = &words[i..end];
            let content = chunk_words.join(" ");

            // Calculate offsets
            let start_offset = words[..i].iter().map(|w| w.len() + 1).sum();
            let end_offset = start_offset + content.len();

            chunks.push(TextChunk {
                content,
                index: chunk_index,
                start_offset,
                end_offset,
                token_count: chunk_words.len(),
            });

            // Move forward by (chunk_size - overlap)
            let step = self.chunk_size.saturating_sub(self.chunk_overlap).max(1);
            i += step;
            chunk_index += 1;
        }

        Ok(chunks)
    }

    /// Sentence-based chunking
    fn chunk_by_sentence(&self, text: &str) -> Result<Vec<TextChunk>> {
        let sentences: Vec<&str> = text.unicode_sentences().collect();
        let mut chunks = Vec::new();
        let mut current_chunk = String::new();
        let mut current_tokens = 0;
        let mut chunk_index = 0;
        let mut start_offset = 0;

        for sentence in sentences {
            let sentence_tokens = Self::estimate_tokens(sentence);

            if current_tokens + sentence_tokens > self.chunk_size && !current_chunk.is_empty() {
                // Save current chunk
                let content = current_chunk.trim().to_string();
                let end_offset = start_offset + content.len();

                chunks.push(TextChunk {
                    content,
                    index: chunk_index,
                    start_offset,
                    end_offset,
                    token_count: current_tokens,
                });

                // Start new chunk (with overlap if needed)
                chunk_index += 1;
                start_offset = end_offset;
                current_chunk.clear();
                current_tokens = 0;
            }

            current_chunk.push_str(sentence);
            current_chunk.push(' ');
            current_tokens += sentence_tokens;
        }

        // Don't forget the last chunk
        if !current_chunk.is_empty() {
            let content = current_chunk.trim().to_string();
            chunks.push(TextChunk {
                content: content.clone(),
                index: chunk_index,
                start_offset,
                end_offset: start_offset + content.len(),
                token_count: current_tokens,
            });
        }

        Ok(chunks)
    }

    /// Paragraph-based chunking
    fn chunk_by_paragraph(&self, text: &str) -> Result<Vec<TextChunk>> {
        let paragraphs: Vec<&str> = text.split("\n\n").collect();
        let mut chunks = Vec::new();
        let mut current_chunk = String::new();
        let mut current_tokens = 0;
        let mut chunk_index = 0;
        let mut start_offset = 0;

        for paragraph in paragraphs {
            let paragraph = paragraph.trim();
            if paragraph.is_empty() {
                continue;
            }

            let para_tokens = Self::estimate_tokens(paragraph);

            // If single paragraph exceeds chunk size, split it
            if para_tokens > self.chunk_size {
                // Save current chunk first
                if !current_chunk.is_empty() {
                    let content = current_chunk.trim().to_string();
                    chunks.push(TextChunk {
                        content: content.clone(),
                        index: chunk_index,
                        start_offset,
                        end_offset: start_offset + content.len(),
                        token_count: current_tokens,
                    });
                    chunk_index += 1;
                    start_offset += content.len() + 2; // +2 for \n\n
                    current_chunk.clear();
                    current_tokens = 0;
                }

                // Split large paragraph by sentences
                let sub_chunks = self.chunk_by_sentence(paragraph)?;
                for sub_chunk in sub_chunks {
                    chunks.push(TextChunk {
                        content: sub_chunk.content,
                        index: chunk_index,
                        start_offset: start_offset + sub_chunk.start_offset,
                        end_offset: start_offset + sub_chunk.end_offset,
                        token_count: sub_chunk.token_count,
                    });
                    chunk_index += 1;
                }
                start_offset += paragraph.len() + 2;
                continue;
            }

            if current_tokens + para_tokens > self.chunk_size && !current_chunk.is_empty() {
                // Save current chunk
                let content = current_chunk.trim().to_string();
                chunks.push(TextChunk {
                    content: content.clone(),
                    index: chunk_index,
                    start_offset,
                    end_offset: start_offset + content.len(),
                    token_count: current_tokens,
                });

                chunk_index += 1;
                start_offset += content.len() + 2;
                current_chunk.clear();
                current_tokens = 0;
            }

            if !current_chunk.is_empty() {
                current_chunk.push_str("\n\n");
            }
            current_chunk.push_str(paragraph);
            current_tokens += para_tokens;
        }

        // Last chunk
        if !current_chunk.is_empty() {
            let content = current_chunk.trim().to_string();
            chunks.push(TextChunk {
                content: content.clone(),
                index: chunk_index,
                start_offset,
                end_offset: start_offset + content.len(),
                token_count: current_tokens,
            });
        }

        Ok(chunks)
    }

    /// Semantic chunking (by headings)
    fn chunk_semantic(&self, text: &str) -> Result<Vec<TextChunk>> {
        // Split by markdown-style headings
        let heading_re = regex::Regex::new(r"(?m)^#{1,6}\s").unwrap();

        let mut sections = Vec::new();
        let mut last_end = 0;

        for m in heading_re.find_iter(text) {
            if m.start() > last_end {
                sections.push(&text[last_end..m.start()]);
            }
            last_end = m.start();
        }
        if last_end < text.len() {
            sections.push(&text[last_end..]);
        }

        // If no headings found, fall back to paragraph chunking
        if sections.len() <= 1 {
            return self.chunk_by_paragraph(text);
        }

        let mut chunks = Vec::new();
        let mut chunk_index = 0;
        let mut offset = 0;

        for section in sections {
            let section = section.trim();
            if section.is_empty() {
                continue;
            }

            let tokens = Self::estimate_tokens(section);

            if tokens <= self.chunk_size {
                chunks.push(TextChunk {
                    content: section.to_string(),
                    index: chunk_index,
                    start_offset: offset,
                    end_offset: offset + section.len(),
                    token_count: tokens,
                });
                chunk_index += 1;
            } else {
                // Section too large, split by paragraphs
                let sub_chunks = self.chunk_by_paragraph(section)?;
                for sub_chunk in sub_chunks {
                    chunks.push(TextChunk {
                        content: sub_chunk.content,
                        index: chunk_index,
                        start_offset: offset + sub_chunk.start_offset,
                        end_offset: offset + sub_chunk.end_offset,
                        token_count: sub_chunk.token_count,
                    });
                    chunk_index += 1;
                }
            }

            offset += section.len() + 2;
        }

        Ok(chunks)
    }

    /// Estimate token count (rough approximation: ~4 chars per token)
    fn estimate_tokens(text: &str) -> usize {
        (text.len() + 3) / 4
    }
}
