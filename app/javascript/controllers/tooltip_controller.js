import { Controller } from "@hotwired/stimulus"

/**
 * Tooltip Controller
 * 
 * Provides accessible, customizable tooltips
 * - Shows on hover or focus
 * - Positions automatically
 * - Handles keyboard interactions
 * - Supports ARIA attributes for accessibility
 */
export default class extends Controller {
  static targets = ["tooltip"]
  static values = { 
    content: String,
    position: { type: String, default: "top" },
    offset: { type: Number, default: 8 },
    delay: { type: Number, default: 300 }
  }
  
  connect() {
    // Create tooltip element if it doesn't exist
    if (!this.hasTooltipTarget) {
      this.tooltipElement = document.createElement('div')
      this.tooltipElement.classList.add(
        'kv-tooltip-content',
        'absolute', 
        'z-50', 
        'p-2',
        'text-xs',
        'bg-gray-800',
        'text-white',
        'rounded',
        'shadow-lg',
        'max-w-xs',
        'invisible',
        'opacity-0',
        'transition-opacity',
        'duration-200'
      )
      this.tooltipElement.setAttribute('role', 'tooltip')
      this.tooltipElement.setAttribute('data-tooltip-target', 'tooltip')
      
      // Generate unique ID for aria-describedby
      this.tooltipId = `tooltip-${Math.random().toString(36).substr(2, 9)}`
      this.tooltipElement.id = this.tooltipId
      
      // Add arrow element
      const arrow = document.createElement('div')
      arrow.classList.add('kv-tooltip-arrow')
      this.tooltipElement.appendChild(arrow)
      
      // Add to DOM
      document.body.appendChild(this.tooltipElement)
      
      // Set ARIA attributes on trigger element
      this.element.setAttribute('aria-describedby', this.tooltipId)
    }
    
    // Update content
    this.updateContent()
    
    // Add event listeners
    this.handleMouseEnter = this.handleMouseEnter.bind(this)
    this.handleMouseLeave = this.handleMouseLeave.bind(this)
    this.handleFocus = this.handleFocus.bind(this)
    this.handleBlur = this.handleBlur.bind(this)
    this.handleEscapeKey = this.handleEscapeKey.bind(this)
    
    this.element.addEventListener('mouseenter', this.handleMouseEnter)
    this.element.addEventListener('mouseleave', this.handleMouseLeave)
    this.element.addEventListener('focus', this.handleFocus)
    this.element.addEventListener('blur', this.handleBlur)
    document.addEventListener('keydown', this.handleEscapeKey)
  }
  
  disconnect() {
    // Remove tooltip from DOM
    if (this.tooltipElement && document.body.contains(this.tooltipElement)) {
      document.body.removeChild(this.tooltipElement)
    }
    
    // Remove event listeners
    this.element.removeEventListener('mouseenter', this.handleMouseEnter)
    this.element.removeEventListener('mouseleave', this.handleMouseLeave)
    this.element.removeEventListener('focus', this.handleFocus)
    this.element.removeEventListener('blur', this.handleBlur)
    document.removeEventListener('keydown', this.handleEscapeKey)
    
    if (this.showTimeoutId) clearTimeout(this.showTimeoutId)
    if (this.hideTimeoutId) clearTimeout(this.hideTimeoutId)
  }
  
  contentValueChanged() {
    this.updateContent()
  }
  
  updateContent() {
    if (this.hasTooltipTarget) {
      // Update tooltip content
      const contentElement = this.tooltipTarget.querySelector('.kv-tooltip-content-inner') || this.tooltipTarget
      contentElement.innerHTML = this.contentValue
    }
  }
  
  handleMouseEnter() {
    this.showTimeoutId = setTimeout(() => {
      this.show()
    }, this.delayValue)
  }
  
  handleMouseLeave() {
    if (this.showTimeoutId) {
      clearTimeout(this.showTimeoutId)
    }
    this.hide()
  }
  
  handleFocus() {
    this.show()
  }
  
  handleBlur() {
    this.hide()
  }
  
  handleEscapeKey(event) {
    if (event.key === 'Escape' && this.isVisible) {
      this.hide()
    }
  }
  
  show() {
    if (!this.tooltipElement) return
    
    this.tooltipElement.innerHTML = `
      <div class="kv-tooltip-content-inner">${this.contentValue}</div>
    `
    
    this.tooltipElement.classList.remove('invisible', 'opacity-0')
    this.tooltipElement.classList.add('opacity-100')
    
    this.position()
    this.isVisible = true
  }
  
  hide() {
    if (!this.tooltipElement) return
    
    this.tooltipElement.classList.remove('opacity-100')
    this.tooltipElement.classList.add('opacity-0')
    
    this.hideTimeoutId = setTimeout(() => {
      this.tooltipElement.classList.add('invisible')
      this.isVisible = false
    }, 200)
  }
  
  position() {
    const trigger = this.element
    const tooltip = this.tooltipElement
    
    if (!trigger || !tooltip) return
    
    const triggerRect = trigger.getBoundingClientRect()
    const tooltipRect = tooltip.getBoundingClientRect()
    
    const position = this.positionValue
    const offset = this.offsetValue || 8
    
    // Calculate positions
    let top, left
    
    switch (position) {
      case 'top':
        top = triggerRect.top - tooltipRect.height - offset
        left = triggerRect.left + (triggerRect.width / 2) - (tooltipRect.width / 2)
        break
      case 'bottom':
        top = triggerRect.bottom + offset
        left = triggerRect.left + (triggerRect.width / 2) - (tooltipRect.width / 2)
        break
      case 'left':
        top = triggerRect.top + (triggerRect.height / 2) - (tooltipRect.height / 2)
        left = triggerRect.left - tooltipRect.width - offset
        break
      case 'right':
        top = triggerRect.top + (triggerRect.height / 2) - (tooltipRect.height / 2)
        left = triggerRect.right + offset
        break
      default:
        top = triggerRect.top - tooltipRect.height - offset
        left = triggerRect.left + (triggerRect.width / 2) - (tooltipRect.width / 2)
    }
    
    // Adjust positioning to prevent overflow
    const viewportWidth = window.innerWidth
    const viewportHeight = window.innerHeight
    
    // Adjust horizontal positioning
    if (left < 0) {
      left = 0
    } else if (left + tooltipRect.width > viewportWidth) {
      left = viewportWidth - tooltipRect.width
    }
    
    // Adjust vertical positioning
    if (top < 0) {
      top = triggerRect.bottom + offset
    } else if (top + tooltipRect.height > viewportHeight) {
      top = triggerRect.top - tooltipRect.height - offset
    }
    
    // Apply position
    tooltip.style.top = `${top + window.scrollY}px`
    tooltip.style.left = `${left + window.scrollX}px`
  }
}
