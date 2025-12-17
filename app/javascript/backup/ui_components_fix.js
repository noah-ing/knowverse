/**
 * UI Components Fix
 * 
 * This script adds critical fixes for UI components that might break when the asset
 * pipeline changes. It provides fallback mechanisms for essential UI interactions
 * like dropdowns and dark mode toggle.
 */

document.addEventListener('DOMContentLoaded', () => {
  console.log('UI Components Fix loaded');
  
  // Fix for dropdown menus
  fixDropdowns();
  
  // Fix for dark mode toggle
  fixDarkModeToggle();
  
  // Add event listeners for debugging
  addDebugEventListeners();
});

/**
 * Fixes dropdown menus that might not be working due to asset pipeline issues
 */
function fixDropdowns() {
  const dropdownControllers = document.querySelectorAll('[data-controller="dropdown"]');
  
  if (dropdownControllers.length === 0) {
    console.warn('No dropdown controllers found');
    return;
  }
  
  console.log(`Found ${dropdownControllers.length} dropdown controllers`);
  
  dropdownControllers.forEach((controller, index) => {
    const button = controller.querySelector('[data-dropdown-target="button"]');
    const menu = controller.querySelector('[data-dropdown-target="menu"]');
    
    if (!button || !menu) {
      console.warn(`Dropdown #${index} missing button or menu elements`);
      return;
    }
    
    // Add direct click handler in case Stimulus controller isn't working
    button.addEventListener('click', (event) => {
      event.stopPropagation();
      
      // Check if menu is currently hidden
      const isHidden = menu.classList.contains('hidden') || 
                      window.getComputedStyle(menu).display === 'none' ||
                      menu.style.opacity === '0';
      
      if (isHidden) {
        // Show dropdown
        menu.classList.remove('hidden');
        menu.classList.add('opacity-100', 'translate-y-0');
        menu.classList.remove('opacity-0', 'translate-y-1');
        button.setAttribute('aria-expanded', 'true');
        
        // Add click-outside handler
        setTimeout(() => {
          document.addEventListener('click', closeDropdown);
        }, 10);
      } else {
        // Hide dropdown
        closeDropdown();
      }
      
      function closeDropdown(e) {
        if (e && controller.contains(e.target) && e.target !== button) {
          return;
        }
        
        menu.classList.add('opacity-0', 'translate-y-1');
        menu.classList.remove('opacity-100', 'translate-y-0');
        button.setAttribute('aria-expanded', 'false');
        
        // Hide completely after animation
        setTimeout(() => {
          menu.classList.add('hidden');
        }, 150);
        
        document.removeEventListener('click', closeDropdown);
      }
    });
  });
}

/**
 * Fixes dark mode toggle that might not be working due to asset pipeline issues
 */
function fixDarkModeToggle() {
  const darkModeControllers = document.querySelectorAll('[data-controller="dark-mode"]');
  
  if (darkModeControllers.length === 0) {
    console.warn('No dark-mode controllers found');
    return;
  }
  
  console.log(`Found ${darkModeControllers.length} dark-mode controllers`);
  
  darkModeControllers.forEach((controller, index) => {
    const toggle = controller.querySelector('[data-dark-mode-target="toggle"]');
    const modeText = controller.querySelector('[data-dark-mode-target="modeText"]');
    
    if (!toggle) {
      console.warn(`Dark mode controller #${index} missing toggle element`);
      return;
    }
    
    // Initialize state from localStorage or system preference
    let isDarkMode = localStorage.getItem('darkMode') === 'true';
    if (localStorage.getItem('darkMode') === null) {
      isDarkMode = window.matchMedia('(prefers-color-scheme: dark)').matches;
    }
    
    // Add direct click handler in case Stimulus controller isn't working
    toggle.addEventListener('click', () => {
      isDarkMode = !isDarkMode;
      updateDarkMode();
      localStorage.setItem('darkMode', isDarkMode);
    });
    
    // Add keyboard shortcut (Shift+D)
    document.addEventListener('keydown', (event) => {
      if (event.key === 'D' && event.shiftKey && !event.ctrlKey && !event.altKey && !event.metaKey) {
        // Skip if in input field
        if (document.activeElement.tagName === 'INPUT' || 
            document.activeElement.tagName === 'TEXTAREA' || 
            document.activeElement.isContentEditable) {
          return;
        }
        
        event.preventDefault();
        isDarkMode = !isDarkMode;
        updateDarkMode();
        localStorage.setItem('darkMode', isDarkMode);
      }
    });
    
    // Update UI based on current state
    function updateDarkMode() {
      if (isDarkMode) {
        document.documentElement.classList.add('dark');
      } else {
        document.documentElement.classList.remove('dark');
      }
      
      // Update toggle appearance and ARIA state
      toggle.classList.toggle('dark', isDarkMode);
      toggle.setAttribute('aria-checked', isDarkMode.toString());
      
      // Update mode text if present
      if (modeText) {
        modeText.textContent = isDarkMode ? 'Dark' : 'Light';
      }
    }
    
    // Initialize on page load
    updateDarkMode();
  });
}

/**
 * Adds debug event listeners to help diagnose UI issues
 */
function addDebugEventListeners() {
  // Highlight interactive elements on hover with Alt key
  document.addEventListener('mouseover', (event) => {
    if (event.altKey) {
      const target = event.target;
      
      if (target.hasAttribute('data-controller') || 
          target.hasAttribute('data-action') || 
          target.hasAttribute('data-target')) {
        
        // Add temporary highlight class
        target.classList.add('debug-highlight');
        
        // Show debug tooltip with controller info
        const tooltip = document.createElement('div');
        tooltip.className = 'debug-tooltip';
        tooltip.style.position = 'absolute';
        tooltip.style.zIndex = '9999';
        tooltip.style.background = 'rgba(0,0,0,0.8)';
        tooltip.style.color = 'white';
        tooltip.style.padding = '5px';
        tooltip.style.borderRadius = '3px';
        tooltip.style.fontSize = '12px';
        tooltip.style.maxWidth = '300px';
        
        let info = '';
        if (target.hasAttribute('data-controller')) {
          info += `Controller: ${target.getAttribute('data-controller')}<br>`;
        }
        if (target.hasAttribute('data-action')) {
          info += `Action: ${target.getAttribute('data-action')}<br>`;
        }
        
        // Add targets info
        const targets = Array.from(target.attributes)
          .filter(attr => attr.name.includes('data-') && attr.name.includes('-target'))
          .map(attr => `${attr.name}: ${attr.value}`);
        
        if (targets.length > 0) {
          info += `Targets: ${targets.join(', ')}<br>`;
        }
        
        tooltip.innerHTML = info;
        
        // Position tooltip
        const rect = target.getBoundingClientRect();
        tooltip.style.top = `${rect.bottom + window.scrollY + 5}px`;
        tooltip.style.left = `${rect.left + window.scrollX}px`;
        
        document.body.appendChild(tooltip);
        
        // Clean up
        target.addEventListener('mouseout', () => {
          target.classList.remove('debug-highlight');
          if (tooltip.parentNode) {
            tooltip.parentNode.removeChild(tooltip);
          }
        }, { once: true });
      }
    }
  });
}
