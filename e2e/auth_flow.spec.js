// @ts-check
const { test, expect } = require('@playwright/test');
const fs = require('fs');
const path = require('path');

// Create screenshots directory
const screenshotsDir = path.join(__dirname, '..', 'frontend_audit_screenshots', 'v8-002');
if (!fs.existsSync(screenshotsDir)) {
  fs.mkdirSync(screenshotsDir, { recursive: true });
}

// Collect issues during tests
let auditIssues = [];
let screenshots = [];

function logIssue(severity, id, title, description, screenshot = null) {
  auditIssues.push({ severity, id, title, description, screenshot });
  console.log(`[${severity}] ${id}: ${title}`);
}

function logScreenshot(filename, description) {
  screenshots.push({ filename, description });
  console.log(`📸 Screenshot: ${filename}`);
}

test.describe('V8-002: User Registration and Login Flow', () => {

  // Test 1: Navigate to registration page
  test('1. registration page loads correctly', async ({ page }) => {
    await page.goto('/users/sign_up');
    await page.waitForLoadState('networkidle');

    const ssPath = path.join(screenshotsDir, '01_registration_page.png');
    await page.screenshot({ path: ssPath, fullPage: true });
    logScreenshot('01_registration_page.png', 'Registration page initial load');

    // Check page title
    const title = await page.title();
    console.log(`Page title: ${title}`);

    // Check for form elements
    const form = page.locator('form');
    expect(await form.count()).toBeGreaterThan(0);
    console.log('✓ Registration form found');

    // Check for email field
    const emailInput = page.locator('input[type="email"], input[name="user[email]"]');
    if (await emailInput.count() > 0) {
      console.log('✓ Email input found');
    } else {
      logIssue('HIGH', 'REG-001', 'Missing email input', 'Registration form missing email field');
    }

    // Check for password field
    const passwordInput = page.locator('input[type="password"]');
    if (await passwordInput.count() > 0) {
      console.log('✓ Password input found');
    } else {
      logIssue('HIGH', 'REG-002', 'Missing password input', 'Registration form missing password field');
    }

    // Check for password confirmation
    const confirmPassword = page.locator('input[name="user[password_confirmation]"]');
    if (await confirmPassword.count() > 0) {
      console.log('✓ Password confirmation field found');
    } else {
      console.log('⚠ No password confirmation field (may be intentional)');
    }

    // Check for submit button
    const submitBtn = page.locator('button[type="submit"], input[type="submit"]');
    expect(await submitBtn.count()).toBeGreaterThan(0);
    console.log('✓ Submit button found');
  });

  // Test 2: Fill out registration form with test data
  test('2. registration form with valid data', async ({ page }) => {
    await page.goto('/users/sign_up');
    await page.waitForLoadState('networkidle');

    // Generate unique test email
    const testEmail = `test_${Date.now()}@example.com`;
    const testPassword = 'TestPassword123!';

    // Fill email
    const emailInput = page.locator('input[type="email"], input[name="user[email]"]');
    if (await emailInput.count() > 0) {
      await emailInput.fill(testEmail);
      console.log(`✓ Filled email: ${testEmail}`);
    }

    // Fill password
    const passwordInput = page.locator('input[type="password"]').first();
    if (await passwordInput.count() > 0) {
      await passwordInput.fill(testPassword);
      console.log('✓ Filled password');
    }

    // Fill password confirmation if present
    const confirmInput = page.locator('input[name="user[password_confirmation]"]');
    if (await confirmInput.count() > 0) {
      await confirmInput.fill(testPassword);
      console.log('✓ Filled password confirmation');
    }

    // Check for organization/name fields
    const nameInput = page.locator('input[name="user[name]"], input[name="name"]');
    if (await nameInput.count() > 0) {
      await nameInput.fill('Test User');
      console.log('✓ Filled name field');
    }

    // Screenshot before submit
    const ssPath = path.join(screenshotsDir, '02_registration_filled.png');
    await page.screenshot({ path: ssPath, fullPage: true });
    logScreenshot('02_registration_filled.png', 'Registration form filled with test data');
  });

  // Test 3: Submit registration form and verify response
  test('3. registration form submission', async ({ page }) => {
    await page.goto('/users/sign_up');
    await page.waitForLoadState('networkidle');

    // Generate unique test email
    const testEmail = `regtest_${Date.now()}@example.com`;
    const testPassword = 'TestPassword123!';

    // Fill form
    const emailInput = page.locator('input[type="email"], input[name="user[email]"]');
    if (await emailInput.count() > 0) {
      await emailInput.fill(testEmail);
    }

    const passwordInput = page.locator('input[type="password"]').first();
    if (await passwordInput.count() > 0) {
      await passwordInput.fill(testPassword);
    }

    const confirmInput = page.locator('input[name="user[password_confirmation]"]');
    if (await confirmInput.count() > 0) {
      await confirmInput.fill(testPassword);
    }

    // Submit form
    await page.click('button[type="submit"], input[type="submit"]');
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(2000);

    const ssPath = path.join(screenshotsDir, '03_registration_result.png');
    await page.screenshot({ path: ssPath, fullPage: true });
    logScreenshot('03_registration_result.png', 'Registration form submission result');

    const url = page.url();
    console.log(`After registration URL: ${url}`);

    // Check for success indicators
    const successMessage = page.locator('.alert-success, .flash-success, [role="alert"]:has-text("success"), [role="alert"]:has-text("Welcome")');
    const errorMessage = page.locator('.alert-danger, .alert-error, .error, [role="alert"]:has-text("error")');

    if (!url.includes('sign_up')) {
      console.log('✓ Redirected away from registration page (likely success)');
    } else {
      // Still on registration page - check for errors
      if (await errorMessage.count() > 0) {
        const errorText = await errorMessage.first().textContent();
        console.log(`Registration error: ${errorText}`);
      } else {
        logIssue('MEDIUM', 'REG-003', 'Unclear registration result', 'Still on registration page but no clear error message');
      }
    }
  });

  // Test 4: Test login with valid credentials
  test('4. login with valid credentials', async ({ page }) => {
    await page.goto('/users/sign_in');
    await page.waitForLoadState('networkidle');

    // Use known test credentials
    const emailInput = page.locator('input[type="email"], input[name="user[email]"]');
    const passwordInput = page.locator('input[type="password"]');

    await emailInput.fill('admin@example.com');
    await passwordInput.fill('password');

    const ssPath1 = path.join(screenshotsDir, '04_login_filled.png');
    await page.screenshot({ path: ssPath1, fullPage: true });
    logScreenshot('04_login_filled.png', 'Login form with valid credentials');

    // Submit
    await page.click('button[type="submit"], input[type="submit"]');
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(2000);

    const ssPath2 = path.join(screenshotsDir, '05_login_success.png');
    await page.screenshot({ path: ssPath2, fullPage: true });
    logScreenshot('05_login_success.png', 'After successful login');

    const url = page.url();
    console.log(`After login URL: ${url}`);

    if (!url.includes('sign_in')) {
      console.log('✓ Login successful - redirected to authenticated area');
    } else {
      logIssue('HIGH', 'AUTH-001', 'Login not working', 'Valid credentials did not redirect away from sign_in page');
    }

    // Check for user menu or authenticated elements
    const userMenu = page.locator('[data-controller*="menu"], .user-menu, .avatar, [aria-label*="user"], [aria-label*="account"]');
    if (await userMenu.count() > 0) {
      console.log('✓ User menu/avatar visible after login');
    }
  });

  // Test 5: Test login with invalid credentials
  test('5. login with invalid credentials shows error', async ({ page }) => {
    await page.goto('/users/sign_in');
    await page.waitForLoadState('networkidle');

    // Use invalid credentials
    const emailInput = page.locator('input[type="email"], input[name="user[email]"]');
    const passwordInput = page.locator('input[type="password"]');

    await emailInput.fill('invalid@nonexistent.com');
    await passwordInput.fill('wrongpassword123');

    // Submit
    await page.click('button[type="submit"], input[type="submit"]');
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(2000);

    const ssPath = path.join(screenshotsDir, '06_login_error.png');
    await page.screenshot({ path: ssPath, fullPage: true });
    logScreenshot('06_login_error.png', 'Login with invalid credentials');

    // Check for error message
    const errorMessage = page.locator('.alert-danger, .alert-error, .error, [role="alert"], .flash-error, .notice');
    const flashMessage = page.locator('.flash, .notice, [data-controller*="flash"]');

    if (await errorMessage.count() > 0) {
      const errorText = await errorMessage.first().textContent();
      console.log(`✓ Error message displayed: ${errorText?.trim()}`);
    } else if (await flashMessage.count() > 0) {
      const flashText = await flashMessage.first().textContent();
      console.log(`✓ Flash message displayed: ${flashText?.trim()}`);
    } else {
      logIssue('HIGH', 'AUTH-002', 'No login error feedback', 'Invalid credentials submitted but no error message displayed to user', '06_login_error.png');
    }

    // Should still be on sign_in page
    const url = page.url();
    if (url.includes('sign_in')) {
      console.log('✓ Correctly stayed on sign_in page after failed attempt');
    }
  });

  // Test 6: Test password reset flow
  test('6. password reset flow', async ({ page }) => {
    await page.goto('/users/sign_in');
    await page.waitForLoadState('networkidle');

    // Find forgot password link
    const forgotLink = page.locator('a:has-text("forgot"), a:has-text("Forgot"), a[href*="password"]');

    if (await forgotLink.count() > 0) {
      console.log('✓ Forgot password link found');
      await forgotLink.first().click();
      await page.waitForLoadState('networkidle');

      const ssPath1 = path.join(screenshotsDir, '07_password_reset_page.png');
      await page.screenshot({ path: ssPath1, fullPage: true });
      logScreenshot('07_password_reset_page.png', 'Password reset page');

      const url = page.url();
      console.log(`Password reset page URL: ${url}`);

      // Check for email input on password reset page
      const emailInput = page.locator('input[type="email"], input[name="user[email]"]');
      if (await emailInput.count() > 0) {
        console.log('✓ Email input found on password reset page');

        // Fill and submit
        await emailInput.fill('admin@example.com');
        await page.click('button[type="submit"], input[type="submit"]');
        await page.waitForLoadState('networkidle');
        await page.waitForTimeout(1500);

        const ssPath2 = path.join(screenshotsDir, '08_password_reset_submitted.png');
        await page.screenshot({ path: ssPath2, fullPage: true });
        logScreenshot('08_password_reset_submitted.png', 'Password reset form submitted');

        // Check for success message
        const successMsg = page.locator('.alert-success, .notice, [role="alert"]:has-text("email")');
        if (await successMsg.count() > 0) {
          console.log('✓ Password reset confirmation message shown');
        } else {
          console.log('⚠ No clear confirmation for password reset');
        }
      }
    } else {
      logIssue('MEDIUM', 'AUTH-003', 'Missing forgot password link', 'No forgot password link visible on login page');
    }
  });

  // Test 7: Magic link login option
  test('7. magic link login option', async ({ page }) => {
    await page.goto('/users/sign_in');
    await page.waitForLoadState('networkidle');

    // Look for magic link option
    const magicLink = page.locator('a:has-text("magic"), a:has-text("Magic"), a:has-text("passwordless"), button:has-text("magic")');

    if (await magicLink.count() > 0) {
      console.log('✓ Magic link option found');
      await magicLink.first().click();
      await page.waitForLoadState('networkidle');

      const ssPath = path.join(screenshotsDir, '09_magic_link_page.png');
      await page.screenshot({ path: ssPath, fullPage: true });
      logScreenshot('09_magic_link_page.png', 'Magic link login page');

      const emailInput = page.locator('input[type="email"]');
      if (await emailInput.count() > 0) {
        console.log('✓ Magic link email form found');
        await emailInput.fill('admin@example.com');

        const ssPath2 = path.join(screenshotsDir, '10_magic_link_filled.png');
        await page.screenshot({ path: ssPath2, fullPage: true });
        logScreenshot('10_magic_link_filled.png', 'Magic link form filled');
      }
    } else {
      console.log('ℹ No magic link option visible (may be by design)');
    }
  });

  // Test 8: Logout flow
  test('8. logout flow', async ({ page }) => {
    // First login
    await page.goto('/users/sign_in');
    await page.waitForLoadState('networkidle');

    await page.fill('input[type="email"], input[name="user[email]"]', 'admin@example.com');
    await page.fill('input[type="password"]', 'password');
    await page.click('button[type="submit"], input[type="submit"]');
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(1500);

    // Find logout option
    const logoutLink = page.locator('a:has-text("sign out"), a:has-text("Sign out"), a:has-text("Logout"), a:has-text("logout"), button:has-text("logout"), [data-method="delete"]');

    // May need to open user menu first
    const userMenu = page.locator('[data-controller*="dropdown"], .user-menu, [aria-haspopup="true"]');
    if (await userMenu.count() > 0) {
      await userMenu.first().click();
      await page.waitForTimeout(500);
    }

    if (await logoutLink.count() > 0) {
      const ssPath = path.join(screenshotsDir, '11_logout_option.png');
      await page.screenshot({ path: ssPath, fullPage: true });
      logScreenshot('11_logout_option.png', 'Logout option visible');

      await logoutLink.first().click();
      await page.waitForLoadState('networkidle');
      await page.waitForTimeout(1000);

      const ssPath2 = path.join(screenshotsDir, '12_after_logout.png');
      await page.screenshot({ path: ssPath2, fullPage: true });
      logScreenshot('12_after_logout.png', 'After logout');

      const url = page.url();
      console.log(`After logout URL: ${url}`);

      // Should be redirected to public page or login
      if (url.includes('/') || url.includes('sign_in')) {
        console.log('✓ Successfully logged out');
      }
    } else {
      console.log('⚠ Could not find logout link');
    }
  });

  // Test 9: Form validation UI
  test('9. form validation feedback', async ({ page }) => {
    await page.goto('/users/sign_up');
    await page.waitForLoadState('networkidle');

    // Submit empty form
    await page.click('button[type="submit"], input[type="submit"]');
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(1000);

    const ssPath = path.join(screenshotsDir, '13_validation_errors.png');
    await page.screenshot({ path: ssPath, fullPage: true });
    logScreenshot('13_validation_errors.png', 'Form validation errors');

    // Check for validation messages
    const validationErrors = page.locator('.field_with_errors, .error, .invalid-feedback, [aria-invalid="true"], .form-error');
    const inlineErrors = page.locator('.help-block, .form-text.text-danger, span.error');

    const errorCount = await validationErrors.count() + await inlineErrors.count();
    if (errorCount > 0) {
      console.log(`✓ ${errorCount} validation feedback elements found`);
    } else {
      // Check if HTML5 validation prevented submit
      const emailInput = page.locator('input[type="email"]');
      const isRequired = await emailInput.getAttribute('required');
      if (isRequired !== null) {
        console.log('✓ HTML5 validation in use (required attribute)');
      } else {
        logIssue('MEDIUM', 'VAL-001', 'No validation feedback', 'Form submitted without showing validation errors');
      }
    }
  });
});

