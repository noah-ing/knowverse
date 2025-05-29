import { Controller } from "@hotwired/stimulus"
import { createStreamingTextDisplay } from "../components/streaming_text_display"

/**
 * RAG Controller
 * 
 * Enhanced controller for handling streaming RAG responses with improved UX:
 * - Dark mode support
 * - Accessibility features
 * - Performance metrics visualization
 * - Mobile responsiveness
 * - Error handling and recovery
 */
export default class extends Controller {
  static targets = [
    "form", "query", "submit", "streamingToggle", "conversationId", 
    "advancedOptions", "responseContainer", "streamingResponse", 
    "streamingCursor", "sources", "sourcesContainer", "conversationContainer",
    "status", "waiting", "streaming", "complete", "feedbackContainer",
    "performanceMetrics", "ttftValue", "tpsValue", "totalTokens", "totalTime",
    "floatingMetrics", "floatingTtft", "floatingTps", "floatingTokens", "floatingTime"
  ]
  
  connect() {
    console.log("RAG controller connected")
    this.streamingDisplay = null
    this.eventSource = null
    this.isStreaming = false
    this.currentQuery = ""
    this.currentResponse = ""
    this.conversationHistory = []
    this.sourceReferences = []
  }
  
  disconnect() {
    this.closeEventSource()
  }
  
  // Handle keyboard shortcuts in the query input
  handleKeydown(event) {
    // Handle Ctrl+Enter to submit form
    if (event.ctrlKey && event.key === 'Enter') {
      this.submitQuery(new Event('submit'))
      event.preventDefault()
    }
    
    // Handle Escape to clear input
    if (event.key === 'Escape') {
      this.queryTarget.value = ''
      event.preventDefault()
    }
  }
  
  // Handle form submission for query
  submitQuery(event) {
    event.preventDefault()
    
    // Get the form and query
    const form = this.formTarget
    this.currentQuery = this.queryTarget.value.trim()
    
    // Skip empty queries
    if (!this.currentQuery) {
      return false
    }
    
    // Get the conversation ID if set
    const conversationId = this.hasConversationIdTarget ? this.conversationIdTarget.value : null
    
    // Create form data
    const formData = new FormData(form)
    
    // Add the question to the conversation UI
    this.addUserMessage(this.currentQuery)
    
    // Clear the query input and focus it
    this.queryTarget.value = ""
    this.queryTarget.focus()
    
    // Show the response container
    this.responseContainerTarget.classList.remove('hidden')
    
    // Reset the sources container
    this.sourcesContainerTarget.classList.add('hidden')
    this.sourcesTarget.innerHTML = ""
    
    // Hide feedback container
    if (this.hasFeedbackContainerTarget) {
      this.feedbackContainerTarget.classList.add('hidden')
    }
    
    // Update status indicators
    this.updateStatus('waiting')
    
    // Initialize streaming display if not already done
    if (!this.streamingDisplay) {
      this.initStreamingDisplay()
    } else {
      // Reset the display
      this.streamingDisplay.reset()
    }
    
    // Check if streaming is enabled
    const isStreamingEnabled = this.hasStreamingToggleTarget && this.streamingToggleTarget.checked
    
    if (isStreamingEnabled) {
      // Start streaming request
      this.startStreaming(formData)
    } else {
      // Standard request
      this.startStandardRequest(formData)
    }
    
    // Disable submit button during processing
    this.submitTarget.disabled = true
    
    return false
  }
  
  // Initialize the streaming text display component
  initStreamingDisplay() {
    // Create enhanced streaming display with our design system classes
    this.streamingDisplay = createStreamingTextDisplay({
      container: this.streamingResponseTarget,
      cursor: this.streamingCursorTarget,
      typingSpeed: 20, // ms per token (lower = faster)
      typingVariability: 10, // ms of random variation
      highlightSources: true,
      highlightClass: 'kv-source-citation',
      highlightActiveClass: 'kv-source-hover-highlight',
      accessibility: true, // Enable accessibility features
      sentenceEndPause: 15, // Extra pause at end of sentences for natural reading
      commaClausePause: 8 // Extra pause at commas
    })
  }
  
