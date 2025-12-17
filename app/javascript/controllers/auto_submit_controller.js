import { Controller } from "@hotwired/stimulus"

// Auto-submit controller for submitting forms with keyboard shortcuts
export default class extends Controller {
  connect() {
    console.log("AutoSubmit controller connected")
  }
  
  // Handle key events for form submission (Enter without shift key)
  checkSubmit(event) {
    // Check if Enter key is pressed without the shift key
    if (event.key === 'Enter' && !event.shiftKey) {
      // Prevent default behavior (newline)
      event.preventDefault()
      
      // Get the form
      const form = this.element
      
      // Validate form
      if (form.checkValidity()) {
        // Submit the form
        form.requestSubmit()
      } else {
        // Trigger form validation
        form.reportValidity()
      }
    }
  }
}
