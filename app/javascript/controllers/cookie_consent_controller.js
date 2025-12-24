import { Controller } from "@hotwired/stimulus"

/**
 * Cookie Consent Controller
 *
 * Manages cookie consent banner display and user preferences.
 * Stores consent in a cookie for 1 year.
 */
export default class extends Controller {
  static targets = ["banner", "settingsModal"]

  connect() {
    // Check if consent has already been given
    if (!this.hasConsent()) {
      this.showBanner()
    }
  }

  showBanner() {
    if (this.hasBannerTarget) {
      this.bannerTarget.classList.remove("hidden")
    }
  }

  hideBanner() {
    if (this.hasBannerTarget) {
      this.bannerTarget.classList.add("hidden")
    }
  }

  // Accept all cookies
  acceptAll() {
    this.setConsent({
      essential: true,
      functional: true,
      analytics: true
    })
    this.hideBanner()
    this.enableAnalytics()
  }

  // Accept only essential cookies
  acceptEssential() {
    this.setConsent({
      essential: true,
      functional: false,
      analytics: false
    })
    this.hideBanner()
    this.disableAnalytics()
  }

  // Show settings modal
  showSettings() {
    if (this.hasSettingsModalTarget) {
      this.settingsModalTarget.classList.remove("hidden")
    }
  }

  // Hide settings modal
  hideSettings() {
    if (this.hasSettingsModalTarget) {
      this.settingsModalTarget.classList.add("hidden")
    }
  }

  // Save custom settings
  saveSettings(event) {
    event.preventDefault()
    const form = event.target
    const formData = new FormData(form)

    this.setConsent({
      essential: true, // Always true
      functional: formData.get("functional") === "on",
      analytics: formData.get("analytics") === "on"
    })

    const consent = this.getConsent()
    if (consent.analytics) {
      this.enableAnalytics()
    } else {
      this.disableAnalytics()
    }

    this.hideSettings()
    this.hideBanner()
  }

  // Check if consent has been given
  hasConsent() {
    return this.getCookie("cookie_consent") !== null
  }

  // Get consent preferences
  getConsent() {
    const consent = this.getCookie("cookie_consent")
    if (!consent) {
      return { essential: true, functional: false, analytics: false }
    }
    try {
      return JSON.parse(decodeURIComponent(consent))
    } catch {
      return { essential: true, functional: false, analytics: false }
    }
  }

  // Set consent preferences
  setConsent(preferences) {
    const value = encodeURIComponent(JSON.stringify(preferences))
    const expires = new Date()
    expires.setFullYear(expires.getFullYear() + 1) // 1 year
    document.cookie = `cookie_consent=${value}; expires=${expires.toUTCString()}; path=/; SameSite=Lax`
  }

  // Get cookie value
  getCookie(name) {
    const match = document.cookie.match(new RegExp("(^| )" + name + "=([^;]+)"))
    return match ? match[2] : null
  }

  // Enable analytics tracking
  enableAnalytics() {
    // Ahoy analytics is already loaded, just ensure it's tracking
    if (window.ahoy) {
      window.ahoy.trackAll()
    }
  }

  // Disable analytics tracking
  disableAnalytics() {
    // Clear analytics cookies
    document.cookie = "ahoy_visitor=; expires=Thu, 01 Jan 1970 00:00:00 UTC; path=/;"
    document.cookie = "ahoy_visit=; expires=Thu, 01 Jan 1970 00:00:00 UTC; path=/;"
  }
}
