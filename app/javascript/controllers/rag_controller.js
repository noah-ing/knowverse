import { Controller } from "@hotwired/stimulus"
import { createStreamingElement } from "components/streaming_text_display"

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
    "floatingMetrics", "floatingTtft", "floatingTps", "floatingTokens", "floatingTime",
    "chatContainer", "userMessageContainer", "userMessageText"
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

  // Auto-resize textarea based on content
  autoResize(event) {
    const textarea = event.target

    // Reset height to auto to get the proper scroll height
    textarea.style.height = 'auto'

    // Calculate new height (capped at max-height set in CSS)
    const newHeight = Math.min(textarea.scrollHeight, 120)
    textarea.style.height = `${newHeight}px`
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
    
    // Show the response container and clear any previous response
    this.responseContainerTarget.classList.remove('hidden')
    if (this.hasStreamingResponseTarget) {
      this.streamingResponseTarget.textContent = ''
    }

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
      // Clear the display for next message
      this.streamingDisplay.clear()
    }
    
    // Always use streaming for RAG
    // Note: We always use streaming because RAG responses benefit from immediate feedback
    console.log('Starting streaming request for query:', this.currentQuery)
    this.startStreaming(formData)
    
    // Disable submit button during processing
    this.submitTarget.disabled = true
    
    return false
  }
  
  // Initialize the streaming text display component
  initStreamingDisplay() {
    // Create streaming display with our design system classes
    this.streamingDisplay = createStreamingElement(this.streamingResponseTarget, {
      typingSpeed: 20, // ms per token (lower = faster)
      cursorBlink: true,
      className: 'kv-streaming-text'
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
    console.log('Creating EventSource with URL:', url)
    this.eventSource = new EventSource(url)
    console.log('EventSource created, readyState:', this.eventSource.readyState)

    // Log when connection opens
    this.eventSource.onopen = (event) => {
      console.log('EventSource connection opened', event)
    }

    // Reset streaming state
    this.isStreaming = true
    this.currentResponse = ""
    this.sourceReferences = []
    this.lastEventId = 0
    
    // Handle all messages - SSE sends generic 'message' events with type in JSON
    this.eventSource.onmessage = (event) => {
      try {
        const data = JSON.parse(event.data)
        console.log('SSE event:', data.type, data)

        switch (data.type) {
          case 'token':
            this.handleToken({ data: event.data })
            break
          case 'context':
            // Context event with documents and conversation_id
            console.log('Context received:', data.documents?.length || 0, 'documents')
            // Save conversation_id for follow-up messages
            if (data.conversation_id && this.hasConversationIdTarget) {
              this.conversationIdTarget.value = data.conversation_id
              console.log('Conversation ID from context:', data.conversation_id)
            }
            // Extract sources from documents in context (for early display)
            if (data.documents && data.documents.length > 0) {
              this.sourceReferences = data.documents.map(doc => ({
                id: doc.id || doc.document_id,
                title: doc.title || doc.meta?.title || doc.filename || `Document ${doc.id || doc.document_id}`,
                score: doc.score
              }))
              this.updateSources(this.sourceReferences)
              console.log('Sources extracted from context:', this.sourceReferences.length)
            }
            break
          case 'sources':
            this.handleSources({ data: event.data })
            break
          case 'metadata':
            this.handleMetadata({ data: event.data })
            break
          case 'complete':
            this.handleStreamingComplete({ data: event.data })
            // Close EventSource on completion to prevent reconnect
            this.closeEventSource()
            break
          case 'error':
            console.error('Server error:', data)
            this.handleStreamingError(event)
            this.closeEventSource()
            break
          default:
            console.log('Unknown event type:', data.type)
        }
      } catch (e) {
        console.error('Failed to parse SSE data:', e, event.data)
      }
    }

    // Handle EventSource connection errors (not server-sent errors)
    this.eventSource.onerror = (event) => {
      // Guard against null eventSource (can happen if closed during error handling)
      if (!this.eventSource) {
        console.log('EventSource already closed, ignoring error')
        return
      }
      // Only handle as error if we're not just completing
      if (this.eventSource.readyState === EventSource.CLOSED) {
        console.log('EventSource closed normally')
        return
      }
      console.error('EventSource error:', event, 'readyState:', this.eventSource?.readyState)
      this.handleStreamingError(event)
    }
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

    // Token content comes as 'content' from SSE
    const token = data.content || data.token || ''

    // Check for sequential order using index
    if (data.index) {
      if (this.lastEventId + 1 !== data.index) {
        console.warn(`Token out of order, expected ${this.lastEventId + 1}, got ${data.index}`)
      }
      this.lastEventId = data.index
    }

    // Add to current response
    this.currentResponse += token

    // Append token directly to response element with metric highlighting
    if (this.hasStreamingResponseTarget) {
      this.streamingResponseTarget.innerHTML = this.formatStreamingText(this.currentResponse)
    }

    // Hide cursor while actively streaming
    if (this.hasStreamingCursorTarget) {
      this.streamingCursorTarget.classList.remove('hidden')
    }
  }

  // Format streaming text with metric highlighting (simpler than full markdown for perf)
  formatStreamingText(text) {
    if (!text) return ''
    return this.escapeHtml(text)
      // Highlight key metrics: percentages, dollar amounts, and numbers with units
      .replace(/(\d+(?:\.\d+)?%)/g, '<span class="text-indigo-600 font-medium">$1</span>')
      .replace(/(\$\d+(?:,\d{3})*(?:\.\d+)?(?:M|K|B)?)/gi, '<span class="text-indigo-600 font-medium">$1</span>')
      .replace(/(\d+(?:\.\d+)?x\b)/gi, '<span class="text-indigo-600 font-medium">$1</span>')
      .replace(/\n/g, '<br>')
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

    // Store references for highlighting (now with chunk-level data)
    this.sourceReferences = data.sources || []
    this.citationMappings = data.citations || []

    // Insert citation markers into the response text
    if (this.citationMappings.length > 0 && this.hasStreamingResponseTarget) {
      this.insertCitationMarkers()
    }

    // Update UI with source list (chunk-level)
    this.updateSources(this.sourceReferences)

    // Register hover events for citation highlighting
    setTimeout(() => {
      // Add source references to text display for highlighting
      if (this.streamingDisplay) {
        this.streamingDisplay.addSourceReferences(this.sourceReferences)
      }

      // Add hover effects for citation markers
      this.setupCitationHovers()
    }, 100)
  }

  // Insert [1] [2] citation markers into the response text
  insertCitationMarkers() {
    if (!this.citationMappings || !this.citationMappings.length) return

    let html = this.streamingResponseTarget.innerHTML

    // Sort citations by position (reverse order to insert from end)
    const sortedCitations = [...this.citationMappings].sort(
      (a, b) => (b.sentence_end || 0) - (a.sentence_end || 0)
    )

    // Insert markers at each citation point
    for (const citation of sortedCitations) {
      const indices = citation.source_indices || []
      if (indices.length === 0) continue

      // Create citation marker HTML
      const markers = indices.map(idx => {
        const source = this.sourceReferences[idx - 1]
        const preview = source?.content_preview || ''
        const title = source?.title || `Source ${idx}`
        const docId = source?.document_id || source?.id
        const chunkIdx = source?.chunk_index

        return `<span class="citation-marker" data-citation-idx="${idx}" data-doc-id="${docId}" data-chunk-idx="${chunkIdx}">
          <a href="#" class="text-indigo-600 hover:text-indigo-800 font-medium text-sm">[${idx}]</a>
          <div class="citation-popover hidden absolute z-50 w-72 p-3 bg-white rounded-lg shadow-lg border border-gray-200 text-sm">
            <p class="font-medium text-gray-900 mb-1">${title}</p>
            ${chunkIdx !== null && chunkIdx !== undefined ? `<p class="text-xs text-gray-500 mb-2">Chunk ${chunkIdx + 1}</p>` : ''}
            <p class="text-gray-600 text-xs leading-relaxed">${preview}</p>
            <a href="/organizations/${this.getOrganizationId()}/documents/${docId}${chunkIdx !== null && chunkIdx !== undefined ? `#chunk-${chunkIdx}` : ''}"
               target="_blank"
               class="inline-block mt-2 text-xs text-indigo-600 hover:text-indigo-800">
              View in document →
            </a>
          </div>
        </span>`
      }).join(' ')

      // Find sentence end position and insert
      // We need to convert text position to HTML position (approximate)
      const sentenceEnd = citation.sentence_end || 0
      const textUpToEnd = this.currentResponse.substring(0, sentenceEnd)

      // Find the corresponding position in rendered text
      // Look for the last punctuation mark near that position
      const searchText = textUpToEnd.slice(-50)
      const punctMatch = searchText.match(/[.!?](?=[^.!?]*$)/)

      if (punctMatch) {
        const insertPos = html.lastIndexOf(punctMatch[0]) + 1
        if (insertPos > 0 && insertPos < html.length) {
          html = html.slice(0, insertPos) + ' ' + markers + html.slice(insertPos)
        }
      }
    }

    this.streamingResponseTarget.innerHTML = html
  }

  // Setup hover events for citation popovers
  setupCitationHovers() {
    const markers = document.querySelectorAll('.citation-marker')

    markers.forEach(marker => {
      const popover = marker.querySelector('.citation-popover')
      if (!popover) return

      marker.addEventListener('mouseenter', () => {
        // Position popover
        const rect = marker.getBoundingClientRect()
        popover.style.top = `${rect.height + 5}px`
        popover.style.left = '0'
        popover.classList.remove('hidden')

        // Highlight corresponding source pill
        const idx = marker.dataset.citationIdx
        this.highlightSourcePill(idx)
      })

      marker.addEventListener('mouseleave', () => {
        popover.classList.add('hidden')
        this.clearSourcePillHighlight()
      })

      // Prevent link click from navigating (let popover link handle it)
      marker.querySelector('a').addEventListener('click', (e) => {
        e.preventDefault()
      })
    })
  }

  // Highlight source pill by citation index
  highlightSourcePill(idx) {
    const pills = this.sourcesTarget.querySelectorAll('.source-pill')
    pills.forEach(pill => {
      if (pill.dataset.citationIdx === idx) {
        pill.classList.add('ring-2', 'ring-indigo-500', 'bg-indigo-50')
      }
    })
  }

  // Clear source pill highlights
  clearSourcePillHighlight() {
    const pills = this.sourcesTarget.querySelectorAll('.source-pill')
    pills.forEach(pill => {
      pill.classList.remove('ring-2', 'ring-indigo-500', 'bg-indigo-50')
    })
  }
  
  // Handle metadata event
  handleMetadata(event) {
    const data = JSON.parse(event.data)
    console.log('Metadata:', data)
    // Store metadata for potential use
    this.streamingMetadata = data

    // Update conversation_id for follow-up messages
    if (data.conversation_id && this.hasConversationIdTarget) {
      this.conversationIdTarget.value = data.conversation_id
      console.log('Conversation ID updated:', data.conversation_id)
    }
  }
  
  // Handle streaming complete
  handleStreamingComplete(event) {
    // Mark streaming as done
    this.isStreaming = false

    // Close the event source
    this.closeEventSource()

    // Parse complete event data if available
    let completeData = {}
    if (event.data) {
      try {
        completeData = JSON.parse(event.data)
        // Update conversation_id for follow-up messages
        if (completeData.conversation_id && this.hasConversationIdTarget) {
          this.conversationIdTarget.value = completeData.conversation_id
          console.log('Conversation ID from complete event:', completeData.conversation_id)
        }
        // Extract sources from complete event if present (and we don't already have them)
        if (completeData.sources && completeData.sources.length > 0 && this.sourceReferences.length === 0) {
          this.sourceReferences = completeData.sources
          this.updateSources(this.sourceReferences)
          console.log('Sources from complete event:', this.sourceReferences.length)
        }
      } catch (e) {
        console.warn('Could not parse complete event data:', e)
      }
    }

    // Hide the cursor
    if (this.hasStreamingCursorTarget) {
      this.streamingCursorTarget.classList.add('hidden')
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

    console.log('Streaming complete. Response:', this.currentResponse.substring(0, 100))
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
    // Hide the welcome message if present
    const welcomeMessage = this.chatContainerTarget.querySelector('.flex.justify-center.py-8')
    if (welcomeMessage) {
      welcomeMessage.remove()
    }

    // Create user message element and add to chat container
    const userDiv = document.createElement('div')
    userDiv.className = 'flex justify-end mb-4'
    userDiv.innerHTML = `
      <div class="max-w-[80%] bg-indigo-600 text-white rounded-2xl rounded-br-md px-4 py-3 shadow-sm">
        <p class="text-sm leading-relaxed">${this.escapeHtml(message)}</p>
      </div>
    `

    // Insert before the streaming response container
    if (this.hasResponseContainerTarget) {
      this.chatContainerTarget.insertBefore(userDiv, this.responseContainerTarget)
    } else {
      this.chatContainerTarget.appendChild(userDiv)
    }

    // Show the streaming response container for the assistant's reply
    if (this.hasResponseContainerTarget) {
      this.responseContainerTarget.classList.remove('hidden')
    }

    // Scroll to bottom
    this.scrollToBottom()
  }

  // Add an assistant message to the conversation history
  addAssistantMessage(message, sources = [], metadata = {}) {
    // Create assistant message element
    const assistantDiv = document.createElement('div')
    assistantDiv.className = 'flex justify-start mb-4'

    // Build sources HTML if present (matching homepage preview pill style)
    let sourcesHtml = ''
    if (sources && sources.length > 0) {
      const orgId = this.getOrganizationId()
      const sourceSpans = sources.map(s => {
        const href = s.id ? `/organizations/${orgId}/documents/${s.id}` : '#'
        return `<a href="${href}" target="_blank" class="text-xs bg-white px-2 py-0.5 rounded-full text-gray-600 hover:bg-gray-50 hover:text-indigo-600 transition-colors border border-gray-100">${this.escapeHtml(s.title || 'Document')}</a>`
      }).join('')
      sourcesHtml = `
        <div class="mt-3 pt-2 border-t border-gray-200">
          <p class="text-xs text-gray-500 mb-1">Sources:</p>
          <div class="flex flex-wrap gap-1">${sourceSpans}</div>
        </div>
      `
    }

    assistantDiv.innerHTML = `
      <div class="max-w-[80%] bg-gray-100 text-gray-900 rounded-2xl rounded-bl-md px-4 py-3 shadow-sm">
        <div class="flex items-center gap-2 mb-1">
          <span class="text-xs font-medium text-indigo-600">KnowVerse</span>
        </div>
        <div class="text-sm leading-relaxed prose prose-sm max-w-none">${this.formatMarkdown(message)}</div>
        ${sourcesHtml}
      </div>
    `

    // Insert before the streaming response container
    if (this.hasResponseContainerTarget) {
      this.chatContainerTarget.insertBefore(assistantDiv, this.responseContainerTarget)
    } else {
      this.chatContainerTarget.appendChild(assistantDiv)
    }

    // Hide and reset the streaming response container for next message
    if (this.hasResponseContainerTarget) {
      this.responseContainerTarget.classList.add('hidden')
    }
    if (this.hasStreamingResponseTarget) {
      this.streamingResponseTarget.textContent = ''
    }
    if (this.hasUserMessageContainerTarget) {
      this.userMessageContainerTarget.classList.add('hidden')
    }

    // Scroll to bottom
    this.scrollToBottom()
  }

  // Scroll chat container to bottom
  scrollToBottom() {
    if (this.hasChatContainerTarget) {
      setTimeout(() => {
        this.chatContainerTarget.scrollTop = this.chatContainerTarget.scrollHeight
      }, 100)
    }
  }

  // Escape HTML to prevent XSS
  escapeHtml(text) {
    const div = document.createElement('div')
    div.textContent = text
    return div.innerHTML
  }

  // Simple markdown formatting (bold, italic, code, links) + metric highlighting
  formatMarkdown(text) {
    if (!text) return ''
    return this.escapeHtml(text)
      .replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>')
      .replace(/\*(.+?)\*/g, '<em>$1</em>')
      .replace(/`(.+?)`/g, '<code class="bg-gray-200 px-1 rounded">$1</code>')
      // Highlight key metrics: percentages, dollar amounts, and numbers with units
      .replace(/(\d+(?:\.\d+)?%)/g, '<span class="text-indigo-600 font-medium">$1</span>')
      .replace(/(\$\d+(?:,\d{3})*(?:\.\d+)?(?:M|K|B)?)/gi, '<span class="text-indigo-600 font-medium">$1</span>')
      .replace(/(\d+(?:\.\d+)?x\b)/gi, '<span class="text-indigo-600 font-medium">$1</span>')
      .replace(/\n/g, '<br>')
  }
  
  // Update the sources list in the UI
  updateSources(sources) {
    if (!sources || !sources.length) return

    // Clear current sources
    this.sourcesTarget.innerHTML = ''

    // Style as flex wrap container for pills
    this.sourcesTarget.className = 'flex flex-wrap gap-2'

    // Add each source as a pill with citation number (chunk-level)
    sources.forEach((source, index) => {
      const citationIdx = source.citation_index || (index + 1)
      const docId = source.document_id || source.id
      const chunkIdx = source.chunk_index
      const title = source.title || `Document ${docId}`
      const preview = source.content_preview || ''

      const pill = document.createElement('div')
      pill.className = 'source-pill relative inline-flex items-center gap-1 bg-white px-2 py-1 rounded-lg text-gray-600 hover:bg-gray-50 transition-colors cursor-pointer border border-gray-200 group'
      pill.dataset.citationIdx = String(citationIdx)
      pill.dataset.sourceId = docId

      // Citation number badge
      const badge = document.createElement('span')
      badge.className = 'flex items-center justify-center w-5 h-5 bg-indigo-100 text-indigo-700 text-xs font-medium rounded-full'
      badge.textContent = citationIdx

      // Title text
      const titleSpan = document.createElement('span')
      titleSpan.className = 'text-xs truncate max-w-[150px]'
      titleSpan.textContent = title
      if (chunkIdx !== null && chunkIdx !== undefined) {
        titleSpan.textContent += ` (chunk ${chunkIdx + 1})`
      }

      // Link to document
      const link = document.createElement('a')
      link.href = `/organizations/${this.getOrganizationId()}/documents/${docId}${chunkIdx !== null && chunkIdx !== undefined ? `#chunk-${chunkIdx}` : ''}`
      link.target = '_blank'
      link.className = 'text-gray-400 hover:text-indigo-600'
      link.innerHTML = '<svg class="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14" /></svg>'
      link.title = 'View in document'

      // Popover for preview
      const popover = document.createElement('div')
      popover.className = 'absolute bottom-full left-0 mb-2 w-64 p-3 bg-white rounded-lg shadow-lg border border-gray-200 text-sm opacity-0 invisible group-hover:opacity-100 group-hover:visible transition-all z-50'
      popover.innerHTML = `
        <p class="font-medium text-gray-900 mb-1">${title}</p>
        ${chunkIdx !== null && chunkIdx !== undefined ? `<p class="text-xs text-gray-500 mb-2">Chunk ${chunkIdx + 1}${source.total_chunks ? ` of ${source.total_chunks}` : ''}</p>` : ''}
        <p class="text-gray-600 text-xs leading-relaxed line-clamp-3">${preview}</p>
      `

      pill.appendChild(badge)
      pill.appendChild(titleSpan)
      pill.appendChild(link)
      pill.appendChild(popover)

      // Add hover highlight for corresponding citation markers
      pill.addEventListener('mouseenter', () => {
        document.querySelectorAll(`.citation-marker[data-citation-idx="${citationIdx}"]`).forEach(marker => {
          marker.classList.add('bg-indigo-100', 'rounded')
        })
      })
      pill.addEventListener('mouseleave', () => {
        document.querySelectorAll('.citation-marker').forEach(marker => {
          marker.classList.remove('bg-indigo-100', 'rounded')
        })
      })

      this.sourcesTarget.appendChild(pill)
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
