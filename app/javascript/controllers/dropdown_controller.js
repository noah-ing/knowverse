import { Controller } from "@hotwired/stimulus"

/**
 * Enhanced Dropdown Controller
 * 
 * Manages dropdown menus in the UI with improved animations, accessibility,
 * and keyboard navigation support
 */
export default class extends Controller {
  static targets = ["menu", "button"]
  
  connect() {
    console.log("[DropdownController] Connected to element:", this.element);
    
    // Initialize state
    this.isOpen = false
    
    // Set initial ARIA attributes
    if (this.hasButtonTarget) {
      console.log("[DropdownController] Button target found:", this.buttonTarget);
      this.buttonTarget.setAttribute('aria-haspopup', 'true')
      this.buttonTarget.setAttribute('aria-expanded', 'false')
    } else {
      console.warn("[DropdownController] No button target found for:", this.element);
    }
    
    if (this.hasMenuTarget) {
      console.log("[DropdownController] Menu target found:", this.menuTarget);
      // Ensure menu starts hidden
      this.menuTarget.classList.add('hidden')
    } else {
      console.warn("[DropdownController] No menu target found for:", this.element);
    }
    
    // Setup keyboard event listener with proper binding
    this.handleKeyDownBound = this.handleKeyDown.bind(this)
    this.element.addEventListener('keydown', this.handleKeyDownBound)
    
    // Create bound versions of methods for event listeners
    this.hideBound = this.hide.bind(this)
    
    console.log("[DropdownController] Initialization complete for:", this.element);
  }
  
  // Toggle the dropdown visibility
  toggle(event) {
    if (event) {
      event.stopPropagation()
      event.preventDefault()
    }
    
    console.log("[DropdownController] Toggle called, current state:", this.isOpen);
    
    if (this.isOpen) {
      this.hide()
    } else {
      this.show()
    }
  }
  
  // Show the dropdown with animation
  show() {
    if (!this.hasMenuTarget) {
      console.error("[DropdownController] Cannot show - no menu target available!");
      return;
    }
    
    console.log("[DropdownController] Show method called");
    
    // Ensure menu exists
    if (!this.menuTarget) {
      console.error("[DropdownController] Menu target is null!");
      return;
    }
    
    console.log("[DropdownController] Menu state before show:", 
      this.menuTarget.classList.contains('hidden'),
      this.menuTarget.classList.contains('opacity-0')
    );
    
    // Remove hidden class to make visible - this is the main change
    // The CSS in ui_fixes.css will handle the animation and visibility
    this.menuTarget.classList.remove('hidden');
    
    // Force a reflow to ensure the browser recognizes the element is visible
    void this.menuTarget.offsetWidth;
    
    // Update ARIA attributes
    if (this.hasButtonTarget) {
      this.buttonTarget.setAttribute('aria-expanded', 'true');
    }
    
    // Set isOpen flag
    this.isOpen = true;
    
    // Focus the first focusable element within the menu
    this.focusFirstElement();
    
    // Handle clicks outside of dropdown
    this.bindDocumentClickHandler();
    
    console.log("[DropdownController] Menu now visible");
  }
  
  // Hide the dropdown
  hide(event) {
    // Skip if the event is from a child of the dropdown that isn't marked for hiding
    if (event && event.target && this.element.contains(event.target) && 
        (!event.currentTarget || !event.currentTarget.matches('[data-action*="dropdown#hide"]'))) {
      console.log("[DropdownController] Ignoring hide event from dropdown child");
      return;
    }
    
    if (!this.hasMenuTarget) {
      console.warn("[DropdownController] Cannot hide - no menu target");
      return;
    }
    
    if (!this.isOpen) {
      console.log("[DropdownController] Menu already hidden");
      return;
    }
    
    console.log("[DropdownController] Hiding dropdown menu");
    
    // Simply add the hidden class - the CSS will handle the rest
    this.menuTarget.classList.add('hidden');
    
    // Update ARIA attributes
    if (this.hasButtonTarget) {
      this.buttonTarget.setAttribute('aria-expanded', 'false');
    }
    
    // Set flag immediately
    this.isOpen = false;
    
    // Remove global click handler
    this.unbindDocumentClickHandler();
    
    // Return focus to dropdown button
    if (this.hasButtonTarget) {
      this.buttonTarget.focus();
    }
    
    console.log("[DropdownController] Menu now hidden");
  }
  
