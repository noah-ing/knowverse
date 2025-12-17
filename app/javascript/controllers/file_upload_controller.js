import { Controller } from "@hotwired/stimulus"

/**
 * File Upload Controller
 * 
 * Enhanced file upload experience with:
 * - Drag and drop support
 * - File previews
 * - Progress indicators
 * - Error handling
 * - Accessibility improvements
 */
export default class extends Controller {
  static targets = ["input", "preview", "dropzone", "progress", "progressBar", "progressText", "fileList", "template", "error"]
  
  static values = {
    maxFiles: { type: Number, default: 1 },
    maxSize: { type: Number, default: 10 }, // In MB
    acceptedTypes: String,
    previewImages: { type: Boolean, default: true }
  }
  
  connect() {
    console.log("[FileUploadController] Connected");
    
    // Set up drag and drop event listeners
    this.dragCounter = 0
    
    this.bindEvents()
    
    // Initialize the file list if it exists
    if (this.hasFileListTarget && this.hasTemplateTarget) {
      this.fileList = []
      this.updateFileList()
    }
  }
  
  disconnect() {
    this.unbindEvents()
  }
  
  bindEvents() {
    // Bind event handlers to maintain context
    this.handleDragEnter = this.handleDragEnter.bind(this)
    this.handleDragOver = this.handleDragOver.bind(this)
    this.handleDragLeave = this.handleDragLeave.bind(this)
    this.handleDrop = this.handleDrop.bind(this)
    this.handleInputChange = this.handleInputChange.bind(this)
    
    // Add event listeners to the dropzone
    if (this.hasDropzoneTarget) {
      this.dropzoneTarget.addEventListener('dragenter', this.handleDragEnter)
      this.dropzoneTarget.addEventListener('dragover', this.handleDragOver)
      this.dropzoneTarget.addEventListener('dragleave', this.handleDragLeave)
      this.dropzoneTarget.addEventListener('drop', this.handleDrop)
      
      // Make the entire dropzone clickable to trigger the file input
      this.dropzoneTarget.addEventListener('click', () => this.inputTarget.click())
    }
    
    // Add event listener to the file input
    this.inputTarget.addEventListener('change', this.handleInputChange)
  }
  
  unbindEvents() {
    if (this.hasDropzoneTarget) {
      this.dropzoneTarget.removeEventListener('dragenter', this.handleDragEnter)
      this.dropzoneTarget.removeEventListener('dragover', this.handleDragOver)
      this.dropzoneTarget.removeEventListener('dragleave', this.handleDragLeave)
      this.dropzoneTarget.removeEventListener('drop', this.handleDrop)
    }
    
    this.inputTarget.removeEventListener('change', this.handleInputChange)
  }
  
  // Drag and drop event handlers
  handleDragEnter(event) {
    event.preventDefault()
    this.dragCounter++
    
    if (this.hasDropzoneTarget) {
      this.dropzoneTarget.classList.add('drag-over', 'bg-primary-50', 'dark:bg-primary-900')
      this.dropzoneTarget.setAttribute('aria-dropeffect', 'copy')
    }
  }
  
  handleDragOver(event) {
    event.preventDefault()
  }
  
  handleDragLeave(event) {
    event.preventDefault()
    this.dragCounter--
    
    if (this.dragCounter === 0 && this.hasDropzoneTarget) {
      this.dropzoneTarget.classList.remove('drag-over', 'bg-primary-50', 'dark:bg-primary-900')
    }
  }
  
  handleDrop(event) {
    event.preventDefault()
    this.dragCounter = 0
    
    if (this.hasDropzoneTarget) {
      this.dropzoneTarget.classList.remove('drag-over', 'bg-primary-50', 'dark:bg-primary-900')
    }
    
    const files = event.dataTransfer.files
    this.processFiles(files)
  }
  
  handleInputChange(event) {
    const files = event.target.files
    this.processFiles(files)
  }
  
