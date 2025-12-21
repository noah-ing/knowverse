import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["tab", "panel"]

  connect() {
    // Show the first panel by default
    this.showPanel("vector-space")
  }

  switch(event) {
    const tabName = event.currentTarget.dataset.tab
    this.showPanel(tabName)
  }

  switchMobile(event) {
    const tabName = event.target.value
    this.showPanel(tabName)
  }

  showPanel(name) {
    // Update tab styles
    this.tabTargets.forEach(tab => {
      if (tab.dataset.tab === name) {
        tab.classList.remove("border-transparent", "kv-text-secondary")
        tab.classList.add("border-primary-500", "kv-text-accent")
        tab.setAttribute("aria-current", "page")
      } else {
        tab.classList.remove("border-primary-500", "kv-text-accent")
        tab.classList.add("border-transparent", "kv-text-secondary")
        tab.removeAttribute("aria-current")
      }
    })

    // Show/hide panels
    this.panelTargets.forEach(panel => {
      if (panel.dataset.panel === name) {
        panel.classList.remove("hidden")
      } else {
        panel.classList.add("hidden")
      }
    })
  }
}
