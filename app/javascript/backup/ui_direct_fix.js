/**
 * UI Direct Fix - Emergency fixes for critical UI components
 * This script uses direct DOM manipulation to ensure UI components work
 * regardless of controller issues
 */

document.addEventListener("DOMContentLoaded", function() {
  console.log("[UI Direct Fix] Initializing emergency UI fixes");
  
  // Fix dropdown menus
  fixDropdowns();
  
  // Fix dark mode toggle
  fixDarkModeToggle();
  
  // Fix authentication display issues
  fixAuthenticationDisplay();
  
  // Fix route-related issues
  fixRouteIssues();
  
  // Add global debug event listener
  addDebugEventListener();
});

/**
 * Fix dropdown menus by adding direct event handlers
 */
function fixDropdowns() {
  const dropdownButtons = document.querySelectorAll('[data-dropdown-target="button"], .dropdown-toggle');
  
  dropdownButtons.forEach(button => {
    // Find the closest dropdown controller
    const dropdown = button.closest('[data-controller="dropdown"]') || button.closest('.dropdown');
    if (!dropdown) return;
    
    // Find the menu associated with this button
    const menu = dropdown.querySelector('[data-dropdown-target="menu"]') || dropdown.querySelector('.dropdown-menu');
    if (!menu) return;
    
    // Remove existing handlers to avoid duplicates
    button.removeEventListener('click', dropdownClickHandler);
    
    // Add the click handler
    button.addEventListener('click', dropdownClickHandler);
    
    // Function to handle dropdown clicks
    function dropdownClickHandler(event) {
      event.preventDefault();
      event.stopPropagation();
      
      console.log("[UI Direct Fix] Dropdown button clicked", button);
      
      // Toggle menu visibility
      const isHidden = menu.classList.contains('hidden') || 
                      menu.style.display === 'none' || 
                      menu.getAttribute('aria-hidden') === 'true';
      
      // First hide all other menus
      document.querySelectorAll('[data-dropdown-target="menu"]:not(.hidden), .dropdown-menu:not(.hidden)').forEach(openMenu => {
        if (openMenu !== menu) {
          hideDropdownMenu(openMenu);
        }
      });
      
      if (isHidden) {
        showDropdownMenu(menu, button);
      } else {
        hideDropdownMenu(menu, button);
      }
    }
  });
  
  // Add global click handler to close dropdowns when clicking outside
  document.removeEventListener('click', documentClickHandler); // Remove to avoid duplicates
  document.addEventListener('click', documentClickHandler);
  
  function documentClickHandler(event) {
    const openMenus = document.querySelectorAll('[data-dropdown-target="menu"]:not(.hidden), .dropdown-menu:not(.hidden)');
    
    openMenus.forEach(menu => {
      const dropdown = menu.closest('[data-controller="dropdown"]') || menu.closest('.dropdown');
      const button = dropdown?.querySelector('[data-dropdown-target="button"]') || dropdown?.querySelector('.dropdown-toggle');
      
      if (dropdown && !dropdown.contains(event.target)) {
        hideDropdownMenu(menu, button);
      }
    });
  }
  
  function showDropdownMenu(menu, button) {
    // Use setTimeout to ensure we run after any competing event handlers
    setTimeout(() => {
      // Show and animate the menu
      menu.classList.remove('hidden', 'opacity-0', 'translate-y-1', 'scale-95');
      menu.classList.add('opacity-100', 'translate-y-0', 'scale-100');
      menu.style.display = '';
      menu.setAttribute('aria-hidden', 'false');
      
      if (button) {
        button.setAttribute('aria-expanded', 'true');
      }
      
      console.log("[UI Direct Fix] Dropdown menu shown", menu);
    }, 10);
  }
  
  function hideDropdownMenu(menu, button) {
    // First animate
    menu.classList.add('opacity-0', 'translate-y-1', 'scale-95');
    menu.classList.remove('opacity-100', 'translate-y-0', 'scale-100');
    
    // Then hide after animation completes
    setTimeout(() => {
      menu.classList.add('hidden');
      menu.setAttribute('aria-hidden', 'true');
      
      if (button) {
        button.setAttribute('aria-expanded', 'false');
      }
      
      console.log("[UI Direct Fix] Dropdown menu hidden", menu);
    }, 150);
  }
  
  console.log(`[UI Direct Fix] Fixed ${dropdownButtons.length} dropdown menus`);
}

