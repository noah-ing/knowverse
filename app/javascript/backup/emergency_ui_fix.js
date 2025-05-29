/**
 * EMERGENCY UI FIX - ENHANCED VERSION
 * This is a completely standalone script that fixes critical UI elements 
 * using direct DOM manipulation, with detection for Stimulus controller conflicts
 * and special handling for route links.
 */

// Wait for DOM to be ready
document.addEventListener('DOMContentLoaded', function() {
  console.log('[EMERGENCY UI FIX] Initializing...');
  
  // Add console tracing for debugging
  addConsoleDiagnostics();
  
  // Fix routing links
  fixRouteLinks();
  
  // Fix dark mode toggle immediately
  fixDarkModeToggle();
  
  // Fix dropdown menus
  fixDropdownMenus();
  
  // Set a small delay to ensure this runs after any other scripts
  setTimeout(function() {
    console.log('[EMERGENCY UI FIX] Running delayed fixes and checks...');
    checkControllerEffectiveness();
    fixDropdownMenus(); // Run again after delay
    fixDarkModeToggle(); // Run again after delay
  }, 500);
  
  // Run periodic checks to ensure fixes stay applied
  // (in case a Turbo navigation or other event replaces DOM elements)
  setInterval(function() {
    fixDropdownMenus();
    fixDarkModeToggle();
  }, 3000);
});

/**
 * Add console diagnostics to help with debugging
 */
function addConsoleDiagnostics() {
  // Log when Stimulus controllers are connected
  if (window.Stimulus) {
    console.log('[EMERGENCY UI FIX] Stimulus detected, adding controller connection logging');
    
    const originalControllerConstructor = window.Stimulus.Controller;
    window.Stimulus.Controller = class extends originalControllerConstructor {
      connect() {
        console.log(`[Controller Debug] ${this.identifier} controller connected`, this.element);
        super.connect();
      }
      
      disconnect() {
        console.log(`[Controller Debug] ${this.identifier} controller disconnected`, this.element);
        super.disconnect();
      }
    };
  } else {
    console.log('[EMERGENCY UI FIX] Stimulus not detected, skipping controller instrumentation');
  }
}

/**
 * Check if Stimulus controllers are working effectively
 */
function checkControllerEffectiveness() {
  // Check dropdown controllers
  const dropdownControllers = document.querySelectorAll('[data-controller="dropdown"]');
  console.log(`[EMERGENCY UI FIX] Found ${dropdownControllers.length} dropdown controllers`);
  
  // Check if any dropdowns are visible
  const openDropdowns = document.querySelectorAll('.dropdown-menu:not(.hidden), [data-dropdown-target="menu"]:not(.hidden)');
  console.log(`[EMERGENCY UI FIX] Found ${openDropdowns.length} open dropdown menus`);
  
  // Check dark mode controller
  const darkModeControllers = document.querySelectorAll('[data-controller="dark-mode"]');
  console.log(`[EMERGENCY UI FIX] Found ${darkModeControllers.length} dark mode controllers`);
  
  // Check if dark mode is working
  const isDarkMode = document.documentElement.classList.contains('dark');
  console.log(`[EMERGENCY UI FIX] Dark mode is ${isDarkMode ? 'active' : 'inactive'}`);
}

/**
 * Fix route links for common errors
 */
