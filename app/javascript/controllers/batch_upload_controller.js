import { Controller } from "@hotwired/stimulus"

/**
 * Batch Upload Controller
 *
 * Handles multi-file upload with:
 * - Drag and drop support
 * - File list management
 * - Per-file size validation
 * - Visual feedback
 */
export default class extends Controller {
  static targets = [
    "fileInput",
    "dropzone",
    "fileListContainer",
    "fileList",
    "fileCount",
    "totalSize",
    "buttonCount",
    "submitButton",
    "error",
    "errorMessage",
    "progressContainer",
    "progressList"
  ]

  static values = {
    maxFiles: { type: Number, default: 20 },
    maxSize: { type: Number, default: 10 } // MB per file
  }

  connect() {
    this.files = []
    this.dragCounter = 0
    this.setupDragDrop()
    this.setupFileInput()
  }

  setupDragDrop() {
    if (!this.hasDropzoneTarget) return

    const dropzone = this.dropzoneTarget

    dropzone.addEventListener("dragenter", (e) => {
      e.preventDefault()
      this.dragCounter++
      dropzone.classList.add("border-primary-500", "bg-primary-50", "dark:bg-primary-900/20")
    })

    dropzone.addEventListener("dragover", (e) => {
      e.preventDefault()
    })

    dropzone.addEventListener("dragleave", (e) => {
      e.preventDefault()
      this.dragCounter--
      if (this.dragCounter === 0) {
        dropzone.classList.remove("border-primary-500", "bg-primary-50", "dark:bg-primary-900/20")
      }
    })

    dropzone.addEventListener("drop", (e) => {
      e.preventDefault()
      this.dragCounter = 0
      dropzone.classList.remove("border-primary-500", "bg-primary-50", "dark:bg-primary-900/20")

      const droppedFiles = Array.from(e.dataTransfer.files)
      this.addFiles(droppedFiles)
    })
  }

  setupFileInput() {
    if (!this.hasFileInputTarget) return

    this.fileInputTarget.addEventListener("change", (e) => {
      const selectedFiles = Array.from(e.target.files)
      this.addFiles(selectedFiles)
    })
  }

  addFiles(newFiles) {
    this.clearError()

    // Validate file count
    if (this.files.length + newFiles.length > this.maxFilesValue) {
      this.showError(`Maximum ${this.maxFilesValue} files allowed. You have ${this.files.length} and tried to add ${newFiles.length}.`)
      return
    }

    // Validate each file
    const validFiles = []
    const errors = []

    for (const file of newFiles) {
      // Check size
      if (file.size > this.maxSizeValue * 1024 * 1024) {
        errors.push(`${file.name} exceeds ${this.maxSizeValue}MB limit`)
        continue
      }

      // Check for duplicates
      if (this.files.some(f => f.name === file.name && f.size === file.size)) {
        errors.push(`${file.name} is already in the list`)
        continue
      }

      validFiles.push(file)
    }

    if (errors.length > 0) {
      this.showError(errors.join(". "))
    }

    // Add valid files
    this.files = [...this.files, ...validFiles]
    this.updateUI()
    this.syncFileInput()
  }

  removeFile(event) {
    const index = parseInt(event.currentTarget.dataset.index, 10)
    if (isNaN(index) || index < 0 || index >= this.files.length) return

    this.files.splice(index, 1)
    this.updateUI()
    this.syncFileInput()
  }

  clearAll() {
    this.files = []
    this.updateUI()
    this.syncFileInput()
    this.clearError()
  }

  updateUI() {
    // Update file list visibility
    if (this.hasFileListContainerTarget) {
      if (this.files.length > 0) {
        this.fileListContainerTarget.classList.remove("hidden")
      } else {
        this.fileListContainerTarget.classList.add("hidden")
      }
    }

    // Update file list
    if (this.hasFileListTarget) {
      this.fileListTarget.innerHTML = this.files.map((file, index) => this.renderFileItem(file, index)).join("")
    }

    // Update counts
    if (this.hasFileCountTarget) {
      this.fileCountTarget.textContent = this.files.length
    }

    if (this.hasButtonCountTarget) {
      this.buttonCountTarget.textContent = this.files.length
    }

    // Update total size
    if (this.hasTotalSizeTarget) {
      const totalBytes = this.files.reduce((sum, f) => sum + f.size, 0)
      this.totalSizeTarget.textContent = this.formatSize(totalBytes)
    }

    // Update submit button
    if (this.hasSubmitButtonTarget) {
      this.submitButtonTarget.disabled = this.files.length === 0
    }
  }

  renderFileItem(file, index) {
    const ext = file.name.split(".").pop().toLowerCase()
    const iconColor = this.getIconColor(ext)

    return `
      <div class="flex items-center justify-between p-3 bg-gray-50 dark:bg-gray-800 rounded-lg border border-gray-200 dark:border-gray-700 group hover:border-primary-300 transition-colors">
        <div class="flex items-center min-w-0 flex-1">
          <div class="flex-shrink-0 w-10 h-10 rounded-lg ${iconColor} flex items-center justify-center mr-3">
            <span class="text-xs font-bold text-white uppercase">${ext}</span>
          </div>
          <div class="min-w-0 flex-1">
            <p class="text-sm font-medium kv-text-primary truncate">${this.escapeHtml(file.name)}</p>
            <p class="text-xs kv-text-secondary">${this.formatSize(file.size)}</p>
          </div>
        </div>
        <button type="button"
                class="ml-3 p-1.5 text-gray-400 hover:text-red-500 hover:bg-red-50 dark:hover:bg-red-900/20 rounded transition-colors opacity-0 group-hover:opacity-100"
                data-action="click->batch-upload#removeFile"
                data-index="${index}"
                title="Remove file">
          <svg class="h-4 w-4" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor">
            <path fill-rule="evenodd" d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z" clip-rule="evenodd" />
          </svg>
        </button>
      </div>
    `
  }

  syncFileInput() {
    if (!this.hasFileInputTarget) return

    // Create a new DataTransfer to set files on the input
    const dataTransfer = new DataTransfer()
    this.files.forEach(file => dataTransfer.items.add(file))
    this.fileInputTarget.files = dataTransfer.files
  }

  getIconColor(ext) {
    const colors = {
      pdf: "bg-red-500",
      doc: "bg-blue-500",
      docx: "bg-blue-500",
      txt: "bg-gray-500",
      md: "bg-gray-600",
      csv: "bg-green-500",
      xlsx: "bg-green-600",
      xls: "bg-green-600",
      json: "bg-yellow-500"
    }
    return colors[ext] || "bg-primary-500"
  }

  formatSize(bytes) {
    if (bytes === 0) return "0 Bytes"
    const k = 1024
    const sizes = ["Bytes", "KB", "MB", "GB"]
    const i = Math.floor(Math.log(bytes) / Math.log(k))
    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + " " + sizes[i]
  }

  showError(message) {
    if (this.hasErrorTarget && this.hasErrorMessageTarget) {
      this.errorMessageTarget.textContent = message
      this.errorTarget.classList.remove("hidden")
    }
  }

  clearError() {
    if (this.hasErrorTarget) {
      this.errorTarget.classList.add("hidden")
    }
  }

  escapeHtml(text) {
    const div = document.createElement("div")
    div.textContent = text
    return div.innerHTML
  }
}
