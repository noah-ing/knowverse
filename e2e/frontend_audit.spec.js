// @ts-check
const { test, expect } = require('@playwright/test');
const fs = require('fs');
const path = require('path');

// Create screenshots directory
const screenshotsDir = path.join(__dirname, '..', 'frontend_audit_screenshots');
if (!fs.existsSync(screenshotsDir)) {
  fs.mkdirSync(screenshotsDir, { recursive: true });
}

// Collect issues during tests
let auditIssues = [];

function logIssue(severity, category, description, screenshot = null) {
  auditIssues.push({ severity, category, description, screenshot });
}

test.describe('V8-001: Homepage and Navigation Audit', () => {
  test('homepage loads and capture screenshot', async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');

    // Take screenshot
    await page.screenshot({
      path: path.join(screenshotsDir, '01_homepage.png'),
      fullPage: true
    });

    // Check for main elements
    const title = await page.title();
    console.log(`Page title: ${title}`);

    // Check hero section
    const heroHeading = page.locator('h1');
    if (await heroHeading.count() > 0) {
      console.log('✓ Hero heading found');
    } else {
      logIssue('MEDIUM', 'UX', 'Missing h1 heading on homepage');
    }

    // Check navigation exists
    const nav = page.locator('nav, header');
    expect(await nav.count()).toBeGreaterThan(0);
    console.log('✓ Navigation element found');
  });

  test('check all navigation links', async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');

    // Find all links in header/nav
    const navLinks = page.locator('header a, nav a');
    const linkCount = await navLinks.count();
    console.log(`Found ${linkCount} navigation links`);

    // Collect link info
    const links = [];
    for (let i = 0; i < linkCount; i++) {
      const link = navLinks.nth(i);
      const href = await link.getAttribute('href');
      const text = await link.innerText();
      if (href) {
        links.push({ text: text.trim(), href });
      }
    }

    // Log discovered links
    console.log('Navigation links discovered:');
    links.forEach(l => console.log(`  - "${l.text}" -> ${l.href}`));

    // Check for essential links
    const essentialPaths = ['/', '/search', '/users/sign_in', '/users/sign_up'];
    const foundPaths = links.map(l => l.href);

    essentialPaths.forEach(path => {
      if (!foundPaths.some(f => f === path || f.endsWith(path))) {
        console.log(`⚠ Missing link to: ${path}`);
      }
    });
  });

  test('check for broken images', async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');

    // Find all images
    const images = page.locator('img');
    const imgCount = await images.count();
    console.log(`Found ${imgCount} images on homepage`);

    let brokenImages = 0;
    for (let i = 0; i < imgCount; i++) {
      const img = images.nth(i);
      const src = await img.getAttribute('src');
      const alt = await img.getAttribute('alt');
      const naturalWidth = await img.evaluate(el => el.naturalWidth);

      if (naturalWidth === 0) {
        console.log(`⚠ Broken image: ${src}`);
        brokenImages++;
        logIssue('MEDIUM', 'Assets', `Broken image: ${src}`);
      }

      if (!alt) {
        console.log(`⚠ Image missing alt text: ${src}`);
        logIssue('LOW', 'Accessibility', `Image missing alt text: ${src}`);
      }
    }

    console.log(`${imgCount - brokenImages}/${imgCount} images loaded correctly`);
  });

  test('check CSS loading', async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');

    // Check for visible styling (body should have styles applied)
    const bodyStyles = await page.evaluate(() => {
      const body = document.body;
      const computed = window.getComputedStyle(body);
      return {
        fontFamily: computed.fontFamily,
        backgroundColor: computed.backgroundColor,
        fontSize: computed.fontSize
      };
    });

    console.log('Body styles:', bodyStyles);

    // Check for potential unstyled content
    if (bodyStyles.fontFamily === 'serif' || bodyStyles.fontFamily === 'Times') {
      logIssue('HIGH', 'CSS', 'CSS may not be loading - serif font detected');
    } else {
      console.log('✓ CSS appears to be loading correctly');
    }
  });

  test('check footer and secondary navigation', async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');

    // Screenshot footer area
    await page.screenshot({
      path: path.join(screenshotsDir, '02_footer.png'),
      fullPage: true
    });

    // Check for footer
    const footer = page.locator('footer');
    if (await footer.count() > 0) {
      console.log('✓ Footer element found');

      // Check footer links
      const footerLinks = footer.locator('a');
      const linkCount = await footerLinks.count();
      console.log(`Footer has ${linkCount} links`);
    } else {
      logIssue('LOW', 'UX', 'No footer element found');
    }
  });
});