function fixRouteLinks() {
  // Fix /documents/new links to include organization context
  document.querySelectorAll('a[href="/documents/new"]').forEach(link => {
    // Get the current organization ID from URL or data attribute
    const currentOrgId = getCurrentOrganizationId();
    if (currentOrgId) {
      console.log(`[EMERGENCY UI FIX] Fixing documents/new link to include organization context: ${currentOrgId}`);
      link.href = `/organizations/${currentOrgId}/documents/new`;
      link.setAttribute('data-fixed-by', 'emergency-ui-fix');
    }
  });
  
  // Fix search controller links
  document.querySelectorAll('a[href^="/search/"]').forEach(link => {
    // Only modify links that would go to the non-namespaced controller
    if (!link.href.includes('/organizations/') && !link.getAttribute('data-fixed-by')) {
      const currentOrgId = getCurrentOrganizationId();
      if (currentOrgId) {
        const newPath = link.href.replace('/search/', `/organizations/${currentOrgId}/search/`);
        console.log(`[EMERGENCY UI FIX] Fixing search link: ${link.href} → ${newPath}`);
        link.href = newPath;
        link.setAttribute('data-fixed-by', 'emergency-ui-fix');
      }
    }
  });
  
  // Helper function to get current organization ID from URL or data attribute
  function getCurrentOrganizationId() {
    // Try to extract from URL path first
    const orgMatch = window.location.pathname.match(/\/organizations\/([^\/]+)/);
    if (orgMatch && orgMatch[1]) {
      return orgMatch[1];
    }
    
    // Next, try to find it in a data attribute (common pattern in Rails apps)
    const orgElement = document.querySelector('[data-organization-id]');
    if (orgElement) {
      return orgElement.getAttribute('data-organization-id');
    }
    
    // Finally, check if there's a current organization in a global JS variable
    if (window.currentOrganizationId) {
      return window.currentOrganizationId;
    }
    
    // Fallback to null if we can't determine the organization
    return null;
  }
}

/**
 * Fix dark mode toggle with enhanced detection and error recovery
 */