  // Process the selected or dropped files
  processFiles(files) {
    try {
      if (!files || files.length === 0) {
        console.warn("[FileUploadController] No files to process");
        return;
      }
      
      console.log("[FileUploadController] Processing files:", files.length);
      
      // Check maximum file count
      if (files.length > this.maxFilesValue && !this.inputTarget.multiple) {
        this.showError(`You can only upload a maximum of ${this.maxFilesValue} file(s)`)
        console.error(`[FileUploadController] Too many files: ${files.length} (max: ${this.maxFilesValue})`);
        return;
      }
      
      // Clone the FileList to an array for processing
      const fileArray = Array.from(files);
      console.log("[FileUploadController] Files converted to array successfully");
      
      // Check file types and sizes
      const invalidFiles = fileArray.filter(file => {
        if (this.acceptedTypesValue && !this.isAcceptedFileType(file)) {
          console.warn(`[FileUploadController] Invalid file type: ${file.type}`);
          return true;
        }
        
        if (file.size > this.maxSizeValue * 1024 * 1024) {
          console.warn(`[FileUploadController] File too large: ${file.size} bytes`);
          return true;
        }
        
        return false;
      });
      
      if (invalidFiles.length > 0) {
        this.showError(`Some files are not valid. Please check the file types and sizes (max ${this.maxSizeValue}MB)`);
        return;
      }
      
      // All files are valid, proceed
      this.clearError();
      
      // Update file preview area
      if (this.hasPreviewTarget) {
        const fileNameElement = this.previewTarget.querySelector('[data-file-upload-target="fileName"]');
        const fileSizeElement = this.previewTarget.querySelector('[data-file-upload-target="fileSize"]');
        const removeButton = this.previewTarget.querySelector('[data-action="file-upload#removeFile"]');
        
        if (fileArray.length > 0) {
          const file = fileArray[0];
          
          // Update file name and size
          if (fileNameElement) fileNameElement.textContent = file.name;
          if (fileSizeElement) fileSizeElement.textContent = this.formatFileSize(file.size);
          
          // Enable remove button
          if (removeButton) {
            removeButton.classList.remove('opacity-50', 'cursor-not-allowed');
            removeButton.removeAttribute('disabled');
          }
          
          // Highlight preview area
          this.previewTarget.classList.add('border-primary-300', 'dark:border-primary-700');
          this.previewTarget.classList.remove('border-gray-300', 'dark:border-gray-600');
        }
      }
      
      if (this.hasFileListTarget && this.hasTemplateTarget) {
        // Update the file list
        this.updateFileList(fileArray);
      } else if (this.hasPreviewTarget && this.previewImagesValue) {
        // Show image previews
        this.showImagePreviews(fileArray);
      }
      
      // If the form is using Direct Upload (ActiveStorage)
      if (typeof DirectUpload !== 'undefined' && this.inputTarget.dataset.directUploadUrl) {
        this.directUploadFiles(fileArray);
      }
      
      // Dispatch a custom event
      this.element.dispatchEvent(new CustomEvent("file-upload:files-added", {
        detail: { files: fileArray },
        bubbles: true
      }));
    } catch (error) {
      console.error("[FileUploadController] Error processing files:", error);
      this.showError("An error occurred while processing the files. Please try again.");
    }
  }
  
  // Check if a file type is in the accepted list
  isAcceptedFileType(file) {
    if (!this.acceptedTypesValue) return true;
    
    const acceptedTypes = this.acceptedTypesValue.split(',').map(type => type.trim());
    const fileType = file.type;
    
    // Check for exact match or wildcard match
    return acceptedTypes.some(type => {
      if (type.endsWith('/*')) {
        const category = type.split('/')[0];
        return fileType.startsWith(`${category}/`);
      } else {
        return type === fileType;
      }
    });
  }
  
