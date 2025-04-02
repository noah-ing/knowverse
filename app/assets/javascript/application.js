// This is the main JavaScript file for the Gold SaaS Boilerplate
// It is imported by application.html.erb and admin.html.erb

// Import Turbo
import "@hotwired/turbo-rails"

// Import Chartkick and Chart.js for analytics charts
import "chartkick/chart.js"

// Import Stimulus controllers
import { Application } from "@hotwired/stimulus"
import Alpine from "alpinejs"

// Initialize Alpine.js
window.Alpine = Alpine
Alpine.start()

// Initialize Stimulus
const application = Application.start()

// Configure Stimulus development experience
application.debug = false
window.Stimulus = application

// Global app controller
document.addEventListener("turbo:load", () => {
  // Initialize any JavaScript that needs to run on page load
  console.log("Turbo page loaded")
})
