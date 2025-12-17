// KnowVerse Application JavaScript
// Entry point for the application

// Import Turbo for navigation
import "@hotwired/turbo-rails";

// Import all controllers
import "./controllers";

// Apply dark mode from localStorage on page load before Stimulus initializes
// to prevent flash of incorrect theme
document.addEventListener("DOMContentLoaded", () => {
  try {
    const darkModePref = localStorage.getItem("darkMode");
    if (darkModePref === "true") {
      document.documentElement.classList.add("dark");
    } else if (darkModePref === "false") {
      document.documentElement.classList.remove("dark");
    } else {
      // Check system preference if no localStorage setting
      if (window.matchMedia("(prefers-color-scheme: dark)").matches) {
        document.documentElement.classList.add("dark");
      }
    }
  } catch (e) {
    console.warn("Error accessing localStorage:", e);
  }
});
