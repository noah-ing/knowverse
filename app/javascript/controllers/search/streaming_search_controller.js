import { Controller } from "@hotwired/stimulus"
import { createStreamingElement } from "../../components/streaming_text_display"

/**
 * Streaming Search Controller
 * 
 * This controller implements the frontend component of the distributed vector search system.
 * It connects to the lazy-loaded backend components through Rails endpoints
 * and provides a responsive UI for vector search with domain awareness.
 * 
 * Features:
 * - Automatic connection to the distributed search backend
 * - Streaming search results with backpressure handling
 * - Domain-aware result prioritization
 * - Lazy-loading of UI components
 * - Confidence-based filtering
 * 
 * @example
 * <div data-controller="search--streaming-search"
 *      data-search--streaming-search-organization-id-value="123"
 *      data-search--streaming-search-domain-id-value="legal"
 *      data-search--streaming-search-stream-url-value="/search/streaming">
 *   <input type="search" data-search--streaming-search-target="input">
 *   <button data-action="click->search--streaming-search#search">Search</button>
 *   <div data-search--streaming-search-target="results"></div>
 *   <div data-search--streaming-search-target="status"></div>
 *   <div data-search--streaming-search-target="spinner" class="hidden">Loading...</div>
 * </div>
 */
export default class extends Controller {
  static targets = ["input", "results", "status", "spinner", "metadata", "domainSelector"]
  
  static values = { 
    organizationId: Number,
    domainId: { type: Number, default: null },
    streamUrl: String,
    debounce: { type: Number, default: 300 },
    confidenceThreshold: { type: Number, default: 0.7 },
    resultLimit: { type: Number, default: 20 },
    prefetchEnabled: { type: Boolean, default: true }
  }
  
  /**
   * Initialize controller state
   */
  connect() {
    this.isConnected = true
    this.isSearching = false
    this.eventSource = null
    this.searchQueue = []
    this.processingQueue = false
    this.searchTimeoutId = null
    this.activeQuery = null
    this.resultCount = 0
    this.responseStartTime = null
    this.streamingElement = null
    this.initialized = false
    this.initializationInProgress = false
    
    // Start component initialization
    this.initializeComponents()
    
    // Set status to ready
    this.setStatus("Ready")
  }
  
  /**
   * Clean up resources when controller disconnects
   */
  disconnect() {
    this.isConnected = false
    this.closeEventSource()
    
    if (this.searchTimeoutId) {
      clearTimeout(this.searchTimeoutId)
    }
    
    // Mark component as disconnected to abort any pending operations
    this.dispatchEvent("disconnected")
  }
  
  /**
   * Initialize the search components lazily
   */
  async initializeComponents() {
    if (this.initialized || this.initializationInProgress) {
      return
    }
    
    this.initializationInProgress = true
    this.setStatus("Initializing search components...")
    
    try {
      // Fetch component initialization data
      const response = await fetch(`/search/components/initialize?organization_id=${this.organizationIdValue || ''}&domain_id=${this.domainIdValue || ''}`)
      
      if (!response.ok) {
        throw new Error(`Failed to initialize search components: ${response.statusText}`)
      }
      
      const data = await response.json()
      
      // Store component configuration
      this.components = data.components
      this.domainOptions = data.domain_options || []
      this.prefetchData = data.prefetch_data || {}
      
      // Update domain selector if available
      if (this.hasDomainSelectorTarget && this.domainOptions.length > 0) {
        this.updateDomainSelector(this.domainOptions, data.current_domain)
      }
      
      // Initialize event handlers
      this.setupEventHandlers()
      
      // Set ready flag
      this.initialized = true
      this.initializationInProgress = false
      
      // Update status
      this.setStatus("Ready")
      
      // Dispatch initialized event
      this.dispatchEvent("initialized", { 
        detail: { 
          components: this.components,
          domainOptions: this.domainOptions
        }
      })
    } catch (error) {
      console.error("Error initializing search components:", error)
      this.initializationInProgress = false
      this.setStatus(`Initialization error: ${error.message}`)
    }
  }
  
  /**
   * Set up event handlers
   */
  setupEventHandlers() {
    // Throttle input changes
    if (this.hasInputTarget) {
      this.inputTarget.addEventListener("input", this.debounce(() => {
        if (this.inputTarget.value.trim().length > 2) {
          this.search()
        }
      }, this.debounceValue))
    }
    
    // Domain change handling
    if (this.hasDomainSelectorTarget) {
      this.domainSelectorTarget.addEventListener("change", this.handleDomainChange.bind(this))
    }
  }
  
