import { Controller } from "@hotwired/stimulus"

/**
 * Dark Mode Controller
 * 
 * Enhanced controller for handling dark mode:
 * - Respects user system preferences
 * - Persists settings in localStorage
 * - Updates theme-color meta tag for browsers
 * - Includes keyboard shortcuts support
 * - Supports accessibility through ARIA attributes
 * - Provides smooth transitions
 */
export default class extends Controller {
  static targets = ["toggle", "themeColor", "modeText"]
  
  // Light and dark theme colors
  static values = {
    lightThemeColor: { type: String, default: "#ffffff" },
    darkThemeColor: { type: String, default: "#1f2937" }
  }
  
  connect() {
    console.log("[DarkModeController] Connected");
    
    // Check for user preference in local storage
    this.isDarkMode = localStorage.getItem("darkMode") === "true"
    console.log("[DarkModeController] isDarkMode from localStorage:", this.isDarkMode);
    
    // Check for system preference if no local storage setting
    if (localStorage.getItem("darkMode") === null) {
      this.isDarkMode = window.matchMedia("(prefers-color-scheme: dark)").matches
      console.log("[DarkModeController] No localStorage setting, using system preference:", this.isDarkMode);
    }
    
    // Initialize dark mode based on stored preference
    this.updateDarkMode()
    
    // Set ARIA attributes on toggle
    if (this.hasToggleTarget) {
      console.log("[DarkModeController] Toggle target found:", this.toggleTarget);
      this.toggleTarget.setAttribute("aria-checked", this.isDarkMode.toString())
      this.toggleTarget.setAttribute("role", "switch")
      
      // Create toggle icon immediately
      this.updateToggleAppearance();
    } else {
      console.warn("[DarkModeController] No toggle target found!");
    }
    
    // Listen for system preference changes
    this.prefersColorSchemeMedia = window.matchMedia("(prefers-color-scheme: dark)")
    this.prefersColorSchemeMedia.addEventListener("change", this.handleSystemPreferenceChange.bind(this))
    
    // Set up keyboard shortcut (Shift+D) for toggling dark mode
    this.handleKeyDown = this.handleKeyDown.bind(this)
    document.addEventListener("keydown", this.handleKeyDown)
    
    // Initialize mode text if available
    if (this.hasModeTextTarget) {
      this.modeTextTarget.textContent = this.isDarkMode ? "Dark" : "Light";
    }
    
    console.log("[DarkModeController] Initialization complete");
  }
  
  disconnect() {
    // Clean up event listeners
    if (this.prefersColorSchemeMedia) {
      this.prefersColorSchemeMedia.removeEventListener("change", this.handleSystemPreferenceChange)
    }
    document.removeEventListener("keydown", this.handleKeyDown)
  }
  
  // Handle system preference changes
  handleSystemPreferenceChange(e) {
    // Only apply if user hasn't explicitly set a preference
    if (localStorage.getItem("darkMode") === null) {
      this.isDarkMode = e.matches
      this.updateDarkMode()
    }
  }
  
  // Toggle dark mode on and off
  toggle(event) {
    console.log("[DarkModeController] Toggle called, current state:", this.isDarkMode);
    
    try {
      // Explicitly convert to boolean in case it's undefined
      this.isDarkMode = !(this.isDarkMode === true);
      
      // Persist to localStorage
      localStorage.setItem("darkMode", this.isDarkMode.toString());
      console.log("[DarkModeController] Saved to localStorage:", this.isDarkMode);
      
      // Apply the theme change
      this.updateDarkMode();
      
      // Prevent default when invoked through keyboard or button
      if (event) {
        event.preventDefault();
        event.stopPropagation();
      }
      
      // Log the change
      console.log("[DarkModeController] Theme toggled to:", this.isDarkMode ? "dark" : "light");
    } catch (e) {
      console.error("[DarkModeController] Error during toggle:", e);
    }
  }
  
  // Handle keyboard shortcut (Shift+D)
  handleKeyDown(event) {
    // Only trigger when not in an input field
    if (this.isEditableElement(event.target)) return
    
    if (event.key === 'D' && event.shiftKey && !event.ctrlKey && !event.altKey && !event.metaKey) {
      event.preventDefault()
      this.toggle()
    }
  }
  
