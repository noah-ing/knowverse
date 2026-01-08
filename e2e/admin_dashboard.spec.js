/**
 * V8-005: Admin Dashboard Testing
 *
 * Tests the admin dashboard functionality including:
 * - Admin login and access
 * - Dashboard navigation
 * - User management (list, search, edit)
 * - Organization settings
 * - Data table pagination and sorting
 * - Admin-only access controls
 */

const { test, expect } = require('@playwright/test');
const path = require('path');

const BASE_URL = 'http://localhost:3000';
const ADMIN_EMAIL = 'admin@example.com';
const ADMIN_PASSWORD = 'password';
const SCREENSHOT_DIR = path.join(__dirname, '..', 'frontend_audit_screenshots', 'v8-005');

// Helper to take screenshots with timestamp
async function takeScreenshot(page, name) {
  const filename = `${name}.png`;
  await page.screenshot({
    path: path.join(SCREENSHOT_DIR, filename),
    fullPage: true
  });
  console.log(`Screenshot saved: ${filename}`);
  return filename;
}

// Helper to dismiss cookie banner if present
async function dismissCookieBanner(page) {
  try {
    const acceptButton = page.locator('text=Accept All').first();
    if (await acceptButton.isVisible({ timeout: 2000 })) {
      await acceptButton.click();
      console.log('Cookie banner dismissed');
    }
  } catch (e) {
    // Banner not present or already dismissed
  }
}

// Helper to login as admin
async function loginAsAdmin(page) {
  await page.goto(`${BASE_URL}/users/sign_in`);
  await dismissCookieBanner(page);
  await page.fill('input[name="user[email]"]', ADMIN_EMAIL);
  await page.fill('input[name="user[password]"]', ADMIN_PASSWORD);
  await page.click('input[type="submit"], button[type="submit"]');
  await page.waitForTimeout(2000);

  // Check if login was successful (should redirect away from sign_in)
  const currentUrl = page.url();
  if (currentUrl.includes('/users/sign_in')) {
    console.log('Login may have failed - still on sign_in page');
    return false;
  }
  console.log('Logged in as admin');
  return true;
}