  /**
   * Handle domain selector change
   */
  handleDomainChange(event) {
    const domainId = parseInt(event.target.value, 10)
    
    if (domainId !== this.domainIdValue) {
      this.domainIdValue = domainId
      
      // Clear existing results
      this.clearResults()
      
      // Reinitialize with new domain
      this.initialized = false
      this.initializeComponents()
      
      // Dispatch domain change event
      this.dispatchEvent("domainChanged", { detail: { domainId } })
    }
  }
  
  /**
   * Perform a search with the current input value
   * @param {Event} event - Optional event object
   */
  search(event) {
    // Prevent form submission if triggered by a form
    if (event) {
      event.preventDefault()
    }
    
    // Initialize components if needed
    if (!this.initialized && !this.initializationInProgress) {
      this.initializeComponents().then(() => {
        this.search()
      })
      return
    }
    
    // Get query from input
    const query = this.inputTarget.value.trim()
    if (!query) {
      this.setStatus("Please enter a search query")
      return
    }
    
    // Clear any pending search timeout
    if (this.searchTimeoutId) {
      clearTimeout(this.searchTimeoutId)
      this.searchTimeoutId = null
    }
    
    // If already searching, add to queue with backpressure handling
    if (this.isSearching) {
      // Add to queue, but only if it's a new query
      if (!this.searchQueue.includes(query)) {
        this.searchQueue.push(query)
        this.setStatus(`Search queued (${this.searchQueue.length} pending)`)
      }
      return
    }
    
    // Start search after debounce
    this.searchTimeoutId = setTimeout(() => {
      this.startStreaming(query)
    }, this.debounceValue)
  }
  
  /**
   * Force an immediate search (skip debounce)
   */
  searchNow() {
    if (this.searchTimeoutId) {
      clearTimeout(this.searchTimeoutId)
      this.searchTimeoutId = null
    }
    
    const query = this.inputTarget.value.trim()
    if (query) {
      this.startStreaming(query)
    }
  }
  
  /**
   * Cancel the current search
   */
  cancel() {
    this.closeEventSource()
    this.isSearching = false
    this.hideSpinner()
    this.setStatus("Search cancelled")
    
    // Process next search if any
    this.processQueue()
  }
  
  /**
   * Start streaming search results
   * @param {string} query - The search query
   */
  startStreaming(query) {
    if (!this.initialized) {
      this.initializeComponents().then(() => {
        this.startStreaming(query)
      })
      return
    }
    
    this.isSearching = true
    this.showSpinner()
    this.clearResults()
    this.setStatus("Searching...")
    this.activeQuery = query
    this.resultCount = 0
    this.responseStartTime = performance.now()
    
    // Construct streaming URL with domain awareness
    const url = new URL(this.streamUrlValue, window.location.origin)
    const params = {
      query: query,
      organization_id: this.organizationIdValue || '',
      domain_id: this.domainIdValue || '',
      confidence: this.confidenceThresholdValue,
      limit: this.resultLimitValue
    }
    
    // Add params to URL
    Object.keys(params).forEach(key => {
      if (params[key] !== null && params[key] !== undefined) {
        url.searchParams.append(key, params[key])
      }
    })
    
    // Close existing connection if any
    this.closeEventSource()
    
    try {
      // Create new streaming connection
      this.eventSource = new EventSource(url.toString())
      
      // Set up event handlers with backpressure handling
      this.eventSource.onmessage = this.handleMessage.bind(this)
      this.eventSource.onerror = this.handleError.bind(this)
      
      // Handle stream completion
      this.eventSource.addEventListener("search_complete", this.handleCompletion.bind(this))
      this.eventSource.addEventListener("error", this.handleStreamError.bind(this))
      
      // Record that we've started searching
      this.dispatchEvent("searchStarted", { 
        detail: { 
          query, 
          domainId: this.domainIdValue,
          timestamp: new Date().toISOString()
        }
      })
    } catch (error) {
      this.handleError(error)
    }
  }
  
  /**
   * Handle incoming message from server
   * @param {MessageEvent} event - The message event
   */
  handleMessage(event) {
    // Parse data from event
    let data
    try {
      data = JSON.parse(event.data)
    } catch (error) {
      console.error("Error parsing streaming data:", error)
      return
    }
    
    // Create or update streaming element
    if (!this.streamingElement) {
      this.streamingElement = createStreamingElement(this.resultsTarget)
    }
    
    // Add content to streaming element with appropriate rendering
    if (data.results && data.results.length > 0) {
      data.results.forEach(result => {
        this.appendSearchResult(result)
        this.resultCount++
      })
    }
    
    // Update metadata display if available
    if (data.metadata && this.hasMetadataTarget) {
      this.updateMetadata(data.metadata)
    }
  }
  
