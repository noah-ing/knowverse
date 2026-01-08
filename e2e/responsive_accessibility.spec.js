// @ts-check
const { test, expect } = require('@playwright/test');
const fs = require('fs');
const path = require('path');

// Create screenshots directory for V8-006
const screenshotsDir = path.join(__dirname, '..', 'screenshots', 'v8-006');
if (!fs.existsSync(screenshotsDir)) {
  fs.mkdirSync(screenshotsDir, { recursive: true });
}

// Collect accessibility and responsive issues
let accessibilityIssues = [];

function logIssue(severity, category, description, element = null) {
  accessibilityIssues.push({ severity, category, description, element });
}

// Helper to login before tests that require authentication
async function loginAsAdmin(page) {
  await page.goto('/users/sign_in');
  await page.fill('input[type="email"], input[name="user[email]"]', 'admin@example.com');
  await page.fill('input[type="password"]', 'password');
  await page.click('button[type="submit"], input[type="submit"]');
  await page.waitForLoadState('networkidle');
  await page.waitForFunction(() => !window.location.href.includes('sign_in'), { timeout: 15000 });
}

// Viewport configurations
const viewports = {
  mobile: { width: 375, height: 667, name: 'mobile' },
  tablet: { width: 768, height: 1024, name: 'tablet' },
  desktop: { width: 1280, height: 800, name: 'desktop' }
};

