import { Controller } from "@hotwired/stimulus"

/**
 * Keyboard Shortcuts Controller
 *
 * Manages keyboard shortcuts and displays a help dialog.
 * Only activates shortcuts when not typing in input fields.
 */
export default class extends Controller {
  static targets = ["dialog", "overlay"]

  // Use private properties for dynamically created elements
  _dialog = null
  _overlay = null

  connect() {
    // Bind the handler so we can remove it later
    this.boundKeyHandler = this.handleKeyDown.bind(this)
    document.addEventListener('keydown', this.boundKeyHandler)

    // Ensure any existing panel is hidden on connect
    this.ensureHidden()
  }

  disconnect() {
    document.removeEventListener('keydown', this.boundKeyHandler)
    // Clean up dynamically created elements
    if (this._dialog) {
      this._dialog.remove()
      this._dialog = null
    }
    if (this._overlay) {
      this._overlay.remove()
      this._overlay = null
    }
  }

  // Get dialog element (target or dynamic)
  get dialog() {
    return this.hasDialogTarget ? this.dialogTarget : this._dialog
  }

  // Get overlay element (target or dynamic)
  get overlay() {
    return this.hasOverlayTarget ? this.overlayTarget : this._overlay
  }

  ensureHidden() {
    // Hide any visible overlays on page load
    const existingOverlays = document.querySelectorAll('.fixed.inset-0.bg-black, .fixed.inset-0.bg-gray-500')
    existingOverlays.forEach(overlay => {
      if (!overlay.classList.contains('hidden')) {
        overlay.classList.add('hidden')
        overlay.style.display = 'none'
        overlay.style.pointerEvents = 'none'
      }
    })
  }

  handleKeyDown(event) {
    // CRITICAL: Skip ALL shortcuts when user is typing in any input field
    const target = event.target
    const tagName = target.tagName.toUpperCase()

    if (tagName === 'INPUT' ||
        tagName === 'TEXTAREA' ||
        tagName === 'SELECT' ||
        target.isContentEditable ||
        target.closest('[contenteditable="true"]')) {
      // Allow the keystroke to pass through normally
      return
    }

    // Show shortcuts dialog with Ctrl/Cmd + ?
    if (event.key === '?' && (event.metaKey || event.ctrlKey)) {
      event.preventDefault()
      this.show()
      return
    }

    // Alt + key shortcuts for navigation
    if (event.altKey) {
      const shortcuts = {
        'd': '/dashboard',
        's': '/search',
        'r': '/rag',
        'u': '/upload'
      }

      if (shortcuts[event.key]) {
        event.preventDefault()
        window.location.href = shortcuts[event.key]
        return
      }

      // Toggle dark mode with Alt + T
      if (event.key === 't') {
        event.preventDefault()
        this.toggleDarkMode()
        return
      }
    }
  }

  show() {
    // Create dialog if it doesn't exist
    if (!this.dialog) {
      this.createDialog()
    }

    const dialog = this.dialog
    const overlay = this.overlay

    if (!dialog || !overlay) return

    // Show overlay
    overlay.classList.remove('hidden')
    overlay.style.display = 'flex'
    overlay.style.pointerEvents = 'auto'

    // Show dialog
    dialog.classList.remove('hidden')
    dialog.setAttribute('aria-hidden', 'false')

    // Animate in
    requestAnimationFrame(() => {
      overlay.classList.remove('opacity-0')
      overlay.classList.add('opacity-100')
      dialog.classList.remove('opacity-0', 'scale-95')
      dialog.classList.add('opacity-100', 'scale-100')
    })

    // Store focus for restoration
    this.previousFocus = document.activeElement
  }

  hide() {
    const dialog = this.dialog
    const overlay = this.overlay

    if (!dialog || !overlay) return

    // Animate out
    overlay.classList.remove('opacity-100')
    overlay.classList.add('opacity-0')
    dialog.classList.remove('opacity-100', 'scale-100')
    dialog.classList.add('opacity-0', 'scale-95')

    // Hide after animation
    setTimeout(() => {
      dialog.classList.add('hidden')
      dialog.setAttribute('aria-hidden', 'true')
      overlay.classList.add('hidden')
      overlay.style.display = 'none'
      overlay.style.pointerEvents = 'none'

      // Restore focus
      if (this.previousFocus) {
        this.previousFocus.focus()
      }
    }, 200)
  }

