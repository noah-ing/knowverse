import { Controller } from "@hotwired/stimulus"

/**
 * Keyboard Shortcuts Controller
 * 
 * Manages keyboard shortcuts and displays a help dialog
 * - Registers global keyboard shortcuts
 * - Shows a modal with available shortcuts
 * - Supports different shortcut contexts
 */
export default class extends Controller {
  static targets = ["dialog", "overlay"]

  connect() {
    // Register global keyboard shortcuts
    document.addEventListener('keydown', this.handleKeyDown.bind(this))
    
    // Initialize dialog if exists
    if (this.hasDialogTarget) {
      this.dialogTarget.setAttribute('aria-hidden', 'true')
      
      // Close dialog on overlay click
      if (this.hasOverlayTarget) {
        this.overlayTarget.addEventListener('click', this.hide.bind(this))
      }
      
      // Close on Escape key
      this.dialogTarget.addEventListener('keydown', (event) => {
        if (event.key === 'Escape') {
          this.hide()
        }
      })
    } else {
      // Create dialog on demand
      this.createDialog()
    }
  }
  
  disconnect() {
    document.removeEventListener('keydown', this.handleKeyDown.bind(this))
  }
  
  show() {
    if (!this.dialogTarget) {
      this.createDialog()
    }
    
    // Show dialog
    this.dialogTarget.classList.remove('hidden')
    this.dialogTarget.setAttribute('aria-hidden', 'false')
    
    // Add animation classes
    setTimeout(() => {
      if (this.hasOverlayTarget) {
        this.overlayTarget.classList.add('opacity-100')
        this.overlayTarget.classList.remove('opacity-0')
      }
      this.dialogTarget.classList.add('opacity-100', 'translate-y-0')
      this.dialogTarget.classList.remove('opacity-0', 'translate-y-4')
      
      // Focus the first focusable element
      const focusable = this.dialogTarget.querySelector('button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])')
      if (focusable) {
        focusable.focus()
      }
    }, 50)
    
    // Store the element that had focus before opening
    this.previousFocus = document.activeElement
  }
  
  hide() {
    if (!this.hasDialogTarget) return
    
    // Add animation classes
    if (this.hasOverlayTarget) {
      this.overlayTarget.classList.add('opacity-0')
      this.overlayTarget.classList.remove('opacity-100')
    }
    this.dialogTarget.classList.add('opacity-0', 'translate-y-4')
    this.dialogTarget.classList.remove('opacity-100', 'translate-y-0')
    
    // Hide dialog after animation
    setTimeout(() => {
      this.dialogTarget.classList.add('hidden')
      this.dialogTarget.setAttribute('aria-hidden', 'true')
      
      // Restore focus
      if (this.previousFocus) {
        this.previousFocus.focus()
      }
    }, 300)
  }
  
  handleKeyDown(event) {
    // Check for keyboard shortcuts
    if (event.key === '?' && (event.metaKey || event.ctrlKey)) {
      // Show keyboard shortcuts dialog
      event.preventDefault()
      this.show()
    }
    
    // Add other global shortcuts as needed
    const shortcuts = {
      // Navigation shortcuts
      'd': () => this.navigateTo('/dashboard'),
      's': () => this.navigateTo('/search'),
      'r': () => this.navigateTo('/rag'),
      'u': () => this.navigateTo('/upload'),
      
      // Actions
      't': () => this.toggleDarkMode(),
      
      // Jump to sections
      '1': () => this.jumpToSection('documents'),
      '2': () => this.jumpToSection('search'),
      '3': () => this.jumpToSection('analytics')
    }
    
    // Check if a key combo is pressed while holding Alt
    if (event.altKey && shortcuts[event.key]) {
      event.preventDefault()
      shortcuts[event.key]()
    }
  }
  