function fixDarkModeToggle() {
  // Inject critical CSS for the toggle directly into the page (with !important to override conflicts)
  if (!document.getElementById('emergency-dark-mode-style')) {
    const style = document.createElement('style');
    style.id = 'emergency-dark-mode-style';
    style.textContent = `
      .kv-dark-mode-toggle {
        width: 60px !important;
        height: 28px !important;
        border-radius: 14px !important;
        background: #e5e7eb !important;
        position: relative !important;
        cursor: pointer !important;
        transition: all 0.3s !important;
        display: inline-flex !important;
        align-items: center !important;
        padding: 0 5px !important;
        box-shadow: inset 0 1px 2px rgba(0,0,0,0.1) !important;
        z-index: 10 !important;
      }
      
      .kv-dark-mode-toggle.dark {
        background: #4b5563 !important;
      }
      
      .kv-dark-mode-toggle::before {
        content: '' !important;
        position: absolute !important;
        width: 22px !important;
        height: 22px !important;
        border-radius: 50% !important;
        background: white !important;
        left: 3px !important;
        transition: all 0.3s !important;
        box-shadow: 0 1px 3px rgba(0,0,0,0.2) !important;
      }
      
      .kv-dark-mode-toggle.dark::before {
        left: 35px !important;
      }
      
      .kv-dark-mode-toggle-text {
        color: #4b5563 !important;
        margin-right: 28px !important;
        font-size: 12px !important;
        font-weight: 500 !important;
        transition: all 0.3s !important;
      }
      
      .kv-dark-mode-toggle.dark .kv-dark-mode-toggle-text {
        margin-right: 0 !important;
        margin-left: 28px !important;
        color: #e5e7eb !important;
      }
      
      /* Force dark mode styles for core elements */
      html.dark {
        color-scheme: dark !important;
      }
      
      html.dark body {
        background-color: #111827 !important;
        color: #f3f4f6 !important;
      }
    `;
    document.head.appendChild(style);
  }
  
  // Find all possible dark mode toggle elements
  const toggles = document.querySelectorAll('.kv-dark-mode-toggle, [data-dark-mode-target="toggle"]');
  
  if (toggles.length === 0) {
    console.log('[EMERGENCY UI FIX] No dark mode toggle found, creating one');
    
    // If no toggle found, try to add one to the navigation
    const navRight = document.querySelector('header nav .flex.items-center');
    if (navRight) {
      const toggle = document.createElement('div');
      toggle.className = 'kv-dark-mode-toggle mr-3';
      toggle.setAttribute('role', 'switch');
      toggle.innerHTML = '<span class="kv-dark-mode-toggle-text">Light</span>';
      navRight.insertBefore(toggle, navRight.firstChild);
      
      // Now process this new toggle
      processToggle(toggle);
    }
  } else {
    // Process existing toggles
    toggles.forEach(toggle => {
      processToggle(toggle);
    });
  }
  
  function processToggle(toggle) {
    // Ensure the toggle has the right class
    if (!toggle.classList.contains('kv-dark-mode-toggle')) {
      toggle.classList.add('kv-dark-mode-toggle');
    }
    
    // Add text span if not present
    if (!toggle.querySelector('.kv-dark-mode-toggle-text')) {
      const textSpan = document.createElement('span');
      textSpan.className = 'kv-dark-mode-toggle-text';
      toggle.appendChild(textSpan);
    }
    
    // Get current state
    const html = document.documentElement;
    const isDarkMode = html.classList.contains('dark');
    
    // Update toggle state
    toggle.classList.toggle('dark', isDarkMode);
    toggle.setAttribute('aria-checked', isDarkMode ? 'true' : 'false');
    
    // Update text
    const textSpan = toggle.querySelector('.kv-dark-mode-toggle-text');
    if (textSpan) {
      textSpan.textContent = isDarkMode ? 'Dark' : 'Light';
    }
    
    // Remove all existing click handlers and add new one
    toggle.removeEventListener('click', handleDarkModeToggle);
    toggle.addEventListener('click', handleDarkModeToggle);
  }
  
  function handleDarkModeToggle(e) {
    // Get the toggle element
    const toggle = e.currentTarget;
    
    // Get current state
    const html = document.documentElement;
    const isDarkMode = html.classList.contains('dark');
    
    // Toggle dark mode
    html.classList.toggle('dark', !isDarkMode);
    
    // Save to localStorage
    localStorage.setItem('darkMode', !isDarkMode ? 'true' : 'false');
    
    // Update toggle state
    toggle.classList.toggle('dark', !isDarkMode);
    toggle.setAttribute('aria-checked', !isDarkMode ? 'true' : 'false');
    
    // Update text
    const textSpan = toggle.querySelector('.kv-dark-mode-toggle-text');
    if (textSpan) {
      textSpan.textContent = !isDarkMode ? 'Dark' : 'Light';
    }
    
    // Update other toggles
    const allToggles = document.querySelectorAll('.kv-dark-mode-toggle, [data-dark-mode-target="toggle"]');
    allToggles.forEach(otherToggle => {
      if (otherToggle !== toggle) {
        otherToggle.classList.toggle('dark', !isDarkMode);
        otherToggle.setAttribute('aria-checked', !isDarkMode ? 'true' : 'false');
        
        const otherTextSpan = otherToggle.querySelector('.kv-dark-mode-toggle-text');
        if (otherTextSpan) {
          otherTextSpan.textContent = !isDarkMode ? 'Dark' : 'Light';
        }
      }
    });
    
    console.log('[EMERGENCY UI FIX] Dark mode toggled to:', !isDarkMode);
    
    // Prevent the event from bubbling up
    e.stopPropagation();
  }
}

/**
 * Fix dropdown menus with enhanced detection and visual debugging
 */
