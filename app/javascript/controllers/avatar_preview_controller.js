import { Controller } from "@hotwired/stimulus"

// Handles avatar file selection preview
// Shows selected image before upload and validates file type/size
export default class extends Controller {
  static targets = ["input", "preview", "placeholder", "filename"]
  static values = {
    maxSize: { type: Number, default: 5242880 } // 5MB default
  }

  connect() {
    // Initialize state
    this.hasExistingAvatar = this.previewTarget.tagName === 'IMG'
  }

  preview(event) {
    const file = event.target.files[0]
    if (!file) return

    // Validate file type
    if (!file.type.startsWith('image/')) {
      this.showError("Please select an image file (PNG, JPG, GIF)")
      event.target.value = ''
      return
    }

    // Validate file size
    if (file.size > this.maxSizeValue) {
      const maxMB = (this.maxSizeValue / 1024 / 1024).toFixed(0)
      this.showError(`Image must be less than ${maxMB}MB`)
      event.target.value = ''
      return
    }

    // Show preview
    const reader = new FileReader()
    reader.onload = (e) => {
      // If preview is an img, update src; otherwise replace placeholder with img
      if (this.previewTarget.tagName === 'IMG') {
        this.previewTarget.src = e.target.result
      } else {
        const img = document.createElement('img')
        img.src = e.target.result
        img.className = 'h-20 w-20 rounded-full object-cover'
        img.alt = 'Avatar preview'
        this.previewTarget.replaceWith(img)
        // Update target reference
        this.previewTarget = img
      }

      // Hide placeholder if exists
      if (this.hasPlaceholderTarget) {
        this.placeholderTarget.classList.add('hidden')
      }
    }
    reader.readAsDataURL(file)

    // Update filename display if target exists
    if (this.hasFilenameTarget) {
      this.filenameTarget.textContent = file.name
    }

    // Clear any previous errors
    this.clearError()
  }

  showError(message) {
    // Remove existing error if any
    this.clearError()

    // Create error message element
    const error = document.createElement('p')
    error.className = 'mt-2 text-sm text-red-600'
    error.id = 'avatar-error'
    error.textContent = message

    // Insert after the input container
    this.inputTarget.closest('.flex')?.insertAdjacentElement('afterend', error)
  }

  clearError() {
    const existingError = document.getElementById('avatar-error')
    if (existingError) {
      existingError.remove()
    }
  }
}