  // Update toggle button appearance with fixed rendering
  updateToggleAppearance() {
    if (!this.hasToggleTarget) return;
    
    try {
      console.log("[DarkModeController] Updating toggle appearance for state:", this.isDarkMode);
      
      // Update ARIA state
      this.toggleTarget.setAttribute("aria-checked", this.isDarkMode.toString());
      
      // We don't need to manually add/remove classes here anymore
      // The CSS in ui_fixes.css will handle the styling based on 
      // the dark-theme-active/light-theme-active classes
      
      // Create icon containers if they don't exist yet
      if (!this.toggleTarget.querySelector('.light-icon') || !this.toggleTarget.querySelector('.dark-icon')) {
        // Clear toggle content first
        this.toggleTarget.innerHTML = '';
        
        // Create light mode icon
        const lightIcon = document.createElement('span');
        lightIcon.className = "light-icon";
        lightIcon.innerHTML = '<svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 3v1m0 16v1m9-9h-1M4 12H3m15.364 6.364l-.707-.707M6.343 6.343l-.707-.707m12.728 0l-.707.707M6.343 17.657l-.707.707M16 12a4 4 0 11-8 0 4 4 0 018 0z" /></svg>';
        this.toggleTarget.appendChild(lightIcon);
        
        // Create dark mode icon
        const darkIcon = document.createElement('span');
        darkIcon.className = "dark-icon"; 
        darkIcon.innerHTML = '<svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M20.354 15.354A9 9 0 018.646 3.646 9.003 9.003 0 0012 21a9.003 9.003 0 008.354-5.646z" /></svg>';
        this.toggleTarget.appendChild(darkIcon);
      }
      
      // Apply a highlight to indicate change
      this.toggleTarget.classList.add("ring", "ring-offset-2", "ring-indigo-400");
      setTimeout(() => {
        this.toggleTarget.classList.remove("ring", "ring-offset-2", "ring-indigo-400");
      }, 300);
      
    } catch (e) {
      console.error("[DarkModeController] Error updating toggle appearance:", e);
    }
  }
  
  // Update the UI based on dark mode state
  updateDarkMode() {
    try {
      console.log("[DarkModeController] Updating dark mode UI state:", this.isDarkMode);
      
      // Apply immediately to prevent flicker
      if (this.isDarkMode) {
        document.documentElement.classList.add("dark");
      } else {
        document.documentElement.classList.remove("dark");
      }
      
      // Update toggle button appearance
      this.updateToggleAppearance();
      
      // Update the mode text if target is available
      if (this.hasModeTextTarget) {
        const newText = this.isDarkMode ? "Dark" : "Light";
        
        // Enhance the fade-out/fade-in animation
        this.modeTextTarget.style.transition = "opacity 200ms ease-in-out, transform 200ms ease-in-out";
        this.modeTextTarget.style.opacity = "0";
        this.modeTextTarget.style.transform = "translateY(-5px)";
        
        setTimeout(() => {
          this.modeTextTarget.textContent = newText;
          this.modeTextTarget.style.opacity = "1";
          this.modeTextTarget.style.transform = "translateY(0)";
        }, 200);
      }
      
      // Update theme-color meta tag for browser chrome
      if (this.hasThemeColorTarget) {
        this.themeColorTarget.content = this.isDarkMode 
          ? this.darkThemeColorValue 
          : this.lightThemeColorValue;
      }
      
      // Dispatch a custom event for other components to react to theme changes
      document.documentElement.dispatchEvent(
        new CustomEvent("themeChanged", { 
          detail: { 
            isDarkMode: this.isDarkMode 
          }
        })
      );
      
      // Create a class to identify dark mode state at the body level
      // This helps with potential CSS selector specificity issues
      const bodyElement = document.querySelector('body');
      if (bodyElement) {
        if (this.isDarkMode) {
          bodyElement.classList.add('dark-theme-active');
          bodyElement.classList.remove('light-theme-active');
        } else {
          bodyElement.classList.add('light-theme-active');
          bodyElement.classList.remove('dark-theme-active');
        }
      }
    } catch (e) {
      console.error("[DarkModeController] Error updating dark mode:", e);
    }
  }
  
  // Helper to check if element is editable (to avoid triggering shortcuts in inputs)
  isEditableElement(element) {
    if (!element) return false;
    
    const tagName = element.tagName?.toLowerCase();
    if (!tagName) return false;
    
    const type = element.type && element.type.toLowerCase();
    
    return (
      (tagName === 'input' &&
        ['text', 'email', 'number', 'password', 'search', 'tel', 'url'].includes(type)
      ) ||
      tagName === 'textarea' ||
      element.isContentEditable
    );
  }
}
