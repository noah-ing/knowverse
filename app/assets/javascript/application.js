// This is the main JavaScript file for the Gold SaaS Boilerplate
// It is imported by application.html.erb and admin.html.erb

// Import Turbo
import "@hotwired/turbo-rails"

// Global app controller
document.addEventListener("turbo:load", () => {
  // Initialize any JavaScript that needs to run on page load
  console.log("Turbo page loaded")
})