  createDialog() {
    // Create dialog element if it doesn't exist
    const dialog = document.createElement('div')
    dialog.setAttribute('role', 'dialog')
    dialog.setAttribute('aria-labelledby', 'keyboard-shortcuts-title')
    dialog.setAttribute('aria-modal', 'true')
    dialog.setAttribute('data-keyboard-shortcuts-target', 'dialog')
    dialog.classList.add(
      'fixed', 'z-50', 'inset-0', 'overflow-y-auto', 'hidden', 
      'opacity-0', 'translate-y-4', 'transition-all', 'duration-300', 'ease-out'
    )
    
    // Create overlay
    const overlay = document.createElement('div')
    overlay.setAttribute('data-keyboard-shortcuts-target', 'overlay')
    overlay.classList.add(
      'fixed', 'inset-0', 'bg-gray-500', 'bg-opacity-75', 'transition-opacity', 
      'duration-300', 'ease-out', 'opacity-0'
    )
    
    // Create dialog content
    dialog.innerHTML = `
      <div class="flex items-end justify-center min-h-screen pt-4 px-4 pb-20 text-center sm:block sm:p-0">
        <span class="hidden sm:inline-block sm:align-middle sm:h-screen" aria-hidden="true">&#8203;</span>
        <div class="inline-block align-bottom bg-white dark:bg-gray-800 rounded-lg text-left overflow-hidden shadow-xl transform transition-all sm:my-8 sm:align-middle sm:max-w-lg sm:w-full p-6">
          <div class="absolute top-0 right-0 pt-4 pr-4">
            <button type="button" data-action="keyboard-shortcuts#hide" class="bg-white dark:bg-gray-800 rounded-md text-gray-400 dark:text-gray-500 hover:text-gray-500 dark:hover:text-gray-400 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-primary-500">
              <span class="sr-only">Close</span>
              <svg class="h-6 w-6" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke="currentColor" aria-hidden="true">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
          </div>
          <div class="sm:flex sm:items-start">
            <div class="mt-3 text-center sm:mt-0 sm:ml-4 sm:text-left w-full">
              <h3 class="text-lg leading-6 font-medium kv-text-primary" id="keyboard-shortcuts-title">
                Keyboard Shortcuts
              </h3>
              <div class="mt-4 space-y-4">
                <div>
                  <h4 class="font-medium text-sm kv-text-accent mb-2">Navigation</h4>
                  <div class="grid grid-cols-2 gap-y-2">
                    <div class="flex items-center">
                      <kbd class="px-2 py-1 text-xs font-semibold kv-bg-secondary text-white rounded">Alt + D</kbd>
                      <span class="ml-2 text-sm kv-text-secondary">Dashboard</span>
                    </div>
                    <div class="flex items-center">
                      <kbd class="px-2 py-1 text-xs font-semibold kv-bg-secondary text-white rounded">Alt + S</kbd>
                      <span class="ml-2 text-sm kv-text-secondary">Search</span>
                    </div>
                    <div class="flex items-center">
                      <kbd class="px-2 py-1 text-xs font-semibold kv-bg-secondary text-white rounded">Alt + R</kbd>
                      <span class="ml-2 text-sm kv-text-secondary">RAG</span>
                    </div>
                    <div class="flex items-center">
                      <kbd class="px-2 py-1 text-xs font-semibold kv-bg-secondary text-white rounded">Alt + U</kbd>
                      <span class="ml-2 text-sm kv-text-secondary">Upload</span>
                    </div>
                  </div>
                </div>
                <div>
                  <h4 class="font-medium text-sm kv-text-accent mb-2">Actions</h4>
                  <div class="grid grid-cols-2 gap-y-2">
                    <div class="flex items-center">
                      <kbd class="px-2 py-1 text-xs font-semibold kv-bg-secondary text-white rounded">Alt + T</kbd>
                      <span class="ml-2 text-sm kv-text-secondary">Toggle Dark Mode</span>
                    </div>
                    <div class="flex items-center">
                      <kbd class="px-2 py-1 text-xs font-semibold kv-bg-secondary text-white rounded">Ctrl + ?</kbd>
                      <span class="ml-2 text-sm kv-text-secondary">Show This Menu</span>
                    </div>
                  </div>
                </div>
                <div>
                  <h4 class="font-medium text-sm kv-text-accent mb-2">Jump to Sections</h4>
                  <div class="grid grid-cols-2 gap-y-2">
                    <div class="flex items-center">
                      <kbd class="px-2 py-1 text-xs font-semibold kv-bg-secondary text-white rounded">Alt + 1</kbd>
                      <span class="ml-2 text-sm kv-text-secondary">Documents</span>
                    </div>
                    <div class="flex items-center">
                      <kbd class="px-2 py-1 text-xs font-semibold kv-bg-secondary text-white rounded">Alt + 2</kbd>
                      <span class="ml-2 text-sm kv-text-secondary">Search</span>
                    </div>
                    <div class="flex items-center">
                      <kbd class="px-2 py-1 text-xs font-semibold kv-bg-secondary text-white rounded">Alt + 3</kbd>
                      <span class="ml-2 text-sm kv-text-secondary">Analytics</span>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    `
    
    // Append dialog to the body
    document.body.appendChild(overlay)
    document.body.appendChild(dialog)
    
    // Store references
    this.dialogTarget = dialog
    this.overlayTarget = overlay
  }
  
  // Navigation helper
  navigateTo(path) {
    if (window.location.pathname !== path) {
      window.location.href = path
    }
  }
  
  // Toggle dark mode
  toggleDarkMode() {
    const darkModeController = document.querySelector('[data-controller="dark-mode"]')
    if (darkModeController) {
      const action = darkModeController.getAttribute('data-action')
      if (action && action.includes('dark-mode#toggle')) {
        darkModeController.click()
      }
    }
  }
  
  // Jump to a section on the page
  jumpToSection(sectionId) {
    const section = document.getElementById(sectionId)
    if (section) {
      section.scrollIntoView({ behavior: 'smooth' })
      section.focus()
    }
  }
}
