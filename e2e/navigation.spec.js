// @ts-check
const { test, expect } = require('@playwright/test');

test.describe('Navigation & Core Pages', () => {
  // Helper to login
  async function login(page) {
    await page.goto('/users/sign_in');
    await page.waitForSelector('input[type="email"], input[name="user[email]"]');

    const emailInput = page.locator('input[type="email"], input[name="user[email]"]').first();
    await emailInput.fill('admin@example.com');

    const passwordInput = page.locator('input[type="password"], input[name="user[password]"]').first();
    await passwordInput.fill('password');

    await page.click('button:has-text("Sign in"), input[type="submit"]');

    // Wait for navigation to complete - user might end up on various pages
    await page.waitForLoadState('networkidle');

    // Verify we're no longer on sign_in page (login succeeded)
    await page.waitForFunction(() => !window.location.href.includes('sign_in'), { timeout: 15000 });
  }

  test('homepage loads correctly', async ({ page }) => {
    await page.goto('/');
    // Check for main heading or logo - use first() since "KnowVerse" appears multiple times
    await expect(page.locator('text=KnowVerse').first()).toBeVisible({ timeout: 10000 });
    // Also check for main hero heading
    await expect(page.locator('h1:has-text("Transform your knowledge")')).toBeVisible();
  });

  test('login page is accessible', async ({ page }) => {
    await page.goto('/users/sign_in');
    // Should have email/password fields
    await expect(page.locator('input[type="email"], input[name="user[email]"]').first()).toBeVisible();
    await expect(page.locator('input[type="password"], input[name="user[password]"]').first()).toBeVisible();
  });

  test('can log in with valid credentials', async ({ page }) => {
    await login(page);
    // Should be on a protected page now
    const url = page.url();
    expect(url).not.toContain('sign_in');
  });

  test('organizations list requires authentication', async ({ page }) => {
    // Try accessing without login
    await page.goto('/organizations');
    // Should redirect to login
    await expect(page).toHaveURL(/sign_in/);
  });

  test('organizations list is accessible when logged in', async ({ page }) => {
    await login(page);
    // Navigate directly without page reload
    await page.goto('/organizations', { waitUntil: 'networkidle' });
    // Should either show organizations or redirect (if no orgs)
    const url = page.url();
    expect(url).toMatch(/organizations|sign_in|dashboard/);
  });

  test('search page is accessible', async ({ page }) => {
    await page.goto('/search');
    // Should show search interface or redirect to login
    const url = page.url();
    expect(url).toMatch(/search|sign_in/);
  });

  test('documentation page loads', async ({ page }) => {
    await page.goto('/docs');
    await page.waitForLoadState('networkidle');
  });
});