function fixDropdownMenus() {
  // Add debugging styles to visualize dropdown functionality
  if (!document.getElementById('emergency-dropdown-style')) {
    const style = document.createElement('style');
    style.id = 'emergency-dropdown-style';
    style.textContent = `
      /* Visual indicator for dropdown menus */
      [data-dropdown-target="menu"]:not(.hidden), .dropdown-menu:not(.hidden) {
        border: 2px solid #22c55e !important; /* Green border for visible menus */
        animation: dropdown-pulse 2s infinite;
      }
      
      /* Animation for visible dropdowns to make them more noticeable */
      @keyframes dropdown-pulse {
        0% { box-shadow: 0 0 0 0 rgba(34, 197, 94, 0.4); }
        70% { box-shadow: 0 0 0 5px rgba(34, 197, 94, 0); }
        100% { box-shadow: 0 0 0 0 rgba(34, 197, 94, 0); }
      }
      
      /* Force dropdown menu visibility */
      .force-visible {
        display: block !important;
        visibility: visible !important;
        opacity: 1 !important;
        transform: translateY(0) !important;
        pointer-events: auto !important;
      }
    `;
    document.head.appendChild(style);
  }

  // Find all dropdown buttons
  const dropdownButtons = document.querySelectorAll('[data-dropdown-target="button"], [aria-haspopup="true"]');
  
  dropdownButtons.forEach(button => {
    // Find the closest dropdown controller element
    const dropdown = button.closest('[data-controller="dropdown"]') || button.closest('.dropdown');
    if (!dropdown) return;
    
    // Find the menu associated with this button
    const menu = dropdown.querySelector('[data-dropdown-target="menu"]') || dropdown.querySelector('.dropdown-menu');
    if (!menu) return;
    
    console.log('[EMERGENCY UI FIX] Processing dropdown menu:', button.textContent.trim());
    
    // Check if the menu has the needed classes for transitions
    if (!menu.classList.contains('transform') && !menu.hasAttribute('data-fixed-by-emergency')) {
      menu.classList.add('transform', 'transition-all', 'duration-200', 'ease-out');
      menu.setAttribute('data-fixed-by-emergency', 'true');
    }
    
    // Remove existing listeners to avoid duplicates
    button.removeEventListener('click', handleDropdownClick);
    
    // Add simple click handler
    button.addEventListener('click', handleDropdownClick);
    
    function handleDropdownClick(e) {
      e.preventDefault();
      e.stopPropagation();
      
      const isHidden = menu.classList.contains('hidden');
      
      // Hide all other dropdown menus first
      document.querySelectorAll('[data-dropdown-target="menu"]:not(.hidden), .dropdown-menu:not(.hidden)').forEach(otherMenu => {
        if (otherMenu !== menu) {
          otherMenu.classList.add('hidden');
          otherMenu.classList.remove('force-visible', 'opacity-100', 'scale-100', 'translate-y-0');
        }
      });
      
      // Toggle this menu with multiple class patterns to handle different CSS approaches
      if (isHidden) {
        menu.classList.remove('hidden');
        menu.classList.add('force-visible', 'opacity-100', 'scale-100', 'translate-y-0');
        menu.style.display = 'block';
        
        // For debugging, log the computed style to see if it's actually visible
        const computedStyle = window.getComputedStyle(menu);
        console.log(`[EMERGENCY UI FIX] Menu display: ${computedStyle.display}, visibility: ${computedStyle.visibility}, opacity: ${computedStyle.opacity}`);
      } else {
        menu.classList.add('hidden');
        menu.classList.remove('force-visible', 'opacity-100', 'scale-100', 'translate-y-0');
      }
      
      // Set ARIA states
      button.setAttribute('aria-expanded', isHidden ? 'true' : 'false');
      
      console.log('[EMERGENCY UI FIX] Dropdown toggled:', isHidden ? 'shown' : 'hidden');
    }
  });
  
  // Add global click handler to close dropdowns when clicking outside
  if (!window.__emergency_ui_click_handler_added) {
    document.addEventListener('click', function(e) {
      const openMenus = document.querySelectorAll('[data-dropdown-target="menu"]:not(.hidden), .dropdown-menu:not(.hidden)');
      
      openMenus.forEach(menu => {
        const dropdown = menu.closest('[data-controller="dropdown"]') || menu.closest('.dropdown');
        if (dropdown && !dropdown.contains(e.target)) {
          menu.classList.add('hidden');
          menu.classList.remove('force-visible', 'opacity-100', 'scale-100', 'translate-y-0');
          
          // Reset button state
          const button = dropdown.querySelector('[data-dropdown-target="button"]') || dropdown.querySelector('[aria-haspopup="true"]');
          if (button) {
            button.setAttribute('aria-expanded', 'false');
          }
        }
      });
    });
    
    window.__emergency_ui_click_handler_added = true;
  }
}
