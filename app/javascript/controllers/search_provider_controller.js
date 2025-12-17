import { Controller } from "@hotwired/stimulus"

// This controller manages the search provider selection UI
export default class extends Controller {
  static targets = ["methodSelect", "form", "providerDisplay", "latencyDisplay"]
  static values = {
    defaultMethod: String,
    lastMethod: String,
    lastDuration: Number
  }
  
  connect() {
    console.log("Search Provider Controller connected")
    
    // Set default method if provided
    if (this.hasDefaultMethodValue && this.hasMethodSelectTarget) {
      this.methodSelectTarget.value = this.defaultMethodValue
    }
    
    // Update provider display if last method is available
    if (this.hasLastMethodValue && this.hasProviderDisplayTarget) {
      this.updateProviderDisplay(this.lastMethodValue)
    }
    
    // Update latency display if available
    if (this.hasLastDurationValue && this.hasLatencyDisplayTarget) {
      this.updateLatencyDisplay(this.lastDurationValue)
    }
  }
  
  // Handle search provider change
  changeProvider(event) {
    const provider = event.target.value
    this.updateProviderDisplay(provider)
    
    // If form exists, update the hidden field
    if (this.hasFormTarget) {
      const hiddenField = this.formTarget.querySelector('input[name="search_method"]')
      if (hiddenField) {
        hiddenField.value = provider
      }
    }
  }
  
  // Update the provider display
  updateProviderDisplay(provider) {
    if (!this.hasProviderDisplayTarget) return
    
    // Update display based on provider
    let displayText = "Default Search"
    let badgeClass = "bg-gray-100 text-gray-800"
    
    switch (provider) {
      case "hybrid":
        displayText = "Hybrid Search"
        badgeClass = "bg-purple-100 text-purple-800"
        break
      case "pgvector_cosine":
        displayText = "Vector Cosine"
        badgeClass = "bg-blue-100 text-blue-800"
        break
      case "pgvector_l2":
        displayText = "Vector Euclidean"
        badgeClass = "bg-cyan-100 text-cyan-800"
        break
      case "hnsw":
        displayText = "SIMD HNSW"
        badgeClass = "bg-green-100 text-green-800"
        break
      case "haystack":
        displayText = "Haystack Service"
        badgeClass = "bg-indigo-100 text-indigo-800"
        break
    }
    
    // Update the display text
    this.providerDisplayTarget.textContent = displayText
    
    // Update badge class (remove old classes and add new ones)
    this.providerDisplayTarget.className = `inline-flex items-center px-2.5 py-0.5 rounded-md text-sm font-medium ${badgeClass}`
  }
  
  // Update latency display
  updateLatencyDisplay(duration) {
    if (!this.hasLatencyDisplayTarget) return
    
    // Convert ms to seconds for display
    const seconds = (duration / 1000).toFixed(3)
    this.latencyDisplayTarget.textContent = `${seconds} seconds`
    
    // Add color coding based on duration
    if (duration < 10) { // < 10ms - excellent
      this.latencyDisplayTarget.className = "text-green-600 font-medium"
    } else if (duration < 50) { // 10-50ms - good
      this.latencyDisplayTarget.className = "text-green-500"
    } else if (duration < 200) { // 50-200ms - acceptable
      this.latencyDisplayTarget.className = "text-yellow-600" 
    } else { // > 200ms - slow
      this.latencyDisplayTarget.className = "text-red-500"
    }
  }
}