  // Start a streaming request using SSE
  startStreaming(formData) {
    // Close any existing event source
    this.closeEventSource()
    
    // Update status
    this.updateStatus('streaming')
    
    // Convert FormData to URL parameters
    const params = new URLSearchParams(formData)
    
    // Create Event Source for streaming
    const url = `${this.formTarget.action}?${params.toString()}`
    this.eventSource = new EventSource(url)
    
    // Reset streaming state
    this.isStreaming = true
    this.currentResponse = ""
    this.sourceReferences = []
    this.lastEventId = 0
    
    // Handle incoming tokens
    this.eventSource.addEventListener('token', this.handleToken.bind(this))
    
    // Handle source references
    this.eventSource.addEventListener('sources', this.handleSources.bind(this))
    
    // Handle metadata
    this.eventSource.addEventListener('metadata', this.handleMetadata.bind(this))
    
    // Handle completion
    this.eventSource.addEventListener('done', this.handleStreamingComplete.bind(this))
    
    // Handle errors
    this.eventSource.onerror = this.handleStreamingError.bind(this)
  }
  
  // Start a standard non-streaming request
  startStandardRequest(formData) {
    // Update status
    this.updateStatus('waiting')
    
    // Make a fetch request
    fetch(this.formTarget.action, {
      method: 'POST',
      body: formData,
      headers: {
        'Accept': 'application/json',
        'X-Requested-With': 'XMLHttpRequest'
      }
    })
    .then(response => response.json())
    .then(data => {
      // Display the response
      if (data.content) {
        this.streamingResponseTarget.textContent = data.content
      }
      
      // Handle sources
      if (data.sources) {
        this.updateSources(data.sources)
      }
      
      // Update status
      this.updateStatus('complete')
      
      // Re-enable submit button
      this.submitTarget.disabled = false
      
      // Show feedback container
      if (this.hasFeedbackContainerTarget) {
        this.feedbackContainerTarget.classList.remove('hidden')
      }
    })
    .catch(error => {
      console.error('Error:', error)
      this.streamingResponseTarget.textContent = "An error occurred while processing your request."
      
      // Update status
      this.updateStatus('error')
      
      // Re-enable submit button
      this.submitTarget.disabled = false
    })
  }
  
  // Handle streaming token events
  handleToken(event) {
    if (!this.isStreaming) return
    
    // Parse the data
    const data = JSON.parse(event.data)
    
    // Check for sequential order
    if (data.id) {
      if (this.lastEventId + 1 !== data.id) {
        console.warn(`Token out of order, expected ${this.lastEventId + 1}, got ${data.id}`)
      }
      this.lastEventId = data.id
    }
    
    // Add to current response
    this.currentResponse += data.token
    
    // If this is the first token, initialize streaming
    if (this.currentResponse.length === data.token.length) {
      this.streamingDisplay.streamText([data.token])
      
      // Start displaying performance metrics
      if (this.hasPerformanceMetricsTarget) {
        this.performanceMetricsTarget.classList.remove('hidden')
      }
      
      // Display time to first token
      if (this.hasTtftValueTarget) {
        const ttft = Math.round(this.streamingDisplay.timeToFirstToken)
        this.ttftValueTarget.textContent = ttft
      }
    } else {
      // Stream just this token
      this.streamingDisplay.tokens.push(data.token)
      this.streamingDisplay.text = this.currentResponse // Ensure synchronized
    }
    
    // Update metrics as tokens arrive
    this.updatePerformanceMetrics()
  }
  
  // Update the performance metrics display
  updatePerformanceMetrics(isComplete = false) {
    // Only proceed if we have the metrics targets
    if (!this.hasPerformanceMetricsTarget) return
    
    const now = performance.now()
    const elapsedTime = now - this.streamingDisplay.startTime
    
    // Update tokens per second
    if (this.streamingDisplay.tokensPerSecond) {
      const tps = this.streamingDisplay.tokensPerSecond.toFixed(1)
      
      if (this.hasTpsValueTarget) {
        this.tpsValueTarget.textContent = tps
      }
      
      if (this.hasFloatingTpsTarget) {
        this.floatingTpsTarget.textContent = tps
      }
    }
    
    // Update total tokens
    const tokenCount = this.streamingDisplay.tokenCount
    if (this.hasTotalTokensTarget) {
      this.totalTokensTarget.textContent = tokenCount
    }
    
    if (this.hasFloatingTokensTarget) {
      this.floatingTokensTarget.textContent = tokenCount
    }
    
    // Update time to first token
    if (this.streamingDisplay.timeToFirstToken) {
      const ttft = Math.round(this.streamingDisplay.timeToFirstToken)
      
      if (this.hasTtftValueTarget) {
        this.ttftValueTarget.textContent = ttft
      }
      
      if (this.hasFloatingTtftTarget) {
        this.floatingTtftTarget.textContent = ttft
      }
    }
    
    // Update total time
    if (isComplete || this.streamingDisplay.tokenCount > 10) {
      const totalTime = Math.round(elapsedTime)
      
      if (this.hasTotalTimeTarget) {
        this.totalTimeTarget.textContent = totalTime
      }
      
      if (this.hasFloatingTimeTarget) {
        this.floatingTimeTarget.textContent = totalTime
      }
    }
    
    // Show floating metrics if we have enough tokens and it's not already visible
    if (this.hasFloatingMetricsTarget && this.streamingDisplay.tokenCount > 5 && 
        this.floatingMetricsTarget.classList.contains('hidden')) {
      this.floatingMetricsTarget.classList.remove('hidden')
    }
  }
  
