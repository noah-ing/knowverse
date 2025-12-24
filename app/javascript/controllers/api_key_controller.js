import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["masked", "revealed", "eyeIcon", "eyeOffIcon", "copyIcon", "checkIcon"]

  connect() {
    this.revealed = false
  }

  toggleReveal() {
    this.revealed = !this.revealed

    if (this.hasMaskedTarget && this.hasRevealedTarget) {
      this.maskedTarget.classList.toggle("hidden", this.revealed)
      this.revealedTarget.classList.toggle("hidden", !this.revealed)
    }

    if (this.hasEyeIconTarget && this.hasEyeOffIconTarget) {
      this.eyeIconTarget.classList.toggle("hidden", this.revealed)
      this.eyeOffIconTarget.classList.toggle("hidden", !this.revealed)
    }
  }

  async copy(event) {
    const apiKey = event.currentTarget.dataset.apiKeyValue

    if (!apiKey) {
      return
    }

    try {
      await navigator.clipboard.writeText(apiKey)

      // Show success feedback
      if (this.hasCopyIconTarget && this.hasCheckIconTarget) {
        this.copyIconTarget.classList.add("hidden")
        this.checkIconTarget.classList.remove("hidden")

        // Reset after 2 seconds
        setTimeout(() => {
          this.copyIconTarget.classList.remove("hidden")
          this.checkIconTarget.classList.add("hidden")
        }, 2000)
      }
    } catch (err) {
      console.error("Failed to copy API key:", err)
    }
  }
}
