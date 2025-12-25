// @ts-check
const { test, expect } = require('@playwright/test');

test.describe('Billing & Subscription Pages', () => {
  // Helper to login
  async function login(page) {
    await page.goto('/users/sign_in');

    // Wait for form to be ready
    await page.waitForSelector('input[type="email"], input[name="user[email]"]');

    // Fill email - try multiple selectors
    const emailInput = page.locator('input[type="email"], input[name="user[email]"]').first();
    await emailInput.fill('admin@example.com');

    // Fill password
    const passwordInput = page.locator('input[type="password"], input[name="user[password]"]').first();
    await passwordInput.fill('password');

    // Click submit
    await page.click('button:has-text("Sign in"), input[type="submit"]');

    // Wait for navigation to complete
    await page.waitForLoadState('networkidle');

    // Verify we're no longer on sign_in page (login succeeded)
    await page.waitForFunction(() => !window.location.href.includes('sign_in'), { timeout: 15000 });
  }

  // Helper to ensure an organization exists
  async function ensureOrganization(page) {
    await page.goto('/organizations');
    await page.waitForLoadState('networkidle');

    // Check if we have no organizations
    const noOrgsText = page.locator('text=You don\'t have any organizations yet');
    if (await noOrgsText.isVisible({ timeout: 3000 }).catch(() => false)) {
      // Create one
      await page.click('text=Create Organization');
      await page.waitForSelector('input[name="organization[name]"]');
      await page.fill('input[name="organization[name]"]', 'Test Organization');
      await page.click('button:has-text("Create"), input[type="submit"]');
      await page.waitForLoadState('networkidle');
    }

    // Get first org link
    const orgLink = page.locator('a[href*="/organizations/"]').first();
    if (await orgLink.count() > 0) {
      const href = await orgLink.getAttribute('href');
      const orgId = href.match(/\/organizations\/(\d+)/)?.[1];
      return orgId || '1';
    }
    return '1';
  }

  test.beforeEach(async ({ page }) => {
    await login(page);
  });

  test('can access organization settings', async ({ page }) => {
    const orgId = await ensureOrganization(page);

    // Navigate to settings
    await page.goto(`/organizations/${orgId}/settings`);
    await page.waitForLoadState('networkidle');

    // Should see Organization Details section (main content)
    await expect(page.locator('h3:has-text("Organization Details")')).toBeVisible({ timeout: 10000 });
    // Should see Team Members section
    await expect(page.locator('h3:has-text("Team Members")')).toBeVisible();
  });

  test('settings page has billing link', async ({ page }) => {
    const orgId = await ensureOrganization(page);
    await page.goto(`/organizations/${orgId}/settings`);
    await page.waitForLoadState('networkidle');

    // Check for billing link in sidebar
    const billingLink = page.locator('a:has-text("Billing")');
    await expect(billingLink).toBeVisible({ timeout: 10000 });
  });

  test('billing page loads with plan info', async ({ page }) => {
    const orgId = await ensureOrganization(page);
    await page.goto(`/organizations/${orgId}/subscription`);
    await page.waitForLoadState('networkidle');

    // Should show billing page heading
    await expect(page.locator('h1:has-text("Billing")')).toBeVisible({ timeout: 10000 });

    // Should show current plan section
    await expect(page.locator('h3:has-text("Current Plan")')).toBeVisible();

    // Should show usage section
    await expect(page.locator('h3:has-text("Usage & Quotas")')).toBeVisible();
  });

  test('plan selection page displays all plans', async ({ page }) => {
    const orgId = await ensureOrganization(page);
    await page.goto(`/organizations/${orgId}/subscription/new`);
    await page.waitForLoadState('networkidle');

    // Should show page title
    await expect(page.locator('h1:has-text("Choose Your Plan")')).toBeVisible({ timeout: 10000 });

    // Should show all 4 plan headings
    await expect(page.locator('h3:has-text("Free")')).toBeVisible();
    await expect(page.locator('h3:has-text("Starter")')).toBeVisible();
    await expect(page.locator('h3:has-text("Growth")')).toBeVisible();
    await expect(page.locator('h3:has-text("Business")')).toBeVisible();
  });

  test('plan cards show correct pricing', async ({ page }) => {
    const orgId = await ensureOrganization(page);
    await page.goto(`/organizations/${orgId}/subscription/new`);
    await page.waitForLoadState('networkidle');

    // Check pricing is displayed (use contains since format is $49.00)
    await expect(page.locator('text=$49.00')).toBeVisible({ timeout: 10000 });
    await expect(page.locator('text=$149.00')).toBeVisible();
    await expect(page.locator('text=$399.00')).toBeVisible();
  });

  test('quota usage bars are visible', async ({ page }) => {
    const orgId = await ensureOrganization(page);
    await page.goto(`/organizations/${orgId}/subscription`);
    await page.waitForLoadState('networkidle');

    // Should have progress bars for quotas
    const progressBars = page.locator('[class*="bg-"][class*="rounded-full"]');
    await expect(progressBars.first()).toBeVisible({ timeout: 10000 });
  });

  test('FAQ section is present on plan selection', async ({ page }) => {
    const orgId = await ensureOrganization(page);
    await page.goto(`/organizations/${orgId}/subscription/new`);
    await page.waitForLoadState('networkidle');

    // Check FAQ section
    await expect(page.locator('text=Frequently Asked Questions')).toBeVisible({ timeout: 10000 });
    await expect(page.locator('text=Can I change plans later')).toBeVisible();
  });
});