  // Handle sources event
  handleSources(event) {
    const data = JSON.parse(event.data)
    
    // Store references for highlighting
    this.sourceReferences = data.sources || []
    
    // Update UI with source list
    this.updateSources(this.sourceReferences)
    
    // Register hover events for source highlighting
    setTimeout(() => {
      // Add source references to text display for highlighting
      if (this.streamingDisplay) {
        this.streamingDisplay.addSourceReferences(this.sourceReferences)
      }
      
      // Add hover effects for source list items
      const sourceItems = this.sourcesTarget.querySelectorAll('li')
      sourceItems.forEach(item => {
        const sourceId = item.dataset.sourceId
        
        // Mouse enter - highlight in text
        item.addEventListener('mouseenter', () => {
          if (this.streamingDisplay) {
            this.streamingDisplay.highlightSource(sourceId)
          }
          item.classList.add('bg-indigo-50')
        })
        
        // Mouse leave - remove highlight 
        item.addEventListener('mouseleave', () => {
          if (this.streamingDisplay) {
            this.streamingDisplay.clearSourceHighlight()
          }
          item.classList.remove('bg-indigo-50')
        })
      })
    }, 100)
  }
  
  // Handle metadata event
  handleMetadata(event) {
    const data = JSON.parse(event.data)
    console.log('Metadata:', data)
    // Store metadata for potential use
    this.streamingMetadata = data
  }
  
  // Handle streaming complete
  handleStreamingComplete(event) {
    // Mark streaming as done
    this.isStreaming = false
    
    // Close the event source
    this.closeEventSource()
    
    // Apply final formatting to text with source highlighting
    if (this.streamingDisplay) {
      this.streamingDisplay.finishStreaming(() => {
        // Final update of performance metrics with complete flag
        this.updatePerformanceMetrics(true)
      })
    }
    
    // Update status
    this.updateStatus('complete')
    
    // Re-enable submit button
    this.submitTarget.disabled = false
    
    // Show feedback container
    if (this.hasFeedbackContainerTarget) {
      this.feedbackContainerTarget.classList.remove('hidden')
    }
    
    // Add the assistant response to the conversation history
    this.addAssistantMessage(this.currentResponse, this.sourceReferences, this.streamingMetadata)
    
    // Hide performance metrics after 10 seconds
    setTimeout(() => {
      if (this.hasPerformanceMetricsTarget) {
        this.performanceMetricsTarget.classList.add('hidden')
      }
      
      // Also hide floating metrics panel if it exists
      if (this.hasFloatingMetricsTarget) {
        this.floatingMetricsTarget.classList.add('hidden')
      }
    }, 10000)
  }
  
  // Handle streaming errors
  handleStreamingError(event) {
    console.error('EventSource error:', event)
    
    // Check if we've already processed some content
    if (this.currentResponse.length > 0) {
      // We got partial content, so finish normally
      this.handleStreamingComplete(event)
    } else {
      // No content received, show error message
      this.streamingResponseTarget.textContent = "An error occurred during streaming. Please try again."
    }
    
    // Close the connection
    this.closeEventSource()
    
    // Update status
    this.updateStatus('error')
    
    // Re-enable submit button
    this.submitTarget.disabled = false
  }
  
  // Close the event source
  closeEventSource() {
    if (this.eventSource) {
      this.eventSource.close()
      this.eventSource = null
    }
  }
  
