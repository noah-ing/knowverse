import { Controller } from "@hotwire/stimulus"

// Connects to data-controller="document-filters"
export default class extends Controller {
  static targets = ["advancedFilters", "label", "icon"]

  connect() {
    // Initialize the state
    this.isAdvancedFiltersVisible = false
    this.updateUI()
  }

  toggle() {
    this.isAdvancedFiltersVisible = !this.isAdvancedFiltersVisible
    this.updateUI()
  }

  updateUI() {
    if (this.isAdvancedFiltersVisible) {
      this.advancedFiltersTarget.classList.remove('hidden')
      this.labelTarget.textContent = "Hide Advanced Filters"
      this.iconTarget.classList.add('transform', 'rotate-180')
    } else {
      this.advancedFiltersTarget.classList.add('hidden')
      this.labelTarget.textContent = "Show Advanced Filters"
      this.iconTarget.classList.remove('transform', 'rotate-180')
    }
  }
}
