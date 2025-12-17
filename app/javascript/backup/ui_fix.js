/**
 * Emergency UI Fix Script - Direct DOM Manipulation
 * 
 * This script directly addresses the three critical UI issues in KnowVerse:
 * 1. "Light" text in header not toggling dark mode
 * 2. User dropdown menu not opening
 * 3. "Only visible when logged in" message showing when user is logged in
 */

console.log("🔥 Emergency UI Fix Script loaded - Direct fixes for critical issues");

// Execute immediately to fix the UI issues
(function() {
  // Define a global object to track what we've fixed
  const fixed = {
    darkModeToggles: [],
    dropdowns: [],
    authMessages: []
  };
  
  // Run the fixes immediately and also on DOM ready and window load
  function runFixes() {
    console.log("⚡ Running emergency UI fixes");
    
    // 1. Fix the dark mode toggle in header
    fixDarkModeToggle();
    
    // 2. Fix dropdown menu
    fixUserDropdown();
    
    // 3. Fix authentication message
    fixDashboardAuthMessage();
  }
  
  // 1. Fix the "Light" text in header that should toggle dark mode
  function fixDarkModeToggle() {
    console.log("🔍 Looking for dark mode toggle in header");
    
    // Find the Light/Dark text in the header (more specific selector)
    const headerModeText = document.querySelector('header span:contains("Light"), header span:contains("Dark")');
    const modeTextByClass = document.querySelector('.kv-dark-mode-toggle + span, span[data-dark-mode-target="modeText"]');
    let modeText = headerModeText || modeTextByClass;
    
    // If still not found, try by position
    if (!modeText) {
      // Look for all spans in the header area
      const headerSpans = Array.from(document.querySelectorAll('header span'));
      // Find one that says Light or Dark
      modeText = headerSpans.find(span => 
        span.textContent.trim() === 'Light' || 
        span.textContent.trim() === 'Dark'
      );
    }
    
    // Direct fix for the "Light" text in header
    if (modeText) {
      console.log("✅ Found mode text in header:", modeText.textContent);
      
      // Make it obvious it's clickable
      modeText.style.cursor = "pointer";
      modeText.style.textDecoration = "underline";
      modeText.style.fontWeight = "bold";
      
      // Direct click handler to toggle dark mode
      modeText.onclick = function(e) {
        e.preventDefault();
        e.stopPropagation();
        
        console.log("👆 Mode text clicked");
        const isDark = document.documentElement.classList.contains("dark");
        
        // Toggle dark mode
        if (isDark) {
          document.documentElement.classList.remove("dark");
          localStorage.setItem("darkMode", "false");
          this.textContent = "Light";
          console.log("☀️ Switched to light mode");
        } else {
          document.documentElement.classList.add("dark");
          localStorage.setItem("darkMode", "true");
          this.textContent = "Dark";
          console.log("🌙 Switched to dark mode");
        }
        
        // Add animation effect
        this.classList.add("animate-pulse");
        setTimeout(() => {
          this.classList.remove("animate-pulse");
        }, 400);
      };
      
      console.log("✅ Applied click handler to mode text");
    } else {
      console.warn("⚠️ Could not find mode text in header");
    }
    
    // Also fix the moon icon in footer
    const footerMoonIcon = document.querySelector('footer button svg[d*="M20.354 15.354"]');
    if (footerMoonIcon && footerMoonIcon.parentElement) {
      const moonButton = footerMoonIcon.closest('button') || footerMoonIcon.parentElement;
      console.log("✅ Found moon icon in footer");
      
      // Make it obvious it's clickable
      moonButton.style.cursor = "pointer";
      
      // Direct click handler for the moon icon
      moonButton.onclick = function(e) {
        e.preventDefault();
        e.stopPropagation();
        
        const isDark = document.documentElement.classList.contains("dark");
        
        // Toggle dark mode
        if (isDark) {
          document.documentElement.classList.remove("dark");
          localStorage.setItem("darkMode", "false");
        } else {
          document.documentElement.classList.add("dark");
          localStorage.setItem("darkMode", "true");
        }
        
        // Update mode text if found
        if (modeText) {
          modeText.textContent = isDark ? "Light" : "Dark";
        }
        
        console.log(`🌓 Toggled dark mode to ${!isDark ? 'dark' : 'light'}`);
      };
      
      console.log("✅ Applied click handler to footer moon icon");
    } else {
      console.warn("⚠️ Could not find moon icon in footer");
    }
  }
  
  // 2. Fix the dropdown menu that's not opening
  function fixUserDropdown() {
    console.log("🔍 Looking for user dropdown menu");
    
    // Try to find user dropdown using various selectors
    const userButtonSelectors = [
      // By display name and SVG arrow
      'button:has(svg[d*="M5.293 7.293"])',
      // By rounded avatar
      'button:has(.rounded-full)',
      // By user profile dropdown specific attributes
      '[data-dropdown-target="button"], [data-action*="dropdown#toggle"]',
      // By position
      'header .relative button'
    ];
    
    // Try each selector
    let userButton = null;
    let dropdown = null;
    for (const selector of userButtonSelectors) {
      try {
        userButton = document.querySelector(selector);
        if (userButton) {
          // Find the closest dropdown container
          dropdown = userButton.closest('.relative, [data-controller="dropdown"]');
          console.log(`✅ Found user dropdown button with selector: ${selector}`);
          break;
        }
      } catch(e) {
        // Some selectors might not be supported
      }
    }
    
    // If not found, try a more brute force approach - look for buttons with avatar-like elements
    if (!userButton) {
      const allButtons = document.querySelectorAll('header button');
      for (const button of allButtons) {
        // Look for buttons that might have avatar-like elements
        if (button.querySelector('.rounded-full') || 
            button.querySelector('svg') || 
            button.textContent.trim().length < 10) { // Short text might be initials
          userButton = button;
          dropdown = button.closest('.relative');
          break;
        }
      }
    }
    
    // Now search for the menu that should be toggled
    let dropdownMenu = null;
    if (dropdown) {
      // Try various selectors for the menu
      const menuSelectors = [
        '[data-dropdown-target="menu"]',
        '.absolute', 
        '.hidden'
      ];
      
      for (const selector of menuSelectors) {
        dropdownMenu = dropdown.querySelector(selector);
        if (dropdownMenu) {
          console.log(`✅ Found dropdown menu with selector: ${selector}`);
          break;
        }
      }
      
      // If we found both button and menu, apply direct fix
      if (userButton && dropdownMenu) {
        console.log("✅ Applying direct fix to user dropdown");
        
        // Direct click handler that simply toggles the menu visibility
        userButton.onclick = function(e) {
          e.preventDefault();
          e.stopPropagation();
          
          const isHidden = dropdownMenu.classList.contains('hidden');
          
          console.log(`👆 User dropdown button clicked, menu is currently ${isHidden ? 'hidden' : 'visible'}`);
          
          if (isHidden) {
            // Show the menu
            dropdownMenu.classList.remove('hidden');
            userButton.setAttribute('aria-expanded', 'true');
            console.log("📂 Opened dropdown menu");
            
            // Close when clicking outside
            const closeHandler = function(evt) {
              if (!dropdown.contains(evt.target)) {
                dropdownMenu.classList.add('hidden');
                userButton.setAttribute('aria-expanded', 'false');
                document.removeEventListener('click', closeHandler);
                console.log("📁 Closed dropdown menu (clicked outside)");
              }
            };
            
            // Add global click handler after a small delay
            setTimeout(() => {
              document.addEventListener('click', closeHandler);
            }, 10);
            
          } else {
            // Hide the menu
            dropdownMenu.classList.add('hidden');
            userButton.setAttribute('aria-expanded', 'false');
            console.log("📁 Closed dropdown menu");
          }
        };
        
        console.log("✅ Applied click handler to user dropdown button");
      } else {
        console.warn("⚠️ Found dropdown container but couldn't locate menu element");
      }
    } else {
      console.warn("⚠️ Could not find user dropdown");
    }
    
    // Additional fallback: add global handler for any button near a .rounded-full (likely avatar)
    const allAvatars = document.querySelectorAll('.rounded-full');
    for (const avatar of allAvatars) {
      // Look for a button that's a parent or sibling of the avatar
      const button = avatar.closest('button') || 
                    avatar.parentElement?.querySelector('button') || 
                    avatar.parentElement?.parentElement?.querySelector('button');
                    
      if (button) {
        console.log("✅ Found avatar button via fallback method");
        
        // Look for a nearby menu
        const container = button.closest('.relative') || button.parentElement;
        const menu = container?.querySelector('.absolute') || 
                    container?.querySelector('.hidden') || 
                    container?.nextElementSibling;
                    
        if (menu) {
          console.log("✅ Found menu via fallback method");
          
          // Apply click handler
          button.onclick = function(e) {
            e.preventDefault();
            e.stopPropagation();
            menu.classList.toggle('hidden');
            console.log("🔀 Toggled menu visibility (fallback method)");
          };
        }
      }
    }
  }
  
  // Authentication State Fix with enhanced detection and fixes
  function fixAuthenticationState() {
    console.log("🔐 UI Fix: Enhanced authentication state check");
    
    // Multiple authentication indicators for more robust detection
    const authIndicators = [
      document.body.classList.contains('user-signed-in'),
      document.querySelector('[data-user-authenticated="true"]') !== null,
      document.querySelector('.user-signed-in') !== null,
      document.querySelector('.md\\:hidden:has(.rounded-full)') !== null, // User avatar in mobile menu is usually a sign
      document.querySelector('button:has(svg.w-4.h-4)') !== null, // Profile dropdown with arrow
      document.querySelector('[aria-expanded]') !== null // User menu buttons often have aria-expanded
    ];
    
    console.log("Authentication indicators:", authIndicators);
    
    // Check for authenticated user with multiple strategies
    const isAuthenticated = authIndicators.some(indicator => indicator === true);
    
    console.log(`👤 User authentication state: ${isAuthenticated ? 'Authenticated' : 'Not authenticated'}`);
    
    // Add body class and attributes for global styling/detection
    if (isAuthenticated) {
      document.body.classList.add('user-authenticated', 'user-signed-in');
      document.body.setAttribute('data-user-authenticated', 'true');
      
      // Force remove the not-authenticated class if it exists
      document.body.classList.remove('user-not-authenticated', 'user-signed-out');
    }
    
    // Enhanced message detection with multiple selectors
    const authMessageSelectors = [
      '[data-auth-required-message]',
      '.dashboard-signin-required',
      '.signin-required',
      '.auth-message',
      'p:contains("only available to signed-in users")',
      'div:contains("Dashboard only available to signed-in users")'
    ];
    
    // Find auth messages with different strategies
    let authMessages = [];
    authMessageSelectors.forEach(selector => {
      try {
        const elements = document.querySelectorAll(selector);
        if (elements.length > 0) {
          console.log(`Found ${elements.length} auth messages with selector: ${selector}`);
          authMessages = [...authMessages, ...elements];
        }
      } catch (e) {
        // Some selectors might not be supported
      }
    });
    
    // Try content-based detection
    if (authMessages.length === 0) {
      // Find elements with text about requiring authentication
      document.querySelectorAll('p, div, span').forEach(el => {
        if (el.textContent.toLowerCase().includes('only available to signed-in users') ||
            el.textContent.toLowerCase().includes('you need to be logged in') ||
            el.textContent.toLowerCase().includes('sign in to view')) {
          console.log("Found auth message by content:", el.textContent.trim());
          authMessages.push(el);
        }
      });
    }
    
    // Apply visibility changes to auth messages
    authMessages.forEach(msg => {
      if (isAuthenticated) {
        console.log("🔒 User is authenticated, hiding auth message:", msg);
        msg.style.display = 'none';
        // Also add a class in case style attribute is overridden
        msg.classList.add('kv-auth-hidden');
        // Add to fixed elements list
        fixed.authMessages.push(msg);
      } else {
        console.log("🔓 User is not authenticated, showing auth message");
        msg.style.display = 'block';
        msg.classList.remove('kv-auth-hidden');
      }
    });
    
    // Additional handling for dashboard elements
    if (isAuthenticated) {
      // Show any dashboard content that might be hidden
      document.querySelectorAll('.dashboard-content, .authenticated-content').forEach(el => {
        el.style.display = 'block';
        el.classList.remove('hidden');
      });
    }
  }
  
  // 3. Fix the dashboard authentication message (when already logged in)
  function fixDashboardAuthMessage() {
    console.log("🔍 Looking for dashboard auth messages");
    
    // First determine if user is likely logged in
    const likelyLoggedIn = 
      // Visual signs of being logged in
      document.querySelector('.rounded-full') !== null || // Avatar usually indicates logged in
      document.querySelector('[data-user-authenticated="true"]') !== null ||
      document.body.classList.contains('user-signed-in') ||
      document.querySelector('button:contains("Sign out")') !== null ||
      // Structural indications
      document.querySelector('.nav-link') !== null; // Navigation links usually shown to authenticated users
    
    console.log(`👤 User appears to be ${likelyLoggedIn ? 'logged in' : 'logged out'}`);
    
    // If user is likely logged in, hide auth-required messages
    if (likelyLoggedIn) {
      // Look for auth messages with various finders
      const authMessages = [
        // Direct element with dashboard message text
        ...[...document.querySelectorAll('p, div, span')].filter(el => 
          el.textContent.includes('Only visible when logged in') || 
          el.textContent.includes('Dashboard only available') ||
          el.textContent.includes('must be signed in')
        ),
        // Elements with common auth message classes
        ...document.querySelectorAll('.dashboard-signin-required, .auth-message, [data-auth-required-message]')
      ];
      
      // Hide all auth messages
      if (authMessages.length > 0) {
        console.log(`✅ Found ${authMessages.length} authentication messages to hide`);
        
        authMessages.forEach(msg => {
          console.log(`🔒 Hiding auth message: "${msg.textContent.trim().substring(0, 30)}..."`);
          
          // Hide using multiple techniques to ensure it works
          msg.style.display = 'none';
          msg.classList.add('hidden');
          msg.setAttribute('hidden', 'true');
          msg.setAttribute('aria-hidden', 'true');
          
          // Add to our fixed list
          fixed.authMessages.push(msg);
        });
      } else {
        console.log("⚠️ No authentication messages found to hide");
      }
    }
  }
  
  // Set up a MutationObserver to handle dynamic DOM changes
  function setupMutationObserver() {
    // Create an observer instance
    const observer = new MutationObserver((mutations) => {
      let needsRecheck = false;
      
      // Check if we have any relevant DOM changes
      mutations.forEach(mutation => {
        if (mutation.type === 'childList' && mutation.addedNodes.length > 0) {
          // Check if any added nodes are relevant to our fixes
          for (let i = 0; i < mutation.addedNodes.length; i++) {
            const node = mutation.addedNodes[i];
            if (node.nodeType === Node.ELEMENT_NODE) {
              // Check for dark mode elements
              if (node.matches('[data-controller="dark-mode"], [data-dark-mode-target="toggle"]') ||
                  node.querySelector('[data-controller="dark-mode"], [data-dark-mode-target="toggle"]')) {
                needsRecheck = true;
              }
              
              // Check for dropdown elements
              if (node.matches('[data-controller="dropdown"]') ||
                  node.querySelector('[data-controller="dropdown"]')) {
                needsRecheck = true;
              }
              
              // Check for auth messages
              if (node.textContent && node.textContent.toLowerCase().includes('only available to signed-in users') ||
                  (node.classList && node.classList.contains('dashboard-signin-required'))) {
                needsRecheck = true;
              }
            }
          }
        } else if (mutation.type === 'attributes' && 
                  (mutation.attributeName === 'class' || mutation.attributeName === 'data-controller')) {
          needsRecheck = true;
        }
      });
      
      // If we need to recheck, run our fixes again
      if (needsRecheck) {
        console.log("🔄 DOM changes detected, re-applying fixes");
        runFixes();
      }
    });
    
    // Observe the entire document
    observer.observe(document.documentElement, {
      childList: true,
      subtree: true,
      attributes: true,
      attributeFilter: ['class', 'style', 'data-controller']
    });
    
    console.log("👀 Mutation observer active to handle dynamic DOM changes");
  }
  
  // Log a summary of fixed elements
  function logFixSummary() {
    console.log("✅ UI Fix Summary:");
    console.log(`- Dark mode toggles fixed: ${fixed.darkModeToggles.length}`);
    console.log(`- Dropdowns fixed: ${fixed.dropdowns.length}`);
    console.log(`- Auth messages hidden: ${fixed.authMessages.length}`);
  }

  // Initialize everything
  runFixes();
  setupMutationObserver();
  logFixSummary();
  
  // Also run after DOM ready
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', runFixes);
  }
  
  // And after window load to catch any late-loading elements
  window.addEventListener('load', runFixes);
})();