  /**
   * Handle error from EventSource
   * @param {Event} event - The error event
   */
  handleError(event) {
    console.error("Streaming error:", event)
    this.setStatus("Error connecting to search service")
    this.isSearching = false
    this.closeEventSource()
    this.hideSpinner()
    this.processQueue()
    
    // Dispatch error event
    this.dispatchEvent("searchError", { 
      detail: { 
        query: this.activeQuery,
        error: event.message || "Connection error"
      }
    })
  }
  
  /**
   * Handle error message from stream
   * @param {MessageEvent} event - The error message event
   */
  handleStreamError(event) {
    let data
    try {
      data = JSON.parse(event.data)
    } catch (error) {
      console.error("Error parsing error data:", error)
      return
    }
    
    this.setStatus(`Error: ${data.message || "Unknown error"}`)
    this.isSearching = false
    this.closeEventSource()
    this.hideSpinner()
    this.processQueue()
    
    // Dispatch error event
    this.dispatchEvent("searchError", { 
      detail: { 
        query: this.activeQuery,
        error: data.message || "Stream error",
        data: data
      }
    })
  }
  
  /**
   * Handle search completion
   * @param {MessageEvent} event - The completion event
   */
  handleCompletion(event) {
    // Parse completion data
    let data
    try {
      data = JSON.parse(event.data)
    } catch (error) {
      console.error("Error parsing completion data:", error)
      return
    }
    
    // Update UI with completion information
    if (data.summary) {
      this.displaySearchSummary(data.summary)
    }
    
    // Clean up and prepare for next search
    this.isSearching = false
    this.hideSpinner()
    this.closeEventSource()
    
    // Calculate response time
    const responseTimeMs = Math.round(performance.now() - this.responseStartTime)
    
    // Show completion status
    this.setStatus(`Search complete (${responseTimeMs}ms)`)
    
    // Dispatch completion event
    this.dispatchEvent("searchComplete", { 
      detail: { 
        query: this.activeQuery,
        resultCount: this.resultCount,
        responseTimeMs: responseTimeMs,
        summary: data.summary
      }
    })
    
    // Process any queued searches
    this.processQueue()
  }
  
  /**
   * Process the next search in the queue
   */
  processQueue() {
    if (this.processingQueue || this.searchQueue.length === 0) return
    
    this.processingQueue = true
    
    // Get next search from queue
    const nextSearch = this.searchQueue.shift()
    
    // Process with small delay to allow UI to update
    setTimeout(() => {
      this.inputTarget.value = nextSearch
      this.startStreaming(nextSearch)
      this.processingQueue = false
    }, 100)
  }
  
  /**
   * Append a search result to the results container
   * @param {Object} result - The search result object
   */
  appendSearchResult(result) {
    if (!result) return
    
    // Create result element
    const resultEl = document.createElement("div")
    resultEl.classList.add("search-result", "vector-search-result", "mb-4", "p-4", "border", "rounded")
    
    // Make it visible immediately but with animation
    resultEl.style.opacity = "0"
    resultEl.style.transform = "translateY(10px)"
    
    // Add title
    const titleEl = document.createElement("h3")
    titleEl.classList.add("text-lg", "font-bold", "mb-2")
    titleEl.textContent = result.title || `Result ${result.id}`
    resultEl.appendChild(titleEl)
    
    // Add content
    const contentEl = document.createElement("div")
    contentEl.classList.add("text-sm")
    contentEl.textContent = result.text
    resultEl.appendChild(contentEl)
    
    // Add confidence score with visual indicator
    const scoreContainer = document.createElement("div")
    scoreContainer.classList.add("flex", "items-center", "mt-2")
    
    // Confidence bar
    const confidenceBar = document.createElement("div")
    confidenceBar.classList.add("domain-model-confidence", "flex-grow", "mr-2")
    const confidenceScore = result.confidence || 0
    confidenceBar.style.width = `${confidenceScore * 100}%`
    
    // Score text
    const scoreEl = document.createElement("div")
    scoreEl.classList.add("text-xs", "text-gray-500")
    scoreEl.textContent = `Confidence: ${(confidenceScore * 100).toFixed(1)}%`
    
    // Add to container
    scoreContainer.appendChild(confidenceBar)
    scoreContainer.appendChild(scoreEl)
    resultEl.appendChild(scoreContainer)
    
    // Add source/metadata if available
    if (result.metadata) {
      const metaEl = document.createElement("div")
      metaEl.classList.add("text-xs", "text-gray-500", "mt-1")
      metaEl.textContent = result.metadata.source || "Unknown source"
      resultEl.appendChild(metaEl)
    }
    
    // Add result to container
    this.resultsTarget.appendChild(resultEl)
    
    // Animate in with setTimeout to ensure DOM updated
    setTimeout(() => {
      resultEl.style.transition = "opacity 0.3s ease, transform 0.3s ease"
      resultEl.style.opacity = "1"
      resultEl.style.transform = "translateY(0)"
    }, 10)
    
    // Scroll to bottom if many results
    if (this.resultCount > 5) {
      resultEl.scrollIntoView({ behavior: "smooth", block: "nearest" })
    }
  }
  
