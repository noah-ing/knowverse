/**
 * UI Elements Resilience
 * 
 * This script enhances UI resilience by removing the need for inline styles and 
 * providing fallback functionality for critical UI components.
 */

document.addEventListener('DOMContentLoaded', () => {
  console.log('[UI Resilience] Initializing UI resilience layer');
  
  // Initialize all resilience features
  initializeAnimations();
  initializeProgressBars();
  enhanceDropdowns();
  enhanceDarkMode();
  enhanceMobileMenu();
  prepareBackgroundImages();
});

/**
 * Converts inline style-based animations to class-based animations
 */
function initializeAnimations() {
  // Convert style="animation-delay: Xms" to class-based delays
  document.querySelectorAll('[style*="animation-delay"]').forEach(element => {
    const delayMatch = element.getAttribute('style').match(/animation-delay:\s*(\d+)ms/);
    if (delayMatch && delayMatch[1]) {
      const delayValue = parseInt(delayMatch[1]);
      const closestDelay = Math.floor(delayValue / 50) * 50;
      const delayClass = `delay-${closestDelay / 50}`;
      
      // Add the appropriate delay class
      element.classList.add(delayClass);
      
      // Remove the inline style animation delay
      const newStyle = element.getAttribute('style').replace(/animation-delay:\s*\d+ms;?/g, '').trim();
      if (newStyle) {
        element.setAttribute('style', newStyle);
      } else {
        element.removeAttribute('style');
      }
    }
  });
  
  // Add data-anim-index to children of specific containers for progressive animation
  document.querySelectorAll('.kv-anim-children').forEach(container => {
    Array.from(container.children).forEach((child, index) => {
      child.setAttribute('data-anim-index', index + 1);
    });
  });
}

/**
 * Converts inline width styles for progress bars to class-based or data-attribute approaches
 */
function initializeProgressBars() {
  // Find all elements with inline width styles likely to be progress bars
  document.querySelectorAll('[style*="width:"]').forEach(element => {
    // Extract the width percentage
    const widthMatch = element.getAttribute('style').match(/width:\s*(\d+)%/);
    if (widthMatch && widthMatch[1]) {
      const widthValue = parseInt(widthMatch[1]);
      
      // For exact 5% increments, use class-based approach
      if (widthValue % 5 === 0) {
        element.classList.add(`w-${widthValue}`);
      } else {
        // For custom widths, use CSS variable
        element.style.setProperty('--target-width', `${widthValue}%`);
        element.classList.add('kv-progress-bar');
      }
      
      // Store the width as a data attribute for extra resilience
      element.setAttribute('data-width', `${widthValue}%`);
      
      // Remove the inline width style
      const newStyle = element.getAttribute('style').replace(/width:\s*\d+%;?/g, '').trim();
      if (newStyle) {
        element.setAttribute('style', newStyle);
      } else {
        element.removeAttribute('style');
      }
    }
  });
}

/**
 * Enhance dropdowns with additional resilience
 */
function enhanceDropdowns() {
  // Find all dropdown controllers
  document.querySelectorAll('[data-controller="dropdown"]').forEach(dropdown => {
    const button = dropdown.querySelector('[data-dropdown-target="button"]');
    const menu = dropdown.querySelector('[data-dropdown-target="menu"]');
    
    if (!button || !menu) return;
    
    // Ensure menu has proper starting classes for animation
    menu.classList.add('transition-all', 'duration-300', 'transform');
    
    // Add extra resilience in case Stimulus controller fails
    button.addEventListener('click', (event) => {
      event.stopPropagation();
      event.preventDefault(); // Prevent default behavior to ensure our handler runs
      
      // Directly toggle the dropdown without relying on Stimulus
      const isHidden = menu.classList.contains('hidden');
      
      if (isHidden) {
        // Show the dropdown
        menu.classList.remove('hidden');
        menu.classList.remove('opacity-0', 'scale-95');
        menu.classList.add('opacity-100', 'scale-100');
        button.setAttribute('aria-expanded', 'true');
      } else {
        // Hide the dropdown
        menu.classList.remove('opacity-100', 'scale-100');
        menu.classList.add('opacity-0', 'scale-95');
        button.setAttribute('aria-expanded', 'false');
        
        // Delay adding the hidden class to allow for animation
        setTimeout(() => {
          if (button.getAttribute('aria-expanded') === 'false') {
            menu.classList.add('hidden');
          }
        }, 300);
      }
    }, { passive: false });
    
    // Add document click handler to close dropdown when clicking outside
    document.addEventListener('click', (event) => {
      if (!menu.classList.contains('hidden') && 
          !dropdown.contains(event.target)) {
        menu.classList.remove('opacity-100', 'scale-100');
        menu.classList.add('opacity-0', 'scale-95');
        button.setAttribute('aria-expanded', 'false');
        
        setTimeout(() => {
          menu.classList.add('hidden');
        }, 300);
      }
    });
  });
  
  // Add a mutation observer to handle dynamically added dropdowns
  const observer = new MutationObserver((mutations) => {
    mutations.forEach((mutation) => {
      if (mutation.addedNodes.length) {
        mutation.addedNodes.forEach((node) => {
          if (node.nodeType === 1 && node.hasAttribute('data-controller') && 
              node.getAttribute('data-controller').includes('dropdown')) {
            const button = node.querySelector('[data-dropdown-target="button"]');
            const menu = node.querySelector('[data-dropdown-target="menu"]');
            
            if (button && menu) {
              button.addEventListener('click', (event) => {
                event.stopPropagation();
                const isHidden = menu.classList.contains('hidden');
                menu.classList.toggle('hidden', !isHidden);
                button.setAttribute('aria-expanded', isHidden ? 'true' : 'false');
              });
            }
          }
        });
      }
    });
  });
  
  observer.observe(document.body, { childList: true, subtree: true });
}