/**
 * Fix dark mode toggle with direct implementation and improved styling
 */
function fixDarkModeToggle() {
  const darkModeToggles = document.querySelectorAll('.kv-dark-mode-toggle, [data-dark-mode-target="toggle"]');
  
  // Apply visual styling to dark mode toggle
  const styleElement = document.createElement('style');
  styleElement.textContent = `
    .kv-dark-mode-toggle {
      width: 48px;
      height: 24px;
      position: relative;
      background: #e2e8f0;
      border-radius: 24px;
      cursor: pointer;
      transition: all 0.3s ease;
      display: inline-flex;
      align-items: center;
      justify-content: space-between;
      padding: 2px 4px;
      border: 2px solid transparent;
    }
    
    .kv-dark-mode-toggle::before {
      content: "";
      position: absolute;
      width: 18px;
      height: 18px;
      border-radius: 50%;
      left: 3px;
      transform: translateX(0);
      background: white;
      transition: transform 0.3s ease, background 0.3s ease;
      box-shadow: 0 1px 3px rgba(0, 0, 0, 0.1);
    }
    
    .kv-dark-mode-toggle.dark {
      background: #4b5563;
    }
    
    .kv-dark-mode-toggle.dark::before {
      transform: translateX(22px);
      background: #f3f4f6;
    }
    
    .kv-dark-mode-toggle:focus {
      outline: none;
      border-color: #4f46e5;
    }
  `;
  document.head.appendChild(styleElement);
  
  darkModeToggles.forEach(toggle => {
    // Make sure the toggle has the correct styling class
    if (!toggle.classList.contains('kv-dark-mode-toggle')) {
      toggle.classList.add('kv-dark-mode-toggle');
    }
    
    // Read the current mode from HTML element or localStorage
    const isDarkMode = document.documentElement.classList.contains('dark') || 
                       localStorage.getItem('darkMode') === 'true';
    
    // Set initial state
    if (isDarkMode) {
      document.documentElement.classList.add('dark');
      toggle.classList.add('dark');
      toggle.setAttribute('aria-checked', 'true');
    } else {
      document.documentElement.classList.remove('dark');
      toggle.classList.remove('dark');
      toggle.setAttribute('aria-checked', 'false');
    }
    
    // Update any mode text elements
    const modeTextElements = document.querySelectorAll('[data-dark-mode-target="modeText"]');
    modeTextElements.forEach(el => {
      el.textContent = isDarkMode ? 'Dark' : 'Light';
    });
    
    // Remove existing click listener to avoid duplicates
    toggle.removeEventListener('click', darkModeClickHandler);
    
    // Add direct click handler
    toggle.addEventListener('click', darkModeClickHandler);
    
    function darkModeClickHandler() {
      const currentDarkMode = document.documentElement.classList.contains('dark');
      
      console.log("[UI Direct Fix] Dark mode toggle clicked, current state:", currentDarkMode);
      
      // Toggle dark mode
      if (currentDarkMode) {
        document.documentElement.classList.remove('dark');
        toggle.classList.remove('dark');
        localStorage.setItem('darkMode', 'false');
        toggle.setAttribute('aria-checked', 'false');
      } else {
        document.documentElement.classList.add('dark');
        toggle.classList.add('dark');
        localStorage.setItem('darkMode', 'true');
        toggle.setAttribute('aria-checked', 'true');
      }
      
      // Update any mode text elements
      modeTextElements.forEach(el => {
        el.textContent = !currentDarkMode ? 'Dark' : 'Light';
      });
      
      // Dispatch custom event for other components
      document.documentElement.dispatchEvent(new CustomEvent('themeChanged', { 
        detail: { isDarkMode: !currentDarkMode } 
      }));
      
      console.log("[UI Direct Fix] Dark mode toggled to:", !currentDarkMode);
    }
  });
  
  console.log(`[UI Direct Fix] Fixed ${darkModeToggles.length} dark mode toggles`);
}

/**
 * Fix authentication display issues by checking for auth indicators
 */
