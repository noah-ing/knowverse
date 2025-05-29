import { Controller } from "@hotwired/stimulus"

/**
 * Mobile Menu Controller
 * 
 * Handles the responsive mobile navigation menu
 * - Toggles menu visibility
 * - Handles transitions and animations
 * - Manages accessibility attributes
 */
export default class extends Controller {
  static targets = ["menuButton", "panel", "openIcon", "closeIcon"]
  
  connect() {
    // Set initial state
    this.isOpen = false
    
    // Setup event listener for clicks outside the menu
    this.handleClickOutside = this.handleClickOutside.bind(this)
    document.addEventListener('click', this.handleClickOutside)
    
    // Set initial ARIA attributes
    if (this.hasMenuButtonTarget) {
      this.menuButtonTarget.setAttribute('aria-expanded', 'false')
    }
  }
  
  disconnect() {
    document.removeEventListener('click', this.handleClickOutside)
  }
  
  toggle() {
    this.isOpen ? this.close() : this.open()
  }
  
  open() {
    if (this.hasPanelTarget && this.hasOpenIconTarget && this.hasCloseIconTarget) {
      // Show panel with animation
      this.panelTarget.classList.remove('hidden')
      
      // Add entrance animation classes
      this.panelTarget.classList.add('animate-in')
      
      // Toggle icon visibility
      this.openIconTarget.classList.add('hidden')
      this.closeIconTarget.classList.remove('hidden')
      
      // Update ARIA attributes
      if (this.hasMenuButtonTarget) {
        this.menuButtonTarget.setAttribute('aria-expanded', 'true')
      }
      
      // Update state
      this.isOpen = true
    }
  }
  
  close() {
    if (this.hasPanelTarget && this.hasOpenIconTarget && this.hasCloseIconTarget) {
      // Add exit animation classes
      this.panelTarget.classList.add('animate-out')
      
      // Listen for animation to complete
      this.panelTarget.addEventListener('animationend', () => {
        // Hide panel after animation completes
        this.panelTarget.classList.add('hidden')
        this.panelTarget.classList.remove('animate-in', 'animate-out')
      }, { once: true })
      
      // Toggle icon visibility
      this.openIconTarget.classList.remove('hidden')
      this.closeIconTarget.classList.add('hidden')
      
      // Update ARIA attributes
      if (this.hasMenuButtonTarget) {
        this.menuButtonTarget.setAttribute('aria-expanded', 'false')
      }
      
      // Update state
      this.isOpen = false
    }
  }
  
  // Close menu when clicking outside
  handleClickOutside(event) {
    if (this.isOpen && 
        this.hasPanelTarget && 
        !this.panelTarget.contains(event.target) && 
        (!this.hasMenuButtonTarget || !this.menuButtonTarget.contains(event.target))) {
      this.close()
    }
  }
}