  // Add a user message to the conversation history
  addUserMessage(message) {
    // Create the HTML elements
    const container = document.createElement('div')
    container.className = 'kv-message kv-message-user'
    
    const header = document.createElement('div')
    header.className = 'kv-message-header'
    header.textContent = 'User'
    
    const content = document.createElement('div')
    content.className = 'kv-message-content'
    content.textContent = message
    
    // Assemble and add to conversation
    container.appendChild(header)
    container.appendChild(content)
    
    const thread = document.getElementById('conversation-thread')
    thread.appendChild(container)
    
    // Scroll to the bottom
    if (this.hasConversationContainerTarget) {
      this.conversationContainerTarget.scrollTop = this.conversationContainerTarget.scrollHeight
    }
  }
  
  // Add an assistant message to the conversation history
  addAssistantMessage(message, sources = [], metadata = {}) {
    // Create the HTML elements with design system classes
    const container = document.createElement('div')
    container.className = 'kv-message kv-message-assistant'
    
    const header = document.createElement('div')
    header.className = 'kv-message-header'
    header.textContent = 'KnowVerse'
    
    const content = document.createElement('div')
    content.className = 'kv-message-content'
    content.textContent = message
    
    // Add the basic elements
    container.appendChild(header)
    container.appendChild(content)
    
    // Add source references if present
    if (sources && sources.length > 0) {
      const sourcesContainer = document.createElement('div')
      sourcesContainer.className = 'kv-message-sources'
      
      const sourcesList = document.createElement('div')
      sourcesList.innerHTML = 'Sources: '
      
      sources.forEach((source, index) => {
        if (index > 0) {
          sourcesList.innerHTML += ', '
        }
        
        const sourceLink = document.createElement('a')
        sourceLink.href = `/organizations/${this.getOrganizationId()}/documents/${source.id}`
        sourceLink.className = 'kv-link'
        sourceLink.textContent = source.title || `Document ${source.id}`
        sourceLink.target = '_blank'
        
        sourcesList.appendChild(sourceLink)
      })
      
      sourcesContainer.appendChild(sourcesList)
      container.appendChild(sourcesContainer)
    }
    
    // Add metrics if present
    if (metadata && metadata.metrics) {
      const metricsContainer = document.createElement('div')
      metricsContainer.className = 'kv-message-metrics'
      
      if (metadata.metrics.time_to_first_token) {
        const ttft = document.createElement('span')
        ttft.title = 'Time to first token'
        ttft.textContent = `${metadata.metrics.time_to_first_token}ms TTF`
        metricsContainer.appendChild(ttft)
      }
      
      if (metadata.metrics.tokens_per_second) {
        const tps = document.createElement('span')
        tps.title = 'Tokens per second'
        tps.textContent = `${metadata.metrics.tokens_per_second} tokens/s`
        metricsContainer.appendChild(tps)
      }
      
      container.appendChild(metricsContainer)
    }
    
    // Add to conversation thread
    const thread = document.getElementById('conversation-thread')
    thread.appendChild(container)
    
    // Scroll to the bottom
    if (this.hasConversationContainerTarget) {
      this.conversationContainerTarget.scrollTop = this.conversationContainerTarget.scrollHeight
    }
  }
  
  // Update the sources list in the UI
  updateSources(sources) {
    if (!sources || !sources.length) return
    
    // Clear current sources
    this.sourcesTarget.innerHTML = ''
    
    // Add design system class to source list
    if (!this.sourcesTarget.classList.contains('kv-sources-list')) {
      this.sourcesTarget.classList.add('kv-sources-list')
    }
    
    // Add each source to the list
    sources.forEach(source => {
      const li = document.createElement('li')
      li.dataset.sourceId = source.id
      
      const link = document.createElement('a')
      link.href = `/organizations/${this.getOrganizationId()}/documents/${source.id}`
      link.className = 'kv-link'
      link.textContent = source.title || `Document ${source.id}`
      link.target = '_blank'
      
      li.appendChild(link)
      
      // Add score if available
      if (source.score) {
        const scoreSpan = document.createElement('span')
        scoreSpan.className = 'kv-text-secondary ml-1'
        scoreSpan.textContent = `(${Math.round(source.score * 100)}% match)`
        li.appendChild(scoreSpan)
      }
      
      this.sourcesTarget.appendChild(li)
    })
    
    // Show the sources container
    this.sourcesContainerTarget.classList.remove('hidden')
  }
  