test.describe('V8-002: Authentication Flow', () => {
  test('login page UI', async ({ page }) => {
    await page.goto('/users/sign_in');
    await page.waitForLoadState('networkidle');

    await page.screenshot({
      path: path.join(screenshotsDir, '03_login_page.png'),
      fullPage: true
    });

    // Check for essential form elements
    const emailInput = page.locator('input[type="email"], input[name="user[email]"]');
    const passwordInput = page.locator('input[type="password"]');
    const submitButton = page.locator('button[type="submit"], input[type="submit"]');

    expect(await emailInput.count()).toBeGreaterThan(0);
    expect(await passwordInput.count()).toBeGreaterThan(0);
    expect(await submitButton.count()).toBeGreaterThan(0);

    console.log('✓ Login form has all required fields');

    // Check for "forgot password" link
    const forgotPassword = page.locator('a:has-text("forgot"), a:has-text("Forgot")');
    if (await forgotPassword.count() > 0) {
      console.log('✓ Forgot password link present');
    } else {
      logIssue('LOW', 'UX', 'Missing forgot password link on login page');
    }

    // Check for sign up link
    const signUpLink = page.locator('a:has-text("Sign up"), a:has-text("sign up"), a:has-text("Register")');
    if (await signUpLink.count() > 0) {
      console.log('✓ Sign up link present');
    }
  });

  test('registration page UI', async ({ page }) => {
    await page.goto('/users/sign_up');
    await page.waitForLoadState('networkidle');

    await page.screenshot({
      path: path.join(screenshotsDir, '04_registration_page.png'),
      fullPage: true
    });

    // Check form structure
    const form = page.locator('form');
    if (await form.count() > 0) {
      console.log('✓ Registration form found');
    }
  });

  test('login with invalid credentials shows error', async ({ page }) => {
    await page.goto('/users/sign_in');
    await page.waitForLoadState('networkidle');

    // Fill with invalid credentials
    await page.fill('input[type="email"], input[name="user[email]"]', 'invalid@test.com');
    await page.fill('input[type="password"]', 'wrongpassword');

    // Submit
    await page.click('button[type="submit"], input[type="submit"]');
    await page.waitForLoadState('networkidle');

    await page.screenshot({
      path: path.join(screenshotsDir, '05_login_error.png'),
      fullPage: true
    });

    // Check for error message
    const errorMessage = page.locator('.alert-danger, .error, [role="alert"]');
    if (await errorMessage.count() > 0) {
      console.log('✓ Error message displayed for invalid login');
    } else {
      logIssue('MEDIUM', 'UX', 'No visible error message for invalid login');
    }
  });

  test('login with valid credentials', async ({ page }) => {
    await page.goto('/users/sign_in');
    await page.waitForLoadState('networkidle');

    // Use test credentials
    await page.fill('input[type="email"], input[name="user[email]"]', 'admin@example.com');
    await page.fill('input[type="password"]', 'password');

    await page.click('button[type="submit"], input[type="submit"]');

    // Wait for redirect
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(2000);

    await page.screenshot({
      path: path.join(screenshotsDir, '06_after_login.png'),
      fullPage: true
    });

    // Should not be on sign_in page
    const url = page.url();
    console.log(`After login URL: ${url}`);

    if (!url.includes('sign_in')) {
      console.log('✓ Login successful - redirected away from sign_in');
    }
  });
});

