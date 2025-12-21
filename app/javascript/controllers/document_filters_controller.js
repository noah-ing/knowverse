import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="document-filters"
export default class extends Controller {
  static targets = [
    "advancedFilters", "label", "icon",
    "searchOptionsTab", "filterTab", "timeTab",
    "searchOptionsPanel", "filterPanel", "timePanel"
  ]

  connect() {
    // Initialize the state
    this.isAdvancedFiltersVisible = false
    this.currentTab = "searchOptions"
  }

  toggle() {
    this.isAdvancedFiltersVisible = !this.isAdvancedFiltersVisible
    this.updateUI()
  }

  updateUI() {
    if (this.hasAdvancedFiltersTarget) {
      if (this.isAdvancedFiltersVisible) {
        this.advancedFiltersTarget.classList.remove('hidden')
        if (this.hasLabelTarget) this.labelTarget.textContent = "Hide Advanced Filters"
        if (this.hasIconTarget) this.iconTarget.classList.add('transform', 'rotate-180')
      } else {
        this.advancedFiltersTarget.classList.add('hidden')
        if (this.hasLabelTarget) this.labelTarget.textContent = "Show Advanced Filters"
        if (this.hasIconTarget) this.iconTarget.classList.remove('transform', 'rotate-180')
      }
    }
  }

  // Tab switching methods for search page
  toggleFilterTab() {
    this.showTab("filter")
  }

  toggleTimeTab() {
    this.showTab("time")
  }

  showSearchOptions() {
    this.showTab("searchOptions")
  }

  showTab(tabName) {
    this.currentTab = tabName

    // Build tabs array only with existing targets
    const tabs = []

    if (this.hasSearchOptionsTabTarget && this.hasSearchOptionsPanelTarget) {
      tabs.push({ name: "searchOptions", tab: this.searchOptionsTabTarget, panel: this.searchOptionsPanelTarget })
    }
    if (this.hasFilterTabTarget && this.hasFilterPanelTarget) {
      tabs.push({ name: "filter", tab: this.filterTabTarget, panel: this.filterPanelTarget })
    }
    if (this.hasTimeTabTarget && this.hasTimePanelTarget) {
      tabs.push({ name: "time", tab: this.timeTabTarget, panel: this.timePanelTarget })
    }

    tabs.forEach(({ name, tab, panel }) => {
      if (name === tabName) {
        // Active tab
        tab.classList.remove("border-transparent", "kv-text-secondary")
        tab.classList.add("border-primary-500", "kv-text-accent")
        tab.setAttribute("aria-selected", "true")
        panel.classList.remove("hidden")
      } else {
        // Inactive tab
        tab.classList.remove("border-primary-500", "kv-text-accent")
        tab.classList.add("border-transparent", "kv-text-secondary")
        tab.setAttribute("aria-selected", "false")
        panel.classList.add("hidden")
      }
    })
  }
}
