import { Controller } from "@hotwired/stimulus"

/**
 * Dark Mode Controller (Disabled)
 *
 * Dark mode has been removed from the application.
 * This controller is kept as a stub to prevent errors if referenced elsewhere.
 */
export default class extends Controller {
  connect() {
    // Dark mode is disabled - app is statically light mode only
  }

  toggle() {
    // No-op - dark mode is disabled
  }
}
