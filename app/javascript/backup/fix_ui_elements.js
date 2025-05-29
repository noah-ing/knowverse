 //Simplified UI fixes for KnowVerse that work across all browsers

// Wait for DOM to be ready
document.addEventListener('DOMContentLoaded', function() {
  console.log('KnowVerse UI Fix (Simplified): Adding stable event handlers to UI elements');
  
  // Fix 1: Make the Light/Dark text in header clickable
  const modeTextElements = document.querySelectorAll('[data-dark-mode-target="modeText"]');
  modeTextElements.forEach(function(element) {
    element.style.cursor = 'pointer';
    element.style.textDecoration = 'underline';
    element.addEventListener('click', function() {
      console.log('Mode text clicked!');
      // Find the toggle button by its data attribute
      const toggle = document.querySelector('[data-dark-mode-target="toggle"]');
      if (toggle) {
        toggle.click();
      }
    });
  });
  
  // Fix 2: Fix the footer moon icon
  const footerMoonIcons = document.querySelectorAll('footer button[aria-label="Toggle dark mode"]');
  footerMoonIcons.forEach(function(button) {
    button.addEventListener('click', function() {
      console.log('Footer moon clicked!');
      // Find the toggle button by its data attribute
      const toggle = document.querySelector('[data-dark-mode-target="toggle"]');
      if (toggle) {
        toggle.click();
      }
    });
  });
  
  // Fix 3: Enhance dropdown functionality 
  const dropdownButtons = document.querySelectorAll('[data-dropdown-target="button"]');
  dropdownButtons.forEach(function(button) {
    button.addEventListener('click', function() {
      console.log('Dropdown button clicked!');
      const dropdown = this.closest('[data-controller="dropdown"]');
      if (dropdown) {
        const menu = dropdown.querySelector('[data-dropdown-target="menu"]');
        if (menu) {
          // Toggle class
          if (menu.classList.contains('hidden')) {
            menu.classList.remove('hidden');
            menu.classList.remove('opacity-0');
            menu.classList.remove('scale-95');
          } else {
            menu.classList.add('hidden');
          }
          console.log('Toggled dropdown menu via data attribute');
        }
      }
    });
  });
  
  // Fix 4: Hide authentication message if user is logged in
  if (document.body.classList.contains('user-signed-in')) {
    document.querySelectorAll('.dashboard-signin-required, .signin-required, .auth-message').forEach(function(msg) {
      msg.style.display = 'none';
    });
  }
  
  // Additional safety: ensure dropdown menus can be closed when clicking outside
  document.addEventListener('click', function(event) {
    const dropdowns = document.querySelectorAll('[data-controller="dropdown"]');
    dropdowns.forEach(function(dropdown) {
      if (!dropdown.contains(event.target)) {
        const menu = dropdown.querySelector('[data-dropdown-target="menu"]');
        if (menu && !menu.classList.contains('hidden')) {
          menu.classList.add('hidden');
        }
      }
    });
  });
  
  // Manually make the dark/light mode text clickable 
  // This is a fallback approach using direct text content
  document.querySelectorAll('span').forEach(function(span) {
    if (span.textContent.trim() === 'Light' || span.textContent.trim() === 'Dark') {
      span.style.cursor = 'pointer';
      span.style.fontWeight = 'bold';
      span.addEventListener('click', function() {
        const toggle = document.querySelector('[data-dark-mode-target="toggle"]');
        if (toggle) toggle.click();
      });
    }
  });
  
  console.log('UI fixes applied successfully');
});