  // Handle keyboard navigation
  handleKeyDown(event) {
    // If menu is open
    if (this.isOpen) {
      // Close on escape
      if (event.key === 'Escape') {
        event.preventDefault();
        this.hide();
      }
      
      // Handle arrow keys for navigation within dropdown
      if (event.key === 'ArrowDown') {
        event.preventDefault();
        this.focusNextElement();
      }
      
      if (event.key === 'ArrowUp') {
        event.preventDefault();
        this.focusPreviousElement();
      }
      
      // Close and focus next focusable element on tab if at the end
      if (event.key === 'Tab' && !event.shiftKey) {
        const focusableElements = this.getFocusableElements();
        const focused = document.activeElement;
        
        if (focused === focusableElements[focusableElements.length - 1]) {
          this.hide();
        }
      }
      
      // Close and focus previous focusable element on shift+tab if at the beginning
      if (event.key === 'Tab' && event.shiftKey) {
        const focusableElements = this.getFocusableElements();
        const focused = document.activeElement;
        
        if (focused === focusableElements[0]) {
          this.hide();
        }
      }
    } else {
      // Open menu on down arrow when focused on the button
      if ((event.key === 'ArrowDown' || event.key === 'Enter' || event.key === ' ') && 
          this.hasButtonTarget && document.activeElement === this.buttonTarget) {
        event.preventDefault();
        this.show();
      }
    }
  }
  
  // Get all focusable elements in the dropdown
  getFocusableElements() {
    if (!this.hasMenuTarget) return [];
    
    return Array.from(this.menuTarget.querySelectorAll(
      'a[href], button, input, textarea, select, details, [tabindex]:not([tabindex="-1"])'
    )).filter(el => !el.hasAttribute('disabled') && !el.getAttribute('aria-hidden'));
  }
  
  // Focus the first focusable element in the dropdown
  focusFirstElement() {
    const elements = this.getFocusableElements();
    if (elements.length > 0) {
      setTimeout(() => elements[0].focus(), 50);
    }
  }
  
  // Focus the next focusable element in the dropdown
  focusNextElement() {
    const elements = this.getFocusableElements();
    const currentIndex = elements.findIndex(el => el === document.activeElement);
    
    if (currentIndex < elements.length - 1) {
      elements[currentIndex + 1].focus();
    } else {
      elements[0].focus(); // Wrap around to the first element
    }
  }
  
  // Focus the previous focusable element in the dropdown
  focusPreviousElement() {
    const elements = this.getFocusableElements();
    const currentIndex = elements.findIndex(el => el === document.activeElement);
    
    if (currentIndex > 0) {
      elements[currentIndex - 1].focus();
    } else {
      elements[elements.length - 1].focus(); // Wrap around to the last element
    }
  }
  
  // Bind a global click handler to detect clicks outside the dropdown
  bindDocumentClickHandler() {
    console.log("[DropdownController] Binding document click handler");
    // Avoid duplicate handlers
    this.unbindDocumentClickHandler();
    // Use the pre-bound method to ensure proper 'this' context
    document.addEventListener('click', this.hideBound, true);
  }
  
  // Remove the global click handler
  unbindDocumentClickHandler() {
    console.log("[DropdownController] Unbinding document click handler");
    document.removeEventListener('click', this.hideBound, true);
  }
  
  // Clean up when controller is disconnected
  disconnect() {
    console.log("[DropdownController] Disconnecting and cleaning up");
    this.unbindDocumentClickHandler();
    this.element.removeEventListener('keydown', this.handleKeyDownBound);
  }
}