  // Display image previews for image files
  showImagePreviews(files) {
    if (!this.hasPreviewTarget) return;
    
    // Clear previous previews
    this.previewTarget.innerHTML = '';
    
    files.forEach(file => {
      if (!file.type.startsWith('image/')) return;
      
      const reader = new FileReader();
      
      reader.onload = (e) => {
        const img = document.createElement('img');
        img.src = e.target.result;
        img.alt = file.name;
        img.classList.add('preview-image', 'h-24', 'object-cover', 'rounded', 'mt-2', 'mr-2');
        this.previewTarget.appendChild(img);
      };
      
      reader.readAsDataURL(file);
    });
  }
  
  // Upload files directly to ActiveStorage
  directUploadFiles(files) {
    if (!this.hasProgressTarget || !this.hasProgressBarTarget || !this.hasProgressTextTarget) return;
    
    let totalProgress = 0;
    const totalFiles = files.length;
    
    // Show progress elements
    this.progressTarget.classList.remove('hidden');
    
    files.forEach(file => {
      const upload = new DirectUpload(
        file, 
        this.inputTarget.dataset.directUploadUrl, 
        {
          directUploadWillStoreFileWithXHR: (xhr) => {
            xhr.upload.addEventListener("progress", (event) => {
              const progress = event.loaded / event.total * 100;
              this.updateProgress(file, progress, totalFiles, totalProgress);
              if (progress === 100) totalProgress++;
            });
          }
        }
      );
      
      upload.create((error, blob) => {
        if (error) {
          this.showError(`Error uploading ${file.name}: ${error}`);
        } else {
          // Add the signed blob ID to the hidden input
          const hiddenField = document.createElement('input');
          hiddenField.type = 'hidden';
          hiddenField.name = this.inputTarget.name;
          hiddenField.value = blob.signed_id;
          this.element.appendChild(hiddenField);
          
          // Dispatch a success event
          this.element.dispatchEvent(new CustomEvent("file-upload:upload-complete", {
            detail: { file, blob },
            bubbles: true
          }));
          
          // Hide progress when all files are uploaded
          if (totalProgress === totalFiles) {
            setTimeout(() => {
              this.progressTarget.classList.add('hidden');
            }, 1000);
          }
        }
      });
    });
  }
  
  // Update the progress bar and text
  updateProgress(file, progress, totalFiles, completedFiles) {
    if (!this.hasProgressBarTarget || !this.hasProgressTextTarget) return;
    
    const fileProgress = Math.round(progress);
    let totalProgress;
    
    if (totalFiles > 1) {
      // Calculate overall progress across all files
      totalProgress = Math.round((completedFiles * 100 + fileProgress) / totalFiles);
    } else {
      totalProgress = fileProgress;
    }
    
    // Update the progress bar width
    this.progressBarTarget.style.width = `${totalProgress}%`;
    
    // Update the progress text
    if (totalFiles > 1) {
      this.progressTextTarget.textContent = `Uploading ${file.name} (${fileProgress}%) - Total: ${totalProgress}%`;
    } else {
      this.progressTextTarget.textContent = `Uploading ${file.name}: ${fileProgress}%`;
    }
  }
  
