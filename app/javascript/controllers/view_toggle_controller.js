import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="view-toggle"
export default class extends Controller {
  static targets = ["gridView", "listView", "gridBtn", "listBtn"]

  connect() {
    // Initialize with grid view by default
    this.showGridView()
  }

  switchToGrid() {
    this.showGridView()
  }

  switchToList() {
    this.showListView()
  }

  showGridView() {
    this.gridViewTarget.classList.remove('hidden')
    this.listViewTarget.classList.add('hidden')
    this.gridBtnTarget.classList.add('bg-white', 'dark:bg-gray-700', 'shadow-sm', 'kv-text-primary')
    this.gridBtnTarget.classList.remove('kv-text-secondary')
    this.listBtnTarget.classList.remove('bg-white', 'dark:bg-gray-700', 'shadow-sm', 'kv-text-primary')
    this.listBtnTarget.classList.add('kv-text-secondary')
    this.gridBtnTarget.setAttribute('aria-pressed', 'true')
    this.listBtnTarget.setAttribute('aria-pressed', 'false')
  }

  showListView() {
    this.gridViewTarget.classList.add('hidden')
    this.listViewTarget.classList.remove('hidden')
    this.listBtnTarget.classList.add('bg-white', 'dark:bg-gray-700', 'shadow-sm', 'kv-text-primary')
    this.listBtnTarget.classList.remove('kv-text-secondary')
    this.gridBtnTarget.classList.remove('bg-white', 'dark:bg-gray-700', 'shadow-sm', 'kv-text-primary')
    this.gridBtnTarget.classList.add('kv-text-secondary')
    this.gridBtnTarget.setAttribute('aria-pressed', 'false')
    this.listBtnTarget.setAttribute('aria-pressed', 'true')
  }
}