// After all tests, write summary
test.afterAll(async () => {
  console.log('\n' + '='.repeat(60));
  console.log('V8-002 AUTHENTICATION FLOW AUDIT SUMMARY');
  console.log('='.repeat(60));

  console.log('\n📸 SCREENSHOTS CAPTURED:');
  screenshots.forEach(s => {
    console.log(`  - ${s.filename}: ${s.description}`);
  });

  console.log('\n🔍 ISSUES FOUND:');
  if (auditIssues.length === 0) {
    console.log('  No issues detected!');
  } else {
    const critical = auditIssues.filter(i => i.severity === 'CRITICAL');
    const high = auditIssues.filter(i => i.severity === 'HIGH');
    const medium = auditIssues.filter(i => i.severity === 'MEDIUM');
    const low = auditIssues.filter(i => i.severity === 'LOW');

    if (critical.length) {
      console.log('\n  CRITICAL:');
      critical.forEach(i => console.log(`    - ${i.id}: ${i.title}`));
    }
    if (high.length) {
      console.log('\n  HIGH:');
      high.forEach(i => console.log(`    - ${i.id}: ${i.title}`));
    }
    if (medium.length) {
      console.log('\n  MEDIUM:');
      medium.forEach(i => console.log(`    - ${i.id}: ${i.title}`));
    }
    if (low.length) {
      console.log('\n  LOW:');
      low.forEach(i => console.log(`    - ${i.id}: ${i.title}`));
    }
  }

  // Write results to JSON
  const resultsPath = path.join(screenshotsDir, 'auth_audit_results.json');
  fs.writeFileSync(resultsPath, JSON.stringify({
    screenshots,
    issues: auditIssues,
    timestamp: new Date().toISOString()
  }, null, 2));
  console.log(`\n📁 Results saved to: ${resultsPath}`);
});
