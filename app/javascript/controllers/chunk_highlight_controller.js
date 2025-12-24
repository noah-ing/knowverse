import { Controller } from "@hotwired/stimulus"

/**
 * Chunk Highlight Controller
 *
 * Handles highlighting and scrolling to specific document chunks
 * when navigating from citation links (e.g., /documents/123#chunk-5)
 */
export default class extends Controller {
  static targets = ["container"]

  connect() {
    // Check for chunk hash in URL on page load
    this.highlightFromHash()

    // Listen for hash changes (e.g., clicking another citation link)
    window.addEventListener('hashchange', () => this.highlightFromHash())
  }

  disconnect() {
    window.removeEventListener('hashchange', () => this.highlightFromHash())
  }

  highlightFromHash() {
    const hash = window.location.hash

    if (!hash || !hash.startsWith('#chunk-')) return

    // Extract chunk index from hash
    const chunkIndex = hash.replace('#chunk-', '')
    const chunkElement = document.getElementById(`chunk-${chunkIndex}`)

    if (!chunkElement) {
      console.warn(`Chunk element not found: chunk-${chunkIndex}`)
      return
    }

    // Clear any existing highlights
    this.clearHighlights()

    // Highlight the target chunk
    this.highlightChunk(chunkElement)

    // Scroll to the chunk
    this.scrollToChunk(chunkElement)
  }

  highlightChunk(element) {
    // Add highlight classes
    element.classList.add(
      'bg-indigo-50',
      'border-l-4',
      'border-indigo-500',
      'chunk-highlighted'
    )

    // Add a subtle animation
    element.style.animation = 'chunk-highlight-pulse 2s ease-in-out'

    // Remove highlight after a delay (optional - keep for visibility)
    setTimeout(() => {
      element.classList.remove('bg-indigo-50')
      element.classList.add('bg-indigo-50/50')
    }, 3000)
  }

  clearHighlights() {
    const highlighted = document.querySelectorAll('.chunk-highlighted')
    highlighted.forEach(el => {
      el.classList.remove(
        'bg-indigo-50',
        'bg-indigo-50/50',
        'border-l-4',
        'border-indigo-500',
        'chunk-highlighted'
      )
      el.style.animation = ''
    })
  }

  scrollToChunk(element) {
    // Get the container for scrolling
    const container = this.hasContainerTarget ? this.containerTarget : element.parentElement

    // Calculate scroll position with offset for visibility
    const containerRect = container.getBoundingClientRect()
    const elementRect = element.getBoundingClientRect()
    const offset = 50 // Pixels from top

    // Scroll the container
    if (container.scrollHeight > container.clientHeight) {
      // Container is scrollable
      const scrollTop = element.offsetTop - offset
      container.scrollTo({
        top: scrollTop,
        behavior: 'smooth'
      })
    } else {
      // Container not scrollable, scroll the window
      element.scrollIntoView({
        behavior: 'smooth',
        block: 'center'
      })
    }
  }

  // Allow manual triggering via data action
  highlight(event) {
    const chunkIndex = event.currentTarget.dataset.chunkIndex
    if (chunkIndex !== undefined) {
      window.location.hash = `chunk-${chunkIndex}`
    }
  }
}