test.describe('V8-006: Responsive Design Tests', () => {

  test.describe('Mobile Viewport (375px)', () => {
    test.beforeEach(async ({ page }) => {
      await page.setViewportSize(viewports.mobile);
    });

    test('homepage mobile layout', async ({ page }) => {
      await page.goto('/');
      await page.waitForLoadState('networkidle');

      await page.screenshot({
        path: path.join(screenshotsDir, '01_mobile_homepage.png'),
        fullPage: true
      });

      // Check horizontal overflow
      const hasHorizontalScroll = await page.evaluate(() => {
        return document.body.scrollWidth > window.innerWidth;
      });

      if (hasHorizontalScroll) {
        logIssue('MEDIUM', 'Responsive', 'Horizontal scroll detected on mobile homepage');
      } else {
        console.log('✓ No horizontal overflow on mobile');
      }

      // Check text readability (font size >= 14px)
      const smallText = await page.evaluate(() => {
        const elements = document.querySelectorAll('p, span, li, a, button, label');
        let tooSmall = [];
        elements.forEach(el => {
          const fontSize = parseFloat(window.getComputedStyle(el).fontSize);
          if (fontSize < 14 && el.textContent?.trim()) {
            tooSmall.push({ text: el.textContent.substring(0, 30), size: fontSize });
          }
        });
        return tooSmall.slice(0, 5); // Return first 5 examples
      });

      if (smallText.length > 0) {
        console.log('⚠ Small text found (< 14px):', smallText);
        logIssue('LOW', 'Responsive', `Small text on mobile: ${smallText.length} elements under 14px`);
      } else {
        console.log('✓ Text sizes are adequate for mobile');
      }
    });

    test('hamburger menu on mobile', async ({ page }) => {
      await page.goto('/');
      await page.waitForLoadState('networkidle');

      // Look for hamburger/mobile menu button
      const hamburgerSelectors = [
        '[data-controller*="menu"]',
        '[data-controller*="navbar"]',
        '.hamburger',
        'button[aria-label*="menu"]',
        'button[aria-label*="Menu"]',
        '[data-action*="toggle"]',
        '.mobile-menu-button',
        'button.md\\:hidden',
        'button:has(svg[class*="h-6"])'
      ];

      let hamburgerFound = false;
      let hamburgerElement = null;

      for (const selector of hamburgerSelectors) {
        const element = page.locator(selector).first();
        if (await element.count() > 0 && await element.isVisible()) {
          hamburgerFound = true;
          hamburgerElement = element;
          console.log(`✓ Hamburger menu found with selector: ${selector}`);
          break;
        }
      }

      if (hamburgerFound && hamburgerElement) {
        await page.screenshot({
          path: path.join(screenshotsDir, '02_mobile_hamburger_closed.png'),
          fullPage: false
        });

        // Try to click it
        try {
          await hamburgerElement.click();
          await page.waitForTimeout(500);

          await page.screenshot({
            path: path.join(screenshotsDir, '03_mobile_hamburger_open.png'),
            fullPage: false
          });

          // Check if menu opened
          const menuVisible = await page.evaluate(() => {
            const menus = document.querySelectorAll('[role="menu"], .mobile-menu, nav.md\\:hidden, [data-mobile-menu]');
            for (const menu of menus) {
              const display = window.getComputedStyle(menu).display;
              if (display !== 'none') return true;
            }
            return false;
          });

          console.log(`Menu opened after click: ${menuVisible}`);
        } catch (e) {
          console.log('⚠ Could not click hamburger menu:', e.message);
        }
      } else {
        // Check if navigation links are visible (might be using different responsive pattern)
        const navLinks = page.locator('header a, nav a');
        const visibleLinks = await navLinks.count();

        if (visibleLinks > 2) {
          console.log(`✓ Navigation visible on mobile (${visibleLinks} links) - may be using different pattern`);
        } else {
          logIssue('MEDIUM', 'Responsive', 'No hamburger menu found on mobile viewport');
          console.log('⚠ No hamburger menu found');
        }
      }
    });

    test('mobile touch targets (44x44px minimum)', async ({ page }) => {
      await page.goto('/');
      await page.waitForLoadState('networkidle');

      // Check interactive element sizes
      const touchTargetResults = await page.evaluate(() => {
        const interactives = document.querySelectorAll('a, button, input, select, textarea, [role="button"]');
        let tooSmall = [];
        let adequate = 0;

        interactives.forEach(el => {
          const rect = el.getBoundingClientRect();
          const minSize = 44; // WCAG recommended minimum

          if (rect.width > 0 && rect.height > 0) {
            if (rect.width < minSize || rect.height < minSize) {
              const text = el.textContent?.substring(0, 20) || el.getAttribute('aria-label') || 'unknown';
              tooSmall.push({
                text,
                width: Math.round(rect.width),
                height: Math.round(rect.height)
              });
            } else {
              adequate++;
            }
          }
        });

        return { tooSmall: tooSmall.slice(0, 10), adequate, total: interactives.length };
      });

      console.log(`Touch targets: ${touchTargetResults.adequate}/${touchTargetResults.total} adequate (44x44px+)`);

      if (touchTargetResults.tooSmall.length > 0) {
        console.log('⚠ Small touch targets found:', touchTargetResults.tooSmall);
        logIssue('MEDIUM', 'Accessibility', `${touchTargetResults.tooSmall.length} touch targets below 44x44px minimum`, JSON.stringify(touchTargetResults.tooSmall.slice(0, 3)));
      } else {
        console.log('✓ All touch targets meet minimum size requirements');
      }
    });

    test('mobile login page', async ({ page }) => {
      await page.goto('/users/sign_in');
      await page.waitForLoadState('networkidle');

      await page.screenshot({
        path: path.join(screenshotsDir, '04_mobile_login.png'),
        fullPage: true
      });

      // Check form is usable on mobile
      const formUsable = await page.evaluate(() => {
        const form = document.querySelector('form');
        if (!form) return false;

        const inputs = form.querySelectorAll('input, button, select');
        for (const input of inputs) {
          const rect = input.getBoundingClientRect();
          if (rect.width < 200) return false; // Form fields should be wide enough on mobile
        }
        return true;
      });

      if (formUsable) {
        console.log('✓ Login form is usable on mobile');
      } else {
        logIssue('MEDIUM', 'Responsive', 'Login form fields may be too narrow on mobile');
      }
    });
  });

  test.describe('Tablet Viewport (768px)', () => {
    test.beforeEach(async ({ page }) => {
      await page.setViewportSize(viewports.tablet);
    });

    test('homepage tablet layout', async ({ page }) => {
      await page.goto('/');
      await page.waitForLoadState('networkidle');

      await page.screenshot({
        path: path.join(screenshotsDir, '05_tablet_homepage.png'),
        fullPage: true
      });

      // Check for balanced layout (no excessive whitespace)
      const layoutBalance = await page.evaluate(() => {
        const main = document.querySelector('main, [role="main"], .container, .content');
        if (main) {
          const rect = main.getBoundingClientRect();
          const windowWidth = window.innerWidth;
          const sideMargin = (windowWidth - rect.width) / 2;
          return { contentWidth: rect.width, sideMargin, ratio: rect.width / windowWidth };
        }
        return null;
      });

      if (layoutBalance) {
        console.log(`Tablet layout: ${Math.round(layoutBalance.ratio * 100)}% content width`);
        if (layoutBalance.ratio < 0.5) {
          logIssue('LOW', 'Responsive', 'Tablet layout may have excessive side margins');
        }
      }
    });

    test('navigation on tablet', async ({ page }) => {
      await page.goto('/');
      await page.waitForLoadState('networkidle');

      // Check if full nav is visible or hamburger
      const navLinks = await page.locator('header a:visible, nav a:visible').count();
      console.log(`Tablet nav links visible: ${navLinks}`);

      await page.screenshot({
        path: path.join(screenshotsDir, '06_tablet_navigation.png'),
        fullPage: false
      });
    });
  });

  test.describe('Desktop Viewport (1280px)', () => {
    test.beforeEach(async ({ page }) => {
      await page.setViewportSize(viewports.desktop);
    });

    test('homepage desktop layout', async ({ page }) => {
      await page.goto('/');
      await page.waitForLoadState('networkidle');

      await page.screenshot({
        path: path.join(screenshotsDir, '07_desktop_homepage.png'),
        fullPage: true
      });

      // Check max-width constraint (content shouldn't span full width)
      const hasMaxWidth = await page.evaluate(() => {
        const containers = document.querySelectorAll('.container, .max-w-7xl, .max-w-6xl, .max-w-5xl, [class*="max-w"]');
        return containers.length > 0;
      });

      if (hasMaxWidth) {
        console.log('✓ Desktop has max-width constraints for readability');
      } else {
        logIssue('LOW', 'Responsive', 'Desktop layout may lack max-width constraints');
      }
    });

    test('desktop navigation fully visible', async ({ page }) => {
      await page.goto('/');
      await page.waitForLoadState('networkidle');

      const navLinks = await page.locator('header a:visible, nav a:visible').count();
      console.log(`Desktop nav links visible: ${navLinks}`);

      // Desktop should show full navigation (more links than mobile)
      if (navLinks >= 3) {
        console.log('✓ Full navigation visible on desktop');
      }

      await page.screenshot({
        path: path.join(screenshotsDir, '08_desktop_navigation.png'),
        fullPage: false
      });
    });
  });
});