  // Update the status indicators
  updateStatus(status) {
    // Hide all status indicators
    if (this.hasWaitingTarget) this.waitingTarget.classList.add('hidden')
    if (this.hasStreamingTarget) this.streamingTarget.classList.add('hidden')
    if (this.hasCompleteTarget) this.completeTarget.classList.add('hidden')
    
    // Show the appropriate indicator
    if (status === 'waiting' && this.hasWaitingTarget) {
      this.waitingTarget.classList.remove('hidden')
    } else if (status === 'streaming' && this.hasStreamingTarget) {
      this.streamingTarget.classList.remove('hidden')
    } else if (status === 'complete' && this.hasCompleteTarget) {
      this.completeTarget.classList.remove('hidden')
    }
  }
  
  // Create a new conversation
  newConversation() {
    // Reset the conversation ID
    if (this.hasConversationIdTarget) {
      this.conversationIdTarget.value = ''
    }
    
    // Clear the conversation display
    const thread = document.getElementById('conversation-thread')
    if (thread) thread.innerHTML = ''
    
    // Clear the response
    this.responseContainerTarget.classList.add('hidden')
    if (this.hasStreamingResponseTarget) {
      this.streamingResponseTarget.textContent = ''
    }
    
    // Reset the status
    this.updateStatus('')
  }
  
  // Export the current conversation
  exportConversation() {
    const thread = document.getElementById('conversation-thread')
    if (!thread || !thread.children.length) return
    
    // Create a text version of the conversation
    let text = "# KnowVerse RAG Conversation\n\n"
    
    // Add timestamp
    text += `Exported: ${new Date().toLocaleString()}\n\n`
    
    // Get all messages
    const messages = thread.children
    for (let i = 0; i < messages.length; i++) {
      const message = messages[i]
      const role = message.querySelector('.kv-message-header').textContent
      const content = message.querySelector('.kv-message-content').textContent
      
      text += `## ${role}\n\n${content}\n\n`
      
      // Add sources if present
      const sourcesEl = message.querySelector('.kv-message-sources')
      if (sourcesEl) {
        text += `${sourcesEl.textContent}\n\n`
      }
    }
    
    // Create a blob and download link
    const blob = new Blob([text], { type: 'text/markdown' })
    const url = URL.createObjectURL(blob)
    
    const a = document.createElement('a')
    a.href = url
    a.download = `knowverse-conversation-${Date.now()}.md`
    document.body.appendChild(a)
    a.click()
    
    // Clean up
    setTimeout(() => {
      URL.revokeObjectURL(url)
      document.body.removeChild(a)
    }, 100)
  }
  
  // Provide feedback for the response
  provideFeedback(event) {
    const value = event.currentTarget.dataset.feedbackValue
    
    // Get the organization ID and conversation ID
    const organizationId = this.getOrganizationId()
    const conversationId = this.hasConversationIdTarget ? this.conversationIdTarget.value : null
    
    // Create request data
    const data = {
      feedback: {
        query: this.currentQuery,
        value: value,
        context: this.currentResponse,
        conversation_id: conversationId
      }
    }
    
    // Send feedback to server
    fetch(`/organizations/${organizationId}/search/feedbacks`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': this.getCSRFToken()
      },
      body: JSON.stringify(data)
    })
    .then(response => {
      if (response.ok) {
        // Hide feedback container
        if (this.hasFeedbackContainerTarget) {
          this.feedbackContainerTarget.classList.add('hidden')
        }
        
        // Show thank you message
        const thanksMsg = document.createElement('div')
        thanksMsg.className = 'text-sm text-green-600 text-right mt-2'
        thanksMsg.textContent = 'Thank you for your feedback!'
        
        if (this.hasFeedbackContainerTarget) {
          this.feedbackContainerTarget.parentNode.appendChild(thanksMsg)
          
          // Remove the message after a delay
          setTimeout(() => {
            if (thanksMsg.parentNode) {
              thanksMsg.parentNode.removeChild(thanksMsg)
            }
          }, 3000)
        }
      }
    })
    .catch(error => {
      console.error('Error providing feedback:', error)
    })
  }
  
  // Helper to get organization ID from URL
  getOrganizationId() {
    const match = window.location.pathname.match(/\/organizations\/(\d+)/)
    return match ? match[1] : null
  }
  
  // Helper to get CSRF token
  getCSRFToken() {
    return document.querySelector('meta[name="csrf-token"]')?.getAttribute('content')
  }
}