/**
 * Enhance dark mode toggle with additional resilience
 */
function enhanceDarkMode() {
  document.querySelectorAll('[data-controller="dark-mode"]').forEach(controller => {
    const toggle = controller.querySelector('[data-dark-mode-target="toggle"]');
    const modeText = controller.querySelector('[data-dark-mode-target="modeText"]');
    
    if (!toggle) return;
    
    // Check if the toggle has the necessary classes
    if (!toggle.classList.contains('kv-dark-mode-toggle')) {
      toggle.classList.add('kv-dark-mode-toggle');
    }
    
    // Ensure the toggle has accessibility attributes
    if (!toggle.hasAttribute('role')) {
      toggle.setAttribute('role', 'switch');
    }
    
    // Add keyboard support for accessibility
    toggle.addEventListener('keydown', (event) => {
      if (event.key === 'Enter' || event.key === ' ') {
        event.preventDefault();
        toggle.click();
      }
    });
    
    // Ensure ARIA state is set correctly
    const isDarkMode = document.documentElement.classList.contains('dark');
    toggle.setAttribute('aria-checked', isDarkMode.toString());
    
    if (modeText) {
      modeText.textContent = isDarkMode ? 'Dark' : 'Light';
    }
  });
}

/**
 * Enhance mobile menu with additional resilience
 */
function enhanceMobileMenu() {
  document.querySelectorAll('[data-controller="mobile-menu"]').forEach(controller => {
    const menuButton = controller.querySelector('[data-mobile-menu-target="menuButton"]');
    const panel = controller.querySelector('[data-mobile-menu-target="panel"]');
    const openIcon = controller.querySelector('[data-mobile-menu-target="openIcon"]');
    const closeIcon = controller.querySelector('[data-mobile-menu-target="closeIcon"]');
    
    if (!menuButton || !panel) return;
    
    // Add extra resilience in case Stimulus controller fails
    menuButton.addEventListener('click', () => {
      const isHidden = panel.classList.contains('hidden');
      
      if (isHidden) {
        panel.classList.remove('hidden');
        menuButton.setAttribute('aria-expanded', 'true');
        
        if (openIcon && closeIcon) {
          openIcon.classList.add('hidden');
          closeIcon.classList.remove('hidden');
        }
      } else {
        panel.classList.add('hidden');
        menuButton.setAttribute('aria-expanded', 'false');
        
        if (openIcon && closeIcon) {
          openIcon.classList.remove('hidden');
          closeIcon.classList.add('hidden');
        }
      }
    }, { passive: true });
  });
}

/**
 * Convert inline background-image styles to a more resilient approach
 */
function prepareBackgroundImages() {
  document.querySelectorAll('[style*="background-image"]').forEach(element => {
    const bgMatch = element.getAttribute('style').match(/background-image:\s*url\(['"]?([^'"]+)['"]?\)/);
    if (bgMatch && bgMatch[1]) {
      const imageUrl = bgMatch[1];
      
      // Add a class for styling
      element.classList.add('kv-bg-image');
      
      // Store the URL as a data attribute
      element.setAttribute('data-bg-image', imageUrl);
      
      // Remove the inline style and set the background-image via CSS var
      element.style.backgroundImage = `url('${imageUrl}')`;
      
      // Clean up other background properties that might be inline
      const newStyle = element.getAttribute('style')
        .replace(/background-(image|size|position|repeat):[^;]+;?/g, '')
        .trim();
      
      if (newStyle) {
        element.setAttribute('style', newStyle);
      } else {
        element.removeAttribute('style');
      }
    }
  });
}

/**
 * Event listener for handling custom animation events
 */
document.addEventListener('ui:animate', (event) => {
  const { element, animation, duration, delay } = event.detail;
  if (!element) return;
  
  const targetEl = typeof element === 'string' ? document.querySelector(element) : element;
  if (!targetEl) return;
  
  // Apply the animation
  targetEl.classList.add(`kv-animate-${animation || 'fade-in'}`);
  
  // Apply duration and delay if provided
  if (duration) {
    targetEl.style.animationDuration = `${duration}ms`;
  }
  
  if (delay) {
    targetEl.style.animationDelay = `${delay}ms`;
  }
});

/**
 * Utility function for dynamically updating progress bars
 */
window.KnowVerse = window.KnowVerse || {};
window.KnowVerse.UI = {
  updateProgressBar: (selector, percentage) => {
    const progressBar = document.querySelector(selector);
    if (!progressBar) return;
    
    progressBar.style.setProperty('--target-width', `${percentage}%`);
    progressBar.setAttribute('data-width', `${percentage}%`);
  }
};