test.describe('V8-005: Admin Dashboard Testing', () => {

  test.beforeEach(async ({ page }) => {
    // Login as admin before each test
    const success = await loginAsAdmin(page);
    expect(success).toBe(true);
  });

  test('Admin access - Navigate to admin dashboard', async ({ page }) => {
    // Navigate to admin dashboard
    await page.goto(`${BASE_URL}/admin`);
    await page.waitForTimeout(1000);

    // Check if we're on the admin page or redirected
    const currentUrl = page.url();
    console.log(`Current URL: ${currentUrl}`);

    // Take screenshot of admin dashboard or access denied page
    if (currentUrl.includes('/admin')) {
      await takeScreenshot(page, '01_admin_dashboard');
      console.log('PASS: Successfully accessed admin dashboard');
    } else {
      await takeScreenshot(page, '01_admin_access_denied');
      console.log(`FAIL: Redirected to ${currentUrl} - admin access may not be set up`);
    }

    // Check for admin navigation elements
    const pageContent = await page.content();
    console.log('\nAdmin page elements found:');

    const navLinks = await page.locator('nav a, aside a, .sidebar a, .nav a').allTextContents();
    console.log('Navigation links:', navLinks.join(', '));
  });

  test('Admin navigation - Test all admin sections', async ({ page }) => {
    await page.goto(`${BASE_URL}/admin`);
    await page.waitForTimeout(1000);

    const adminSections = [
      { name: 'Dashboard', path: '/admin' },
      { name: 'Mission Control', path: '/admin/mission_control' },
      { name: 'Users', path: '/admin/users' },
      { name: 'Analytics', path: '/admin/analytics' },
      { name: 'Search Metrics', path: '/admin/search_metrics' },
      { name: 'Distributed', path: '/admin/distributed/dashboard' },
      { name: 'LLM Providers', path: '/admin/llm_providers' },
      { name: 'Embedding Cache', path: '/admin/embedding_cache/dashboard' },
    ];

    const visitedSections = [];

    for (const section of adminSections) {
      await page.goto(`${BASE_URL}${section.path}`);
      await page.waitForTimeout(500);

      const currentUrl = page.url();
      const status = currentUrl.includes('/admin') ? 'accessible' : 'redirected';
      visitedSections.push({ ...section, status, actualUrl: currentUrl });

      // Take screenshot for key sections
      if (['Dashboard', 'Users', 'Analytics', 'Mission Control'].includes(section.name)) {
        const screenshotName = `02_admin_${section.name.toLowerCase().replace(/\s+/g, '_')}`;
        await takeScreenshot(page, screenshotName);
      }
    }

    console.log('\nAdmin sections navigation results:');
    visitedSections.forEach(s => {
      console.log(`  ${s.name}: ${s.status} (${s.actualUrl})`);
    });
  });

  test('User management - List and search users', async ({ page }) => {
    await page.goto(`${BASE_URL}/admin/users`);
    await page.waitForTimeout(1000);

    await takeScreenshot(page, '03_admin_users_list');

    // Check for user table
    const table = page.locator('table');
    const hasTable = await table.count() > 0;
    console.log(`User table present: ${hasTable}`);

    if (hasTable) {
      // Count rows
      const rows = await page.locator('table tbody tr').count();
      console.log(`User rows in table: ${rows}`);

      // Check for table headers
      const headers = await page.locator('table th').allTextContents();
      console.log('Table headers:', headers.join(', '));
    }

    // Look for search functionality
    const searchInput = page.locator('input[type="search"], input[name*="search"], input[placeholder*="Search"]');
    const hasSearch = await searchInput.count() > 0;
    console.log(`Search input present: ${hasSearch}`);

    if (hasSearch) {
      await searchInput.first().fill('admin');
      await page.waitForTimeout(500);
      await takeScreenshot(page, '04_admin_users_search');
    }

    // Check for pagination
    const pagination = page.locator('.pagination, nav[aria-label*="pagination"], [data-controller="pagination"]');
    const hasPagination = await pagination.count() > 0;
    console.log(`Pagination present: ${hasPagination}`);
  });

  test('User management - View/edit user', async ({ page }) => {
    await page.goto(`${BASE_URL}/admin/users`);
    await page.waitForTimeout(1000);

    // Look for edit links or view buttons
    const editLinks = page.locator('a[href*="/edit"], button:has-text("Edit"), a:has-text("Edit")');
    const editCount = await editLinks.count();
    console.log(`Edit links/buttons found: ${editCount}`);

    const viewLinks = page.locator('a[href*="/admin/users/"][href$=""]').filter({ hasNotText: 'Edit' });
    const viewCount = await viewLinks.count();
    console.log(`View links found: ${viewCount}`);

    // Click first user if available
    if (editCount > 0) {
      await editLinks.first().click();
      await page.waitForTimeout(500);
      await takeScreenshot(page, '05_admin_user_edit');

      // Check for form fields
      const formFields = await page.locator('input, select, textarea').count();
      console.log(`Form fields on edit page: ${formFields}`);
    } else if (viewCount > 0) {
      await viewLinks.first().click();
      await page.waitForTimeout(500);
      await takeScreenshot(page, '05_admin_user_view');
    }
  });

  test('Analytics - View analytics dashboard', async ({ page }) => {
    await page.goto(`${BASE_URL}/admin/analytics`);
    await page.waitForTimeout(1000);

    await takeScreenshot(page, '06_admin_analytics');

    // Check for analytics elements (charts, stats, tables)
    const charts = await page.locator('canvas, svg, .chart, [data-chart]').count();
    console.log(`Chart elements: ${charts}`);

    const statCards = await page.locator('.stat, .card, .metric, [data-stat]').count();
    console.log(`Stat cards: ${statCards}`);

    // Check for date filters
    const dateInputs = await page.locator('input[type="date"], [data-controller*="date"], .datepicker').count();
    console.log(`Date filter inputs: ${dateInputs}`);
  });

  test('Mission Control - View system status', async ({ page }) => {
    await page.goto(`${BASE_URL}/admin/mission_control`);
    await page.waitForTimeout(1000);

    await takeScreenshot(page, '07_admin_mission_control');

    // Check for status indicators
    const statusIndicators = await page.locator('.status, .indicator, .badge, [class*="status"]').count();
    console.log(`Status indicators: ${statusIndicators}`);

    // Check for system metrics
    const content = await page.textContent('body');
    const hasMetrics = content.includes('CPU') || content.includes('Memory') || content.includes('Status') || content.includes('Health');
    console.log(`System metrics present: ${hasMetrics}`);
  });

  test('Search Metrics - View search analytics', async ({ page }) => {
    await page.goto(`${BASE_URL}/admin/search_metrics`);
    await page.waitForTimeout(1000);

    await takeScreenshot(page, '08_admin_search_metrics');

    // Check for search-related metrics
    const content = await page.textContent('body');
    const hasSearchData = content.includes('Search') || content.includes('Query') || content.includes('Results');
    console.log(`Search metrics present: ${hasSearchData}`);
  });

  test('LLM Providers - View provider configuration', async ({ page }) => {
    await page.goto(`${BASE_URL}/admin/llm_providers`);
    await page.waitForTimeout(1000);

    await takeScreenshot(page, '09_admin_llm_providers');

    // Check for provider listings
    const content = await page.textContent('body');
    const hasProviders = content.includes('Provider') || content.includes('API') || content.includes('OpenAI') || content.includes('Anthropic') || content.includes('Claude');
    console.log(`LLM provider config present: ${hasProviders}`);
  });

  test('Distributed System - View cluster status', async ({ page }) => {
    await page.goto(`${BASE_URL}/admin/distributed/dashboard`);
    await page.waitForTimeout(1000);

    await takeScreenshot(page, '10_admin_distributed');

    // Check for cluster/node information
    const content = await page.textContent('body');
    const hasClusterInfo = content.includes('Node') || content.includes('Cluster') || content.includes('Distributed') || content.includes('Replica');
    console.log(`Distributed system info present: ${hasClusterInfo}`);
  });

  test('Access control - Test non-admin access denied', async ({ page }) => {
    // Logout
    await page.goto(`${BASE_URL}/users/sign_out`);
    await page.waitForTimeout(500);

    // Try to access admin pages without auth
    await page.goto(`${BASE_URL}/admin`);
    await page.waitForTimeout(500);

    const currentUrl = page.url();
    if (currentUrl.includes('/users/sign_in')) {
      console.log('PASS: Unauthenticated user redirected to login');
    } else {
      console.log(`WARN: Unauthenticated access resulted in: ${currentUrl}`);
    }

    await takeScreenshot(page, '11_admin_access_control');
  });

  test('Data tables - Check pagination and sorting', async ({ page }) => {
    await page.goto(`${BASE_URL}/admin/users`);
    await page.waitForTimeout(1000);

    // Check for sortable columns
    const sortableHeaders = await page.locator('th[data-sort], th a, th button').count();
    console.log(`Sortable column headers: ${sortableHeaders}`);

    // Check for pagination controls
    const paginationControls = await page.locator('.pagination a, [aria-label*="page"], .page-link').count();
    console.log(`Pagination controls: ${paginationControls}`);

    // Check for page size selector
    const pageSizeSelector = await page.locator('select[name*="per_page"], select[name*="limit"]').count();
    console.log(`Page size selector: ${pageSizeSelector}`);

    // Try clicking a sortable header if present
    const sortableHeader = page.locator('th[data-sort], th a').first();
    if (await sortableHeader.count() > 0) {
      await sortableHeader.click();
      await page.waitForTimeout(500);
      await takeScreenshot(page, '12_admin_users_sorted');
    }
  });

  test('Embedding Cache - View cache dashboard', async ({ page }) => {
    await page.goto(`${BASE_URL}/admin/embedding_cache/dashboard`);
    await page.waitForTimeout(1000);

    await takeScreenshot(page, '13_admin_embedding_cache');

    // Check for cache metrics
    const content = await page.textContent('body');
    const hasCacheInfo = content.includes('Cache') || content.includes('Embedding') || content.includes('Hit') || content.includes('Miss');
    console.log(`Embedding cache info present: ${hasCacheInfo}`);
  });

});