  // Update the visual file list
  updateFileList(newFiles = []) {
    if (!this.hasFileListTarget || !this.hasTemplateTarget) return;
    
    // Add new files to the list
    if (newFiles.length > 0) {
      if (this.inputTarget.multiple) {
        // Add to existing files
        this.fileList = [...this.fileList, ...newFiles];
      } else {
        // Replace existing files
        this.fileList = newFiles;
      }
    }
    
    // Clear the list
    this.fileListTarget.innerHTML = '';
    
    // Show "no files" message if empty
    if (this.fileList.length === 0) {
      this.fileListTarget.innerHTML = '<div class="text-sm kv-text-secondary">No files selected</div>';
      return;
    }
    
    // Add each file to the list
    this.fileList.forEach((file, index) => {
      const fileItem = this.templateTarget.content.cloneNode(true);
      
      // Set file name
      const nameElement = fileItem.querySelector('[data-file-name]');
      if (nameElement) nameElement.textContent = file.name;
      
      // Set file size
      const sizeElement = fileItem.querySelector('[data-file-size]');
      if (sizeElement) sizeElement.textContent = this.formatFileSize(file.size);
      
      // Set file type
      const typeElement = fileItem.querySelector('[data-file-type]');
      if (typeElement) typeElement.textContent = file.type || 'Unknown';
      
      // Set file icon based on type
      const iconElement = fileItem.querySelector('[data-file-icon]');
      if (iconElement) {
        const iconClass = this.getFileIconClass(file);
        iconElement.classList.add(iconClass);
      }
      
      // Set up remove button
      const removeButton = fileItem.querySelector('[data-action="file-upload#removeFile"]');
      if (removeButton) {
        removeButton.dataset.fileIndex = index;
      }
      
      // Add the file item to the list
      this.fileListTarget.appendChild(fileItem);
    });
  }
  
  // Remove a file from the list
  removeFile(event) {
    const index = parseInt(event.currentTarget.dataset.fileIndex, 10);
    
    if (isNaN(index) || index < 0 || index >= this.fileList.length) return;
    
    // Remove the file from the list
    this.fileList.splice(index, 1);
    
    // Update the file input
    if (this.fileList.length === 0) {
      this.inputTarget.value = '';
    } else {
      // Create a new FileList-like object
      const dataTransfer = new DataTransfer();
      this.fileList.forEach(file => {
        dataTransfer.items.add(file);
      });
      this.inputTarget.files = dataTransfer.files;
    }
    
    // Update the UI
    this.updateFileList();
    
    // Dispatch an event
    this.element.dispatchEvent(new CustomEvent("file-upload:file-removed", {
      detail: { index },
      bubbles: true
    }));
  }
  
  // Format file size in a human-readable way
  formatFileSize(bytes) {
    if (bytes === 0) return '0 Bytes';
    
    const k = 1024;
    const sizes = ['Bytes', 'KB', 'MB', 'GB', 'TB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    
    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
  }
  
  // Get the appropriate icon class based on file type
  getFileIconClass(file) {
    const type = file.type;
    
    if (type.startsWith('image/')) {
      return 'file-icon-image';
    } else if (type.startsWith('video/')) {
      return 'file-icon-video';
    } else if (type.startsWith('audio/')) {
      return 'file-icon-audio';
    } else if (type.includes('pdf')) {
      return 'file-icon-pdf';
    } else if (type.includes('word') || type.includes('document')) {
      return 'file-icon-document';
    } else if (type.includes('excel') || type.includes('spreadsheet')) {
      return 'file-icon-spreadsheet';
    } else if (type.includes('powerpoint') || type.includes('presentation')) {
      return 'file-icon-presentation';
    } else if (type.includes('zip') || type.includes('archive')) {
      return 'file-icon-archive';
    } else {
      return 'file-icon-generic';
    }
  }
  
  // Show error message
  showError(message) {
    if (!this.hasErrorTarget) return;
    
    this.errorTarget.textContent = message;
    this.errorTarget.classList.remove('hidden');
  }
  
  // Clear error message
  clearError() {
    if (!this.hasErrorTarget) return;
    
    this.errorTarget.textContent = '';
    this.errorTarget.classList.add('hidden');
  }
  
  // Reset the form
  reset() {
    this.inputTarget.value = '';
    
    if (this.hasPreviewTarget) {
      this.previewTarget.innerHTML = '';
    }
    
    if (this.hasFileListTarget) {
      this.fileList = [];
      this.updateFileList();
    }
    
    if (this.hasProgressTarget) {
      this.progressTarget.classList.add('hidden');
    }
    
    this.clearError();
  }
}
