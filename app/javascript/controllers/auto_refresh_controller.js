import { Controller } from "@hotwired/stimulus"

/**
 * Auto Refresh Controller
 *
 * Automatically refreshes the page at a set interval when processing is in progress
 */
export default class extends Controller {
  static values = {
    interval: { type: Number, default: 5000 }
  }

  connect() {
    this.startRefresh()
  }

  disconnect() {
    this.stopRefresh()
  }

  startRefresh() {
    this.refreshTimer = setInterval(() => {
      // Use Turbo to refresh the page
      if (window.Turbo) {
        Turbo.visit(window.location.href, { action: "replace" })
      } else {
        window.location.reload()
      }
    }, this.intervalValue)
  }

  stopRefresh() {
    if (this.refreshTimer) {
      clearInterval(this.refreshTimer)
    }
  }
}
