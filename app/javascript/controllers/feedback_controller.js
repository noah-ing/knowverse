import { Controller } from "@hotwired/stimulus"

// Handles the feedback functionality in search results
export default class extends Controller {
  static targets = ["thumbsUp", "thumbsDown", "feedbackForm", "feedbackStatus", "submitButton"]
  
  connect() {
    console.log("Feedback controller connected")
  }
  
  // Handle thumbs up click
  async thumbsUp(event) {
    event.preventDefault()
    const url = this.thumbsUpTarget.getAttribute("data-feedback-url")
    await this.submitFeedback(url)
    this.thumbsUpTarget.classList.add("bg-green-500", "text-white")
    this.thumbsUpTarget.classList.remove("bg-gray-200", "text-gray-700")
    
    if (this.hasThumbsDownTarget) {
      this.thumbsDownTarget.classList.remove("bg-red-500", "text-white")
      this.thumbsDownTarget.classList.add("bg-gray-200", "text-gray-700")
    }
  }
  
  // Handle thumbs down click
  async thumbsDown(event) {
    event.preventDefault()
    const url = this.thumbsDownTarget.getAttribute("data-feedback-url")
    await this.submitFeedback(url)
    this.thumbsDownTarget.classList.add("bg-red-500", "text-white")
    this.thumbsDownTarget.classList.remove("bg-gray-200", "text-gray-700")
    
    if (this.hasThumbsUpTarget) {
      this.thumbsUpTarget.classList.remove("bg-green-500", "text-white")
      this.thumbsUpTarget.classList.add("bg-gray-200", "text-gray-700")
    }
  }
  
  // Show detailed feedback form
  showForm(event) {
    event.preventDefault()
    if (this.hasFeedbackFormTarget) {
      this.feedbackFormTarget.classList.remove("hidden")
    }
  }
  
  // Handle form submission
  async submitForm(event) {
    event.preventDefault()
    
    if (this.hasSubmitButtonTarget) {
      this.submitButtonTarget.disabled = true
      this.submitButtonTarget.classList.add("opacity-50", "cursor-not-allowed")
    }
    
    const form = event.currentTarget
    const formData = new FormData(form)
    
    try {
      const response = await fetch(form.action, {
        method: form.method,
        body: formData,
        headers: {
          "Accept": "application/json"
        }
      })
      
      const data = await response.json()
      
      if (response.ok) {
        this.showSuccess("Feedback submitted successfully. Thank you!")
        if (this.hasFeedbackFormTarget) {
          this.feedbackFormTarget.classList.add("hidden")
        }
      } else {
        this.showError(`Error: ${data.errors ? data.errors.join(", ") : "Unable to submit feedback"}`)
      }
    } catch (error) {
      this.showError("Network error. Please try again.")
    } finally {
      if (this.hasSubmitButtonTarget) {
        this.submitButtonTarget.disabled = false
        this.submitButtonTarget.classList.remove("opacity-50", "cursor-not-allowed")
      }
    }
  }
  
  // Generic feedback submission
  async submitFeedback(url) {
    try {
      const response = await fetch(url, {
        method: "POST",
        headers: {
          "X-CSRF-Token": this.getCSRFToken(),
          "Accept": "application/json"
        }
      })
      
      const data = await response.json()
      
      if (response.ok) {
        this.showSuccess("Feedback recorded. Thank you!")
      } else {
        this.showError(`Error: ${data.errors ? data.errors.join(", ") : "Unable to record feedback"}`)
      }
    } catch (error) {
      this.showError("Network error. Please try again.")
    }
  }
  
  // Helper to get CSRF token
  getCSRFToken() {
    return document.querySelector('meta[name="csrf-token"]')?.getAttribute("content") || ""
  }
  
  // Show success message
  showSuccess(message) {
    if (this.hasFeedbackStatusTarget) {
      this.feedbackStatusTarget.textContent = message
      this.feedbackStatusTarget.classList.remove("text-red-500", "hidden")
      this.feedbackStatusTarget.classList.add("text-green-500")
      
      setTimeout(() => {
        this.feedbackStatusTarget.classList.add("hidden")
      }, 5000)
    }
  }
  
  // Show error message
  showError(message) {
    if (this.hasFeedbackStatusTarget) {
      this.feedbackStatusTarget.textContent = message
      this.feedbackStatusTarget.classList.remove("text-green-500", "hidden")
      this.feedbackStatusTarget.classList.add("text-red-500")
      
      setTimeout(() => {
        this.feedbackStatusTarget.classList.add("hidden")
      }, 5000)
    }
  }
}
