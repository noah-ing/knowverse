/**
 * Streaming Text Display Component
 * 
 * Creates a dynamic text display that handles streaming text content with
 * smooth rendering, cursor animation, and backpressure handling.
 * 
 * Usage:
 * const streamingElement = createStreamingElement(containerElement);
 * streamingElement.addText("This will be streamed...");
 */

/**
 * Create a streaming text display element
 * @param {HTMLElement} container - The container to render the streaming text in
 * @param {Object} options - Configuration options
 * @returns {Object} - The streaming text element controller
 */
export function createStreamingElement(container, options = {}) {
  // Configuration with defaults
  const config = {
    typingSpeed: options.typingSpeed || 0, // 0 = instant, higher = slower
    cursorBlink: options.cursorBlink !== false,
    cursorChar: options.cursorChar || '▌',
    className: options.className || 'streaming-text',
    renderMarkdown: options.renderMarkdown !== false,
    highlightCode: options.highlightCode !== false,
    ...options
  };
  
  // Create elements
  const wrapper = document.createElement('div');
  wrapper.className = config.className;
  
  const textElement = document.createElement('div');
  textElement.className = `${config.className}-content`;
  
  const cursor = document.createElement('span');
  cursor.className = `${config.className}-cursor`;
  cursor.textContent = config.cursorChar;
  
  if (config.cursorBlink) {
    cursor.classList.add(`${config.className}-cursor-blink`);
  }
  
  // Add to container
  wrapper.appendChild(textElement);
  wrapper.appendChild(cursor);
  container.appendChild(wrapper);
  
  // Track state
  let buffer = "";
  let isStreaming = false;
  let processingQueue = false;
  let streamTimeout = null;
  
  /**
   * Add text to the stream
   * @param {string} text - Text to add
   */
  function addText(text) {
    if (!text) return;
    
    // Add to buffer
    buffer += text;
    
    // Start streaming if not already
    if (!isStreaming) {
      streamNextChunk();
    }
  }
  
  /**
   * Stream the next chunk of text with throttling
   */
  function streamNextChunk() {
    isStreaming = true;
    
    // Process immediately if no typing speed
    if (config.typingSpeed === 0) {
      textElement.innerHTML = formatText(buffer);
      buffer = "";
      isStreaming = false;
      
      // Scroll container to bottom if needed
      scrollToBottom();
      return;
    }
    
    // Handle throttled rendering
    let chunk = buffer.slice(0, 10);
    if (chunk.length > 0) {
      textElement.innerHTML += formatText(chunk);
      buffer = buffer.slice(10);
      
      // Scroll to bottom
      scrollToBottom();
      
      // Continue streaming after delay
      streamTimeout = setTimeout(streamNextChunk, config.typingSpeed);
    } else {
      // Buffer empty, stop streaming
      isStreaming = false;
    }
  }
  
  /**
   * Format text with optional Markdown and code highlighting
   * @param {string} text - Text to format
   * @returns {string} - Formatted HTML
   */
  function formatText(text) {
    let formattedText = text;
    
    // If text is code block, apply formatting
    const isCodeBlock = /^```([a-z]*)\n([\s\S]*?)```$/m.test(text);
    
    if (isCodeBlock && config.highlightCode) {
      formattedText = highlightCodeBlock(text);
    } else if (config.renderMarkdown) {
      // Simple markdown-like formatting
      formattedText = formattedText
        // Bold
        .replace(/\*\*(.*?)\*\*/g, '<strong>$1</strong>')
        // Italic
        .replace(/\*(.*?)\*/g, '<em>$1</em>')
        // Code
        .replace(/`(.*?)`/g, '<code>$1</code>')
        // Linebreaks
        .replace(/\n/g, '<br>');
    }
    
    return formattedText;
  }
  
  /**
   * Apply syntax highlighting to code blocks
   * @param {string} text - Text containing code block
   * @returns {string} - HTML with highlighted code
   */
  function highlightCodeBlock(text) {
    // Extract code and language
    const match = text.match(/^```([a-z]*)\n([\s\S]*?)```$/m);
    
    if (!match) return text;
    
    const [fullMatch, language, code] = match;
    
    // If Prism.js is available, use it
    if (typeof Prism !== 'undefined') {
      try {
        const grammar = Prism.languages[language] || Prism.languages.javascript;
        const highlightedCode = Prism.highlight(code, grammar, language);
        
        return `<pre class="language-${language}"><code class="language-${language}">${highlightedCode}</code></pre>`;
      } catch (e) {
        console.warn('Error highlighting code:', e);
      }
    }
    
    // Fallback with simple formatting
    return `<pre><code class="language-${language}">${code}</code></pre>`;
  }
  
  /**
   * Scroll container to bottom
   */
  function scrollToBottom() {
    const parent = findScrollableParent(container);
    if (parent) {
      parent.scrollTop = parent.scrollHeight;
    }
  }
  
  /**
   * Find the nearest scrollable parent
   * @param {HTMLElement} element - Element to start from
   * @returns {HTMLElement} - The scrollable parent or null
   */
  function findScrollableParent(element) {
    if (!element) return null;
    
    // Check if element is scrollable
    const style = window.getComputedStyle(element);
    const overflowY = style.getPropertyValue('overflow-y');
    
    if (overflowY === 'auto' || overflowY === 'scroll') {
      return element;
    }
    
    // Move up the DOM tree
    return findScrollableParent(element.parentElement) || document.documentElement;
  }
  
  /**
   * Replace all content with new text
   * @param {string} text - New text content
   */
  function replaceContent(text) {
    // Clear current content and buffer
    buffer = "";
    clearTimeout(streamTimeout);
    isStreaming = false;
    
    // Set new content directly
    textElement.innerHTML = formatText(text);
    scrollToBottom();
  }
  
  /**
   * Clear all content
   */
  function clear() {
    buffer = "";
    clearTimeout(streamTimeout);
    isStreaming = false;
    textElement.innerHTML = "";
  }
  
  /**
   * Remove the streaming element
   */
  function remove() {
    clearTimeout(streamTimeout);
    container.removeChild(wrapper);
  }
  
  /**
   * Update configuration
   * @param {Object} newOptions - New configuration options
   */
  function updateConfig(newOptions) {
    Object.assign(config, newOptions);
    
    if (config.cursorBlink) {
      cursor.classList.add(`${config.className}-cursor-blink`);
    } else {
      cursor.classList.remove(`${config.className}-cursor-blink`);
    }
    
    cursor.textContent = config.cursorChar;
  }
  
  // Return the controller interface
  return {
    addText,
    replaceContent,
    clear,
    remove,
    updateConfig,
    element: wrapper,
    contentElement: textElement,
    cursorElement: cursor
  };
}