test.describe('V8-006: Accessibility Tests', () => {

  test('color contrast check', async ({ page }) => {
    await page.setViewportSize(viewports.desktop);
    await page.goto('/');
    await page.waitForLoadState('networkidle');

    // Extract color information
    const colorData = await page.evaluate(() => {
      const results = {
        textColors: [],
        backgroundColors: [],
        lowContrastPairs: []
      };

      // Helper to calculate relative luminance
      function getLuminance(r, g, b) {
        const a = [r, g, b].map(v => {
          v = v / 255;
          return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
        });
        return a[0] * 0.2126 + a[1] * 0.7152 + a[2] * 0.0722;
      }

      // Helper to calculate contrast ratio
      function getContrastRatio(l1, l2) {
        const lighter = Math.max(l1, l2);
        const darker = Math.min(l1, l2);
        return (lighter + 0.05) / (darker + 0.05);
      }

      // Helper to parse RGB values
      function parseRGB(color) {
        const match = color.match(/rgb[a]?\((\d+),\s*(\d+),\s*(\d+)/);
        if (match) {
          return { r: parseInt(match[1]), g: parseInt(match[2]), b: parseInt(match[3]) };
        }
        return null;
      }

      // Check text elements
      const textElements = document.querySelectorAll('p, span, a, button, h1, h2, h3, h4, h5, h6, label, li');

      textElements.forEach(el => {
        const style = window.getComputedStyle(el);
        const textColor = style.color;
        const bgColor = style.backgroundColor;

        const text = parseRGB(textColor);
        const bg = parseRGB(bgColor);

        if (text && bg && bgColor !== 'rgba(0, 0, 0, 0)') {
          const textLum = getLuminance(text.r, text.g, text.b);
          const bgLum = getLuminance(bg.r, bg.g, bg.b);
          const ratio = getContrastRatio(textLum, bgLum);

          // WCAG AA requires 4.5:1 for normal text, 3:1 for large text
          if (ratio < 4.5) {
            const sampleText = el.textContent?.substring(0, 30) || '';
            results.lowContrastPairs.push({
              text: sampleText,
              textColor,
              bgColor,
              ratio: ratio.toFixed(2)
            });
          }
        }
      });

      return results;
    });

    if (colorData.lowContrastPairs.length > 0) {
      console.log('⚠ Low contrast text found:', colorData.lowContrastPairs.slice(0, 5));
      logIssue('MEDIUM', 'Accessibility', `${colorData.lowContrastPairs.length} elements may have insufficient color contrast`, JSON.stringify(colorData.lowContrastPairs.slice(0, 3)));
    } else {
      console.log('✓ Color contrast appears adequate');
    }

    await page.screenshot({
      path: path.join(screenshotsDir, '09_color_contrast_test.png'),
      fullPage: true
    });
  });

  test('keyboard navigation - tab order', async ({ page }) => {
    await page.setViewportSize(viewports.desktop);
    await page.goto('/');
    await page.waitForLoadState('networkidle');

    // Test tab navigation
    const tabOrder = [];

    for (let i = 0; i < 10; i++) {
      await page.keyboard.press('Tab');

      const focusedElement = await page.evaluate(() => {
        const el = document.activeElement;
        if (el) {
          return {
            tagName: el.tagName,
            text: el.textContent?.substring(0, 30) || '',
            href: el.getAttribute('href'),
            hasVisibleFocus: window.getComputedStyle(el).outlineStyle !== 'none' ||
                            window.getComputedStyle(el).boxShadow !== 'none'
          };
        }
        return null;
      });

      if (focusedElement) {
        tabOrder.push(focusedElement);
      }
    }

    console.log('Tab order (first 10 elements):');
    tabOrder.forEach((el, i) => {
      console.log(`  ${i + 1}. ${el.tagName} - "${el.text.trim()}" ${el.href ? `(${el.href})` : ''}`);
    });

    // Check for visible focus indicators
    const focusIssues = tabOrder.filter(el => !el.hasVisibleFocus);
    if (focusIssues.length > 0) {
      logIssue('MEDIUM', 'Accessibility', `${focusIssues.length} elements may lack visible focus indicator`);
      console.log('⚠ Some elements may lack visible focus indicators');
    } else {
      console.log('✓ Focus indicators appear present');
    }

    await page.screenshot({
      path: path.join(screenshotsDir, '10_keyboard_focus.png'),
      fullPage: false
    });
  });

  test('heading hierarchy', async ({ page }) => {
    await page.setViewportSize(viewports.desktop);
    await page.goto('/');
    await page.waitForLoadState('networkidle');

    const headings = await page.evaluate(() => {
      const results = [];
      const headingElements = document.querySelectorAll('h1, h2, h3, h4, h5, h6');

      headingElements.forEach(h => {
        results.push({
          level: parseInt(h.tagName.charAt(1)),
          text: h.textContent?.substring(0, 50) || ''
        });
      });

      return results;
    });

    console.log('Heading hierarchy:');
    headings.forEach(h => {
      console.log(`  H${h.level}: "${h.text}"`);
    });

    // Check for skipped levels
    let previousLevel = 0;
    let skippedLevels = false;

    headings.forEach(h => {
      if (previousLevel > 0 && h.level > previousLevel + 1) {
        skippedLevels = true;
        console.log(`⚠ Skipped heading level: H${previousLevel} -> H${h.level}`);
      }
      previousLevel = h.level;
    });

    if (skippedLevels) {
      logIssue('LOW', 'Accessibility', 'Heading levels are skipped (e.g., H1 -> H3)');
    } else {
      console.log('✓ Heading hierarchy is logical');
    }

    // Check for multiple H1s
    const h1Count = headings.filter(h => h.level === 1).length;
    if (h1Count > 1) {
      logIssue('LOW', 'Accessibility', `Multiple H1 elements found: ${h1Count}`);
      console.log(`⚠ Multiple H1 elements: ${h1Count}`);
    } else if (h1Count === 0) {
      logIssue('MEDIUM', 'Accessibility', 'No H1 element found on page');
      console.log('⚠ No H1 element found');
    }
  });

  test('ARIA labels and roles', async ({ page }) => {
    await page.setViewportSize(viewports.desktop);
    await page.goto('/');
    await page.waitForLoadState('networkidle');

    const ariaResults = await page.evaluate(() => {
      const results = {
        withLabels: 0,
        withoutLabels: [],
        roles: []
      };

      // Check interactive elements for labels
      const interactives = document.querySelectorAll('button, a, input, select, textarea');

      interactives.forEach(el => {
        const hasLabel = el.getAttribute('aria-label') ||
                        el.getAttribute('aria-labelledby') ||
                        el.textContent?.trim() ||
                        el.getAttribute('title') ||
                        el.getAttribute('placeholder');

        if (hasLabel) {
          results.withLabels++;
        } else {
          results.withoutLabels.push({
            tag: el.tagName,
            type: el.getAttribute('type') || '',
            id: el.id || ''
          });
        }
      });

      // Check for landmark roles
      const landmarks = document.querySelectorAll('[role], header, nav, main, footer, aside');
      landmarks.forEach(el => {
        const role = el.getAttribute('role') || el.tagName.toLowerCase();
        results.roles.push(role);
      });

      return results;
    });

    console.log(`ARIA: ${ariaResults.withLabels} labeled elements`);
    console.log(`Landmarks found: ${[...new Set(ariaResults.roles)].join(', ')}`);

    if (ariaResults.withoutLabels.length > 0) {
      console.log('⚠ Elements without accessible labels:', ariaResults.withoutLabels.slice(0, 5));
      logIssue('LOW', 'Accessibility', `${ariaResults.withoutLabels.length} interactive elements may lack accessible labels`);
    }

    await page.screenshot({
      path: path.join(screenshotsDir, '11_aria_check.png'),
      fullPage: false
    });
  });

  test('form accessibility', async ({ page }) => {
    await page.setViewportSize(viewports.desktop);
    await page.goto('/users/sign_in');
    await page.waitForLoadState('networkidle');

    const formAccessibility = await page.evaluate(() => {
      const results = {
        labelsCorrect: [],
        labelsMissing: [],
        errorHandling: false
      };

      const inputs = document.querySelectorAll('input, select, textarea');

      inputs.forEach(input => {
        const id = input.id;
        const name = input.getAttribute('name');
        const type = input.getAttribute('type');
        const ariaLabel = input.getAttribute('aria-label');
        const label = id ? document.querySelector(`label[for="${id}"]`) : null;

        if (type === 'hidden' || type === 'submit') return;

        if (label || ariaLabel) {
          results.labelsCorrect.push({ name, hasLabel: true });
        } else {
          results.labelsMissing.push({ name, type, id });
        }
      });

      // Check for error message regions
      const errorRegions = document.querySelectorAll('[role="alert"], .error, .alert, [aria-live]');
      results.errorHandling = errorRegions.length > 0;

      return results;
    });

    console.log(`Form inputs with proper labels: ${formAccessibility.labelsCorrect.length}`);

    if (formAccessibility.labelsMissing.length > 0) {
      console.log('⚠ Inputs missing labels:', formAccessibility.labelsMissing);
      logIssue('MEDIUM', 'Accessibility', `${formAccessibility.labelsMissing.length} form inputs may lack proper labels`);
    } else {
      console.log('✓ All form inputs have proper labels');
    }

    await page.screenshot({
      path: path.join(screenshotsDir, '12_form_accessibility.png'),
      fullPage: true
    });
  });

  test('skip to main content link', async ({ page }) => {
    await page.setViewportSize(viewports.desktop);
    await page.goto('/');
    await page.waitForLoadState('networkidle');

    // Check for skip link
    const skipLink = await page.evaluate(() => {
      const links = document.querySelectorAll('a');
      for (const link of links) {
        const text = link.textContent?.toLowerCase() || '';
        const href = link.getAttribute('href') || '';
        if ((text.includes('skip') && text.includes('main')) || href === '#main') {
          return {
            text: link.textContent,
            href,
            visible: window.getComputedStyle(link).position !== 'absolute' ||
                    window.getComputedStyle(link).clip !== 'rect(0px, 0px, 0px, 0px)'
          };
        }
      }
      return null;
    });

    if (skipLink) {
      console.log(`✓ Skip link found: "${skipLink.text}" -> ${skipLink.href}`);
    } else {
      console.log('⚠ No "skip to main content" link found');
      logIssue('LOW', 'Accessibility', 'No skip to main content link found');
    }
  });

  test('images have alt text', async ({ page }) => {
    await page.setViewportSize(viewports.desktop);
    await page.goto('/');
    await page.waitForLoadState('networkidle');

    const imageResults = await page.evaluate(() => {
      const images = document.querySelectorAll('img');
      const results = { withAlt: 0, withoutAlt: [], decorative: 0 };

      images.forEach(img => {
        const alt = img.getAttribute('alt');
        const src = img.getAttribute('src');

        if (alt === '') {
          // Empty alt is valid for decorative images
          results.decorative++;
        } else if (alt) {
          results.withAlt++;
        } else {
          results.withoutAlt.push({ src: src?.substring(0, 50) });
        }
      });

      return results;
    });

    console.log(`Images: ${imageResults.withAlt} with alt, ${imageResults.decorative} decorative, ${imageResults.withoutAlt.length} missing alt`);

    if (imageResults.withoutAlt.length > 0) {
      console.log('⚠ Images missing alt text:', imageResults.withoutAlt);
      logIssue('MEDIUM', 'Accessibility', `${imageResults.withoutAlt.length} images missing alt text`);
    } else {
      console.log('✓ All images have alt text');
    }
  });
});

test.describe('V8-006: Authenticated Page Responsiveness', () => {
  test.beforeEach(async ({ page }) => {
    await loginAsAdmin(page);
  });

  test('dashboard responsive - mobile', async ({ page }) => {
    await page.setViewportSize(viewports.mobile);
    await page.goto('/dashboard');
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(1000);

    await page.screenshot({
      path: path.join(screenshotsDir, '13_mobile_dashboard.png'),
      fullPage: true
    });

    // Check if cards stack properly
    const cardLayout = await page.evaluate(() => {
      const cards = document.querySelectorAll('[class*="card"], .card, [class*="rounded"]');
      let stacked = true;
      let prevTop = -1;

      cards.forEach(card => {
        const rect = card.getBoundingClientRect();
        if (rect.top < prevTop && rect.width > 100) {
          stacked = false;
        }
        prevTop = rect.top;
      });

      return { cardCount: cards.length, stacked };
    });

    console.log(`Dashboard cards: ${cardLayout.cardCount}, stacked: ${cardLayout.stacked}`);
  });

  test('documents page responsive - mobile', async ({ page }) => {
    await page.setViewportSize(viewports.mobile);
    await page.goto('/documents');
    await page.waitForLoadState('networkidle');

    await page.screenshot({
      path: path.join(screenshotsDir, '14_mobile_documents.png'),
      fullPage: true
    });
  });

  test('RAG chat responsive - mobile', async ({ page }) => {
    await page.setViewportSize(viewports.mobile);

    // Navigate directly to organizations page
    await page.goto('/organizations');
    await page.waitForLoadState('networkidle');

    // Take screenshot of organizations page on mobile
    await page.screenshot({
      path: path.join(screenshotsDir, '15_mobile_organizations.png'),
      fullPage: true
    });

    // Try to find and click RAG link - but use visible check first
    const ragLink = page.locator('a:has-text("RAG"):visible');
    const ragCount = await ragLink.count();

    if (ragCount > 0) {
      await ragLink.first().click();
      await page.waitForLoadState('networkidle');

      await page.screenshot({
        path: path.join(screenshotsDir, '16_mobile_rag.png'),
        fullPage: true
      });

      // Check input area accessibility
      const inputAccessible = await page.evaluate(() => {
        const input = document.querySelector('textarea, input[type="text"]');
        if (input) {
          const rect = input.getBoundingClientRect();
          return rect.width >= 250 && rect.height >= 40;
        }
        return false;
      });

      if (inputAccessible) {
        console.log('✓ RAG input is accessible on mobile');
      } else {
        logIssue('LOW', 'Responsive', 'RAG input may be too small on mobile');
      }
    } else {
      // RAG link not visible on mobile - this is expected behavior for hamburger menu
      console.log('RAG link not directly visible on mobile - may be in hamburger menu');

      // Check if there's a hamburger menu to open
      const hamburger = page.locator('[data-controller*="menu"] button:visible, button[aria-label*="menu"]:visible').first();
      if (await hamburger.count() > 0) {
        await hamburger.click();
        await page.waitForTimeout(500);

        await page.screenshot({
          path: path.join(screenshotsDir, '15b_mobile_menu_open.png'),
          fullPage: false
        });

        // Now check for RAG link in opened menu
        const ragInMenu = page.locator('a:has-text("RAG"):visible');
        if (await ragInMenu.count() > 0) {
          console.log('✓ RAG link found in hamburger menu');
        }
      }
    }
  });
});

// Summary after all tests
test.afterAll(async () => {
  console.log('\n=== V8-006 ACCESSIBILITY & RESPONSIVE AUDIT SUMMARY ===\n');

  if (accessibilityIssues.length === 0) {
    console.log('No accessibility or responsive issues detected!');
  } else {
    // Group by severity
    const critical = accessibilityIssues.filter(i => i.severity === 'CRITICAL');
    const high = accessibilityIssues.filter(i => i.severity === 'HIGH');
    const medium = accessibilityIssues.filter(i => i.severity === 'MEDIUM');
    const low = accessibilityIssues.filter(i => i.severity === 'LOW');

    if (critical.length > 0) {
      console.log('CRITICAL:');
      critical.forEach(i => console.log(`  - [${i.category}] ${i.description}`));
    }
    if (high.length > 0) {
      console.log('HIGH:');
      high.forEach(i => console.log(`  - [${i.category}] ${i.description}`));
    }
    if (medium.length > 0) {
      console.log('MEDIUM:');
      medium.forEach(i => console.log(`  - [${i.category}] ${i.description}`));
    }
    if (low.length > 0) {
      console.log('LOW:');
      low.forEach(i => console.log(`  - [${i.category}] ${i.description}`));
    }
  }

  // Write issues to JSON file
  const issuesPath = path.join(screenshotsDir, 'accessibility_issues.json');
  fs.writeFileSync(issuesPath, JSON.stringify(accessibilityIssues, null, 2));
  console.log(`\nIssues saved to: ${issuesPath}`);
  console.log(`Screenshots saved to: ${screenshotsDir}`);
});
