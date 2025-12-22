import { Controller } from "@hotwired/stimulus"

/**
 * Bulk Select Controller
 *
 * Handles selecting multiple items for bulk operations like delete
 */
export default class extends Controller {
  static targets = ["checkbox", "selectAll", "selectedCount", "bulkActions", "form"]
  static values = {
    deleteUrl: String
  }

  connect() {
    this.updateUI()
  }

  toggleAll(event) {
    const checked = event.target.checked
    this.checkboxTargets.forEach(checkbox => {
      checkbox.checked = checked
    })
    this.updateUI()
  }

  toggle() {
    this.updateUI()
  }

  updateUI() {
    const selected = this.checkboxTargets.filter(cb => cb.checked)
    const count = selected.length

    // Update count display
    if (this.hasSelectedCountTarget) {
      this.selectedCountTarget.textContent = count
    }

    // Show/hide bulk actions
    if (this.hasBulkActionsTarget) {
      if (count > 0) {
        this.bulkActionsTarget.classList.remove("hidden")
      } else {
        this.bulkActionsTarget.classList.add("hidden")
      }
    }

    // Update select all checkbox state
    if (this.hasSelectAllTarget) {
      if (count === 0) {
        this.selectAllTarget.checked = false
        this.selectAllTarget.indeterminate = false
      } else if (count === this.checkboxTargets.length) {
        this.selectAllTarget.checked = true
        this.selectAllTarget.indeterminate = false
      } else {
        this.selectAllTarget.checked = false
        this.selectAllTarget.indeterminate = true
      }
    }
  }

  deleteSelected(event) {
    event.preventDefault()

    const selected = this.checkboxTargets.filter(cb => cb.checked)
    const count = selected.length

    if (count === 0) return

    if (!confirm(`Are you sure you want to delete ${count} document(s)? This action cannot be undone.`)) {
      return
    }

    // Collect document IDs
    const ids = selected.map(cb => cb.value)

    // Submit the form with the selected IDs
    if (this.hasFormTarget) {
      // Clear existing hidden inputs
      this.formTarget.querySelectorAll('input[name="ids[]"]').forEach(el => el.remove())

      // Add selected IDs
      ids.forEach(id => {
        const input = document.createElement('input')
        input.type = 'hidden'
        input.name = 'ids[]'
        input.value = id
        this.formTarget.appendChild(input)
      })

      this.formTarget.submit()
    }
  }

  selectNone() {
    this.checkboxTargets.forEach(cb => cb.checked = false)
    if (this.hasSelectAllTarget) {
      this.selectAllTarget.checked = false
    }
    this.updateUI()
  }
}