function fixAuthenticationDisplay() {
  // Look for auth indicators in the DOM
  const isAuthenticated = 
    document.body.classList.contains('user-signed-in') || 
    document.querySelectorAll('.signed-in-indicator').length > 0 ||
    document.querySelectorAll('[data-authenticated="true"]').length > 0 ||
    document.querySelector('[data-dropdown-target="button"]')?.textContent.includes('Profile') ||
    document.querySelector('.dropdown-toggle')?.textContent.includes('Profile');
  
  if (isAuthenticated) {
    // User is authenticated, make dashboard content visible
    const dashboardContent = document.querySelector('.dashboard-content');
    if (dashboardContent) {
      dashboardContent.classList.remove('hidden');
    }
    
    // Remove "Only visible when logged in" if it's a placeholder
    const loginPlaceholders = document.querySelectorAll('.login-required-placeholder');
    loginPlaceholders.forEach(placeholder => {
      placeholder.classList.add('hidden');
    });
    
    // Update any authentication dependent sections
    document.querySelectorAll('[data-auth-required]').forEach(el => {
      el.classList.remove('hidden');
    });
    
    // Mark the body as authenticated with a data attribute for CSS selectors
    document.body.setAttribute('data-user-authenticated', 'true');
  }
  
  console.log(`[UI Direct Fix] Authentication status: ${isAuthenticated ? 'Authenticated' : 'Not authenticated'}`);
}

/**
 * Fix common route issues
 */
function fixRouteIssues() {
  // Fix links to documents
  const documentLinks = document.querySelectorAll('a[href^="/documents/"]');
  documentLinks.forEach(link => {
    // Get current organization ID from URL or meta tag
    const currentOrgId = getCurrentOrganizationId();
    if (currentOrgId) {
      // Update the link to include organization context
      const origHref = link.getAttribute('href');
      if (origHref && !origHref.includes('/organizations/')) {
        const newHref = `/organizations/${currentOrgId}${origHref}`;
        link.setAttribute('href', newHref);
        console.log(`[UI Direct Fix] Updated document link from ${origHref} to ${newHref}`);
      }
    }
  });
  
  // Fix search links
  const searchLinks = document.querySelectorAll('a[href="/search"]');
  searchLinks.forEach(link => {
    // If search route needs to be within organization context
    const orgId = getCurrentOrganizationId();
    if (orgId) {
      link.setAttribute('href', `/search?organization_id=${orgId}`);
    }
  });
}

/**
 * Helper function to get current organization ID
 */
function getCurrentOrganizationId() {
  // Try to get from URL
  const orgMatch = window.location.pathname.match(/\/organizations\/(\d+)/);
  if (orgMatch && orgMatch[1]) {
    return orgMatch[1];
  }
  
  // Try to get from meta tag
  const orgMeta = document.querySelector('meta[name="current-organization-id"]');
  if (orgMeta) {
    return orgMeta.getAttribute('content');
  }
  
  // Try to get from a data attribute on body
  const orgData = document.body.getAttribute('data-organization-id');
  if (orgData) {
    return orgData;
  }
  
  return null;
}

/**
 * Add debug event listener to help troubleshoot issues
 */
function addDebugEventListener() {
  const isDevEnv = window.location.hostname === 'localhost' || 
                  window.location.hostname === '127.0.0.1';
  
  if (isDevEnv) {
    document.addEventListener('keydown', function(e) {
      // Ctrl+Shift+D for debug info
      if (e.ctrlKey && e.shiftKey && e.key === 'D') {
        e.preventDefault();
        
        console.group('UI Debug Information');
        console.log('Dark mode active:', document.documentElement.classList.contains('dark'));
        console.log('Authentication state:', document.body.classList.contains('user-signed-in'));
        
        const dropdowns = document.querySelectorAll('[data-controller="dropdown"]');
        console.log(`Dropdowns on page: ${dropdowns.length}`);
        dropdowns.forEach((dropdown, i) => {
          const button = dropdown.querySelector('[data-dropdown-target="button"]');
          const menu = dropdown.querySelector('[data-dropdown-target="menu"]');
          console.log(`Dropdown ${i+1}:`, {
            button: button ? button.textContent.trim() : 'Missing',
            menu: menu ? (!menu.classList.contains('hidden') ? 'Visible' : 'Hidden') : 'Missing'
          });
        });
        
        console.log('Current organization ID:', getCurrentOrganizationId());
        console.groupEnd();
        
        alert('UI Debug information logged to console (Ctrl+Shift+I to view)');
      }
    });
  }
}
