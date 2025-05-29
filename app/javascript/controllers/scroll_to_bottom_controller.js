import { Controller } from "@hotwired/stimulus"

// Scroll to bottom controller for conversation interfaces
export default class extends Controller {
  connect() {
    console.log("ScrollToBottom controller connected")
    
    // Scroll to bottom on initial load
    this.scrollToBottom()
    
    // Create an observer to watch for changes to child elements
    this.createObserver()
  }
  
  disconnect() {
    // Disconnect observer when controller is disconnected
    if (this.observer) {
      this.observer.disconnect()
    }
  }
  
  // Scroll the container to the bottom
  scrollToBottom() {
    // Use timeout to ensure this happens after DOM updates
    setTimeout(() => {
      this.element.scrollTop = this.element.scrollHeight
    }, 0)
  }
  
  // Create a mutation observer to detect content changes
  createObserver() {
    this.observer = new MutationObserver(mutations => {
      // Check if any mutations include added nodes
      const shouldScroll = mutations.some(mutation => {
        return mutation.addedNodes.length > 0 || 
               mutation.type === 'attributes' ||
               mutation.type === 'characterData'
      })
      
      if (shouldScroll) {
        this.scrollToBottom()
      }
    })
    
    // Start observing the container for changes
    this.observer.observe(this.element, {
      childList: true,      // Watch for changes to child elements
      subtree: true,        // Watch for changes in descendants too
      characterData: true,  // Watch for changes to text content
      attributes: true      // Watch for changes to attributes
    })
  }
}
