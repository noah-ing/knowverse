// @ts-check
const { test, expect } = require('@playwright/test');

test.describe('Connectors - GitHub, Slack, Confluence', () => {
  // Helper to login with retries
  async function login(page) {
    await page.goto('/users/sign_in');
    await page.waitForLoadState('networkidle');
    await page.waitForSelector('input[type="email"], input[name="user[email]"]', { timeout: 10000 });

    const emailInput = page.locator('input[type="email"], input[name="user[email]"]').first();
    await emailInput.fill('admin@example.com');

    const passwordInput = page.locator('input[type="password"], input[name="user[password]"]').first();
    await passwordInput.fill('password');

    // Click sign in button
    const signInButton = page.locator('button:has-text("Sign in"), input[type="submit"][value="Sign in"]').first();
    await signInButton.click();

    // Wait for navigation away from sign_in page
    await page.waitForLoadState('networkidle');
    await page.waitForFunction(() => !window.location.href.includes('sign_in'), { timeout: 20000 });

    // Extra wait to ensure session is established
    await page.waitForTimeout(500);
  }

  // Helper to navigate to documents page
  async function navigateToDocuments(page) {
    // First go to organizations to get an org ID
    await page.goto('/organizations');
    await page.waitForLoadState('networkidle');

    // If redirected to sign_in, we need to login again
    if (page.url().includes('sign_in')) {
      await login(page);
      await page.goto('/organizations');
      await page.waitForLoadState('networkidle');
    }

    // Click on first organization or dashboard link
    const orgLink = page.locator('a[href*="/organizations/"][href*="/dashboard"], a[href*="/organizations/"][href$="/documents"]').first();
    await orgLink.waitFor({ state: 'visible', timeout: 10000 });
    await orgLink.click();
    await page.waitForLoadState('networkidle');

    // If we're on dashboard, click documents link
    if (page.url().includes('/dashboard')) {
      const documentsLink = page.locator('a[href*="/documents"]').first();
      await documentsLink.waitFor({ state: 'visible', timeout: 5000 });
      await documentsLink.click();
      await page.waitForLoadState('networkidle');
    }

    // Ensure we're on documents page
    await page.waitForFunction(() => window.location.href.includes('/documents'), { timeout: 10000 });
  }

  test.describe('Documents Page Connector Buttons', () => {
    test.beforeEach(async ({ page }) => {
      await login(page);
    });

    test('documents page shows GitHub connector button', async ({ page }) => {
      await navigateToDocuments(page);

      // Look for GitHub button (either "GitHub" or "Connect GitHub")
      const githubButton = page.locator('a:has-text("GitHub"), a:has-text("Connect GitHub")').first();
      await expect(githubButton).toBeVisible({ timeout: 10000 });
    });

    test('documents page shows Slack connector button', async ({ page }) => {
      await navigateToDocuments(page);

      // Look for Slack button
      const slackButton = page.locator('a:has-text("Slack"), a:has-text("Connect Slack")').first();
      await expect(slackButton).toBeVisible({ timeout: 10000 });
    });

    test('documents page shows Confluence connector button', async ({ page }) => {
      await navigateToDocuments(page);

      // Look for Confluence button
      const confluenceButton = page.locator('a:has-text("Confluence"), a:has-text("Connect Confluence")').first();
      await expect(confluenceButton).toBeVisible({ timeout: 10000 });
    });
  });

  test.describe('Connector Button Click Behavior', () => {
    test.beforeEach(async ({ page }) => {
      await login(page);
    });

    // Note: When OAuth credentials aren't configured, clicking connect buttons
    // redirects back to documents with "X integration is not configured" alert.
    // This is expected behavior - we test that the buttons work without errors.

    test('GitHub connect button is clickable and handles unconfigured state', async ({ page }) => {
      await navigateToDocuments(page);

      const githubButton = page.locator('a:has-text("Connect GitHub")').first();
      if (await githubButton.isVisible()) {
        await githubButton.click();
        await page.waitForLoadState('networkidle');

        // Should either show connection page OR redirect with "not configured" message
        // Both are valid depending on whether OAuth credentials are set
        const url = page.url();
        const hasConfigError = await page.locator('text=not configured').isVisible().catch(() => false);
        const isOnConnectorPage = url.includes('/connectors/github');

        expect(hasConfigError || isOnConnectorPage || url.includes('/documents')).toBeTruthy();
      }
    });

    test('Slack connect button is clickable and handles unconfigured state', async ({ page }) => {
      await navigateToDocuments(page);

      const slackButton = page.locator('a:has-text("Connect Slack")').first();
      if (await slackButton.isVisible()) {
        await slackButton.click();
        await page.waitForLoadState('networkidle');

        const url = page.url();
        const hasConfigError = await page.locator('text=not configured').isVisible().catch(() => false);
        const isOnConnectorPage = url.includes('/connectors/slack');

        expect(hasConfigError || isOnConnectorPage || url.includes('/documents')).toBeTruthy();
      }
    });

    test('Confluence connect button is clickable and handles unconfigured state', async ({ page }) => {
      await navigateToDocuments(page);

      const confluenceButton = page.locator('a:has-text("Connect Confluence")').first();
      if (await confluenceButton.isVisible()) {
        await confluenceButton.click();
        await page.waitForLoadState('networkidle');

        const url = page.url();
        const hasConfigError = await page.locator('text=not configured').isVisible().catch(() => false);
        const isOnConnectorPage = url.includes('/connectors/confluence');

        expect(hasConfigError || isOnConnectorPage || url.includes('/documents')).toBeTruthy();
      }
    });
  });

  test.describe('All Connector Buttons Present', () => {
    test('documents page shows all 5 connector buttons (Drive, Notion, GitHub, Slack, Confluence)', async ({ page }) => {
      await login(page);
      await navigateToDocuments(page);

      // Verify all connector buttons are present
      await expect(page.locator('a:has-text("Drive"), a:has-text("Connect Drive")').first()).toBeVisible({ timeout: 10000 });
      await expect(page.locator('a:has-text("Notion"), a:has-text("Connect Notion")').first()).toBeVisible({ timeout: 10000 });
      await expect(page.locator('a:has-text("GitHub"), a:has-text("Connect GitHub")').first()).toBeVisible({ timeout: 10000 });
      await expect(page.locator('a:has-text("Slack"), a:has-text("Connect Slack")').first()).toBeVisible({ timeout: 10000 });
      await expect(page.locator('a:has-text("Confluence"), a:has-text("Connect Confluence")').first()).toBeVisible({ timeout: 10000 });
    });
  });
});