  /**
   * Update metadata display
   * @param {Object} metadata - The metadata object
   */
  updateMetadata(metadata) {
    if (!this.hasMetadataTarget) return
    
    const metadataEl = this.metadataTarget
    metadataEl.innerHTML = ''
    
    // Create a metadata items list
    const metaItems = [
      { label: "Domain", value: metadata.domain || 'general' },
      { label: "Model", value: metadata.model_used || 'default' },
      { label: "Vector dimensions", value: metadata.dimensions || 'unknown' }
    ]
    
    // Add each item to metadata display
    metaItems.forEach(item => {
      const itemEl = document.createElement("div")
      itemEl.classList.add("text-xs", "mr-3")
      itemEl.innerHTML = `<span class="text-gray-500">${item.label}:</span> ${item.value}`
      metadataEl.appendChild(itemEl)
    })
  }
  
  /**
   * Display search summary at the end of results
   * @param {Object} summary - The summary object
   */
  displaySearchSummary(summary) {
    const summaryEl = document.createElement("div")
    summaryEl.classList.add("search-summary", "mt-4", "text-sm", "text-gray-500", "border-t", "pt-2")
    
    const resultCount = summary.result_count || this.resultCount
    const timeMs = summary.time_ms || Math.round(performance.now() - this.responseStartTime)
    const modelName = summary.model_name || "default model"
    
    summaryEl.textContent = `Found ${resultCount} results in ${timeMs}ms using ${modelName}`
    
    // Add any additional summary information
    if (summary.additional_info) {
      const additionalEl = document.createElement("div")
      additionalEl.classList.add("text-xs", "mt-1")
      additionalEl.textContent = summary.additional_info
      summaryEl.appendChild(additionalEl)
    }
    
    this.resultsTarget.appendChild(summaryEl)
  }
  
  /**
   * Update the domain selector dropdown
   * @param {Array} domains - The array of domain options
   * @param {Object} currentDomain - The current domain object
   */
  updateDomainSelector(domains, currentDomain) {
    if (!this.hasDomainSelectorTarget) return
    
    const selector = this.domainSelectorTarget
    selector.innerHTML = "" // Clear existing options
    
    // Add domains as options
    domains.forEach(domain => {
      const option = document.createElement("option")
      option.value = domain.id
      option.textContent = domain.name || `Domain ${domain.id}`
      option.selected = currentDomain && domain.id === currentDomain.id
      selector.appendChild(option)
    })
    
    // Set current domain value
    if (currentDomain) {
      this.domainIdValue = currentDomain.id
    }
  }
  
  /**
   * Set status message
   * @param {string} message - The status message
   */
  setStatus(message) {
    if (!this.hasStatusTarget) return
    this.statusTarget.textContent = message
  }
  
  /**
   * Clean up EventSource
   */
  closeEventSource() {
    if (this.eventSource) {
      this.eventSource.close()
      this.eventSource = null
    }
  }
  
  /**
   * Clear results container
   */
  clearResults() {
    if (!this.hasResultsTarget) return
    
    this.resultsTarget.innerHTML = ""
    this.streamingElement = null
    
    // Reset result count
    this.resultCount = 0
  }
  
  /**
   * Show loading spinner
   */
  showSpinner() {
    if (!this.hasSpinnerTarget) return
    this.spinnerTarget.classList.remove("hidden")
  }
  
  /**
   * Hide loading spinner
   */
  hideSpinner() {
    if (!this.hasSpinnerTarget) return
    this.spinnerTarget.classList.add("hidden")
  }
  
  /**
   * Helper to dispatch custom events
   */
  dispatchEvent(name, detail = {}) {
    const event = new CustomEvent(`streaming-search:${name}`, detail)
    this.element.dispatchEvent(event)
  }
  
  /**
   * Helper to create a debounced function
   */
  debounce(func, wait) {
    let timeout
    return (...args) => {
      clearTimeout(timeout)
      timeout = setTimeout(() => func.apply(this, args), wait)
    }
  }
}