test.describe('V8-003: Dashboard and Main Interface', () => {
  test.beforeEach(async ({ page }) => {
    // Login first
    await page.goto('/users/sign_in');
    await page.fill('input[type="email"], input[name="user[email]"]', 'admin@example.com');
    await page.fill('input[type="password"]', 'password');
    await page.click('button[type="submit"], input[type="submit"]');
    await page.waitForLoadState('networkidle');
    await page.waitForFunction(() => !window.location.href.includes('sign_in'), { timeout: 15000 });
  });

  test('dashboard loads and screenshot', async ({ page }) => {
    await page.goto('/dashboard');
    await page.waitForLoadState('networkidle');

    await page.screenshot({
      path: path.join(screenshotsDir, '07_dashboard.png'),
      fullPage: true
    });

    console.log(`Dashboard URL: ${page.url()}`);
  });

  test('documents page', async ({ page }) => {
    await page.goto('/documents');
    await page.waitForLoadState('networkidle');

    await page.screenshot({
      path: path.join(screenshotsDir, '08_documents.png'),
      fullPage: true
    });

    // Check for document list or upload area
    const uploadArea = page.locator('[data-controller*="upload"], .upload, .dropzone, input[type="file"]');
    if (await uploadArea.count() > 0) {
      console.log('✓ Upload area found');
    }

    console.log(`Documents page URL: ${page.url()}`);
  });

  test('conversations page', async ({ page }) => {
    await page.goto('/conversations');
    await page.waitForLoadState('networkidle');

    await page.screenshot({
      path: path.join(screenshotsDir, '09_conversations.png'),
      fullPage: true
    });

    console.log(`Conversations page URL: ${page.url()}`);
  });
});

test.describe('V8-004: Responsive Design', () => {
  test('mobile viewport (375px)', async ({ page }) => {
    await page.setViewportSize({ width: 375, height: 667 });
    await page.goto('/');
    await page.waitForLoadState('networkidle');

    await page.screenshot({
      path: path.join(screenshotsDir, '10_mobile_homepage.png'),
      fullPage: true
    });

    // Check for hamburger menu
    const hamburger = page.locator('[data-controller*="menu"], .hamburger, button[aria-label*="menu"], [data-action*="toggle"]');
    if (await hamburger.count() > 0) {
      console.log('✓ Mobile menu button found');
    } else {
      logIssue('MEDIUM', 'Responsive', 'No hamburger menu found on mobile');
    }

    console.log('Mobile viewport test completed');
  });

  test('tablet viewport (768px)', async ({ page }) => {
    await page.setViewportSize({ width: 768, height: 1024 });
    await page.goto('/');
    await page.waitForLoadState('networkidle');

    await page.screenshot({
      path: path.join(screenshotsDir, '11_tablet_homepage.png'),
      fullPage: true
    });

    console.log('Tablet viewport test completed');
  });

  test('desktop viewport (1280px)', async ({ page }) => {
    await page.setViewportSize({ width: 1280, height: 800 });
    await page.goto('/');
    await page.waitForLoadState('networkidle');

    await page.screenshot({
      path: path.join(screenshotsDir, '12_desktop_homepage.png'),
      fullPage: true
    });

    console.log('Desktop viewport test completed');
  });
});

test.describe('V8-005: Error States', () => {
  test('404 page', async ({ page }) => {
    await page.goto('/nonexistent-page-12345');
    await page.waitForLoadState('networkidle');

    await page.screenshot({
      path: path.join(screenshotsDir, '13_404_page.png'),
      fullPage: true
    });

    // Check for 404 message
    const page404 = page.locator('text=404, text=not found, text=Not Found');
    if (await page404.count() > 0) {
      console.log('✓ 404 page displays correctly');
    }
  });
});

// After all tests, write issues summary
test.afterAll(async () => {
  console.log('\n=== AUDIT ISSUES SUMMARY ===');
  if (auditIssues.length === 0) {
    console.log('No issues detected!');
  } else {
    auditIssues.forEach(issue => {
      console.log(`[${issue.severity}] ${issue.category}: ${issue.description}`);
    });
  }

  // Write issues to file
  const issuesPath = path.join(screenshotsDir, 'audit_issues.json');
  fs.writeFileSync(issuesPath, JSON.stringify(auditIssues, null, 2));
  console.log(`\nIssues saved to: ${issuesPath}`);
});