  createDialog() {
    // Create overlay
    const overlay = document.createElement('div')
    overlay.className = 'fixed inset-0 bg-black/50 z-40 hidden opacity-0 transition-opacity duration-200'
    overlay.style.display = 'none'
    overlay.style.pointerEvents = 'none'
    overlay.addEventListener('click', () => this.hide())

    // Create dialog
    const dialog = document.createElement('div')
    dialog.className = 'fixed inset-0 z-50 flex items-center justify-center hidden opacity-0 scale-95 transition-all duration-200'
    dialog.setAttribute('role', 'dialog')
    dialog.setAttribute('aria-modal', 'true')
    dialog.setAttribute('aria-labelledby', 'shortcuts-title')
    dialog.setAttribute('aria-hidden', 'true')

    dialog.innerHTML = `
      <div class="bg-white dark:bg-gray-800 rounded-xl shadow-2xl max-w-md w-full mx-4 p-6">
        <div class="flex items-center justify-between mb-4">
          <h2 id="shortcuts-title" class="text-lg font-semibold text-gray-900 dark:text-white">
            Keyboard Shortcuts
          </h2>
          <button type="button" class="text-gray-400 hover:text-gray-600 dark:hover:text-gray-300 p-1 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-700 transition-colors" aria-label="Close">
            <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/>
            </svg>
          </button>
        </div>

        <div class="space-y-4">
          <div>
            <h3 class="text-sm font-medium text-gray-500 dark:text-gray-400 mb-2">Navigation</h3>
            <div class="space-y-2">
              <div class="flex justify-between text-sm">
                <span class="text-gray-700 dark:text-gray-300">Dashboard</span>
                <kbd class="px-2 py-0.5 bg-gray-100 dark:bg-gray-700 rounded text-xs font-mono">Alt + D</kbd>
              </div>
              <div class="flex justify-between text-sm">
                <span class="text-gray-700 dark:text-gray-300">Search</span>
                <kbd class="px-2 py-0.5 bg-gray-100 dark:bg-gray-700 rounded text-xs font-mono">Alt + S</kbd>
              </div>
              <div class="flex justify-between text-sm">
                <span class="text-gray-700 dark:text-gray-300">RAG Chat</span>
                <kbd class="px-2 py-0.5 bg-gray-100 dark:bg-gray-700 rounded text-xs font-mono">Alt + R</kbd>
              </div>
            </div>
          </div>

          <div>
            <h3 class="text-sm font-medium text-gray-500 dark:text-gray-400 mb-2">Actions</h3>
            <div class="space-y-2">
              <div class="flex justify-between text-sm">
                <span class="text-gray-700 dark:text-gray-300">Toggle Dark Mode</span>
                <kbd class="px-2 py-0.5 bg-gray-100 dark:bg-gray-700 rounded text-xs font-mono">Alt + T</kbd>
              </div>
              <div class="flex justify-between text-sm">
                <span class="text-gray-700 dark:text-gray-300">Show Shortcuts</span>
                <kbd class="px-2 py-0.5 bg-gray-100 dark:bg-gray-700 rounded text-xs font-mono">Ctrl + ?</kbd>
              </div>
            </div>
          </div>
        </div>

        <div class="mt-6 pt-4 border-t border-gray-200 dark:border-gray-700">
          <p class="text-xs text-gray-500 dark:text-gray-400 text-center">
            Press <kbd class="px-1.5 py-0.5 bg-gray-100 dark:bg-gray-700 rounded text-xs">Esc</kbd> to close
          </p>
        </div>
      </div>
    `

    // Add close button handler
    const closeBtn = dialog.querySelector('button')
    closeBtn.addEventListener('click', () => this.hide())

    // Close on Escape key
    dialog.addEventListener('keydown', (e) => {
      if (e.key === 'Escape') this.hide()
    })

    // Append to body
    document.body.appendChild(overlay)
    document.body.appendChild(dialog)

    // Store references (NOT as targets)
    this._overlay = overlay
    this._dialog = dialog
  }

  toggleDarkMode() {
    const darkModeController = document.querySelector('[data-controller="dark-mode"]')
    if (darkModeController) {
      darkModeController.click()
    }
  }
}
