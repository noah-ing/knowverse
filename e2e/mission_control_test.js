// @ts-check
const { chromium } = require('playwright');

const CREDENTIALS = {
  email: process.env.TEST_EMAIL || 'noah.ing@protonmail.com',
  password: process.env.TEST_PASSWORD || 'No$$ah10304632'
};

const BASE_URL = 'http://localhost:3000';

async function run() {
  console.log('Starting Mission Control E2E Test...\n');

  let browser;
  try {
    browser = await chromium.launch({
      headless: true,
      slowMo: 50
    });

    const context = await browser.newContext({
      viewport: { width: 1440, height: 900 }
    });

    const page = await context.newPage();

    // Login
    console.log('Test 1: Logging in...');
    await page.goto(`${BASE_URL}/users/sign_in`);
    await page.waitForSelector('input[type="email"]', { timeout: 10000 });

    await page.fill('input[type="email"]', CREDENTIALS.email);
    await page.fill('input[type="password"]', CREDENTIALS.password);

    // Click and wait for navigation
    await Promise.all([
      page.waitForNavigation({ waitUntil: 'domcontentloaded', timeout: 20000 }),
      page.click('button[type="submit"], input[type="submit"]')
    ]).catch(async () => {
      // If navigation doesn't happen, just wait
      await page.waitForTimeout(3000);
    });

    // Check if we're logged in by looking at current URL
    const afterLoginUrl = page.url();
    console.log(`   After login URL: ${afterLoginUrl}`);

    if (afterLoginUrl.includes('sign_in')) {
      console.log('   WARNING: Still on sign_in page, checking for errors...');
      const errorMsg = await page.locator('.alert, .flash, .error').textContent().catch(() => 'No error found');
      console.log(`   Error message: ${errorMsg}`);
    }
    console.log('   OK - Login attempted\n');

    // Navigate to Mission Control directly
    console.log('Test 2: Navigating to Mission Control...');
    await page.goto(`${BASE_URL}/admin/mission_control`, { timeout: 30000 });
    await page.waitForLoadState('domcontentloaded');

    // Wait for the page to render
    await page.waitForTimeout(2000);

    const currentUrl = page.url();
    console.log(`   Current URL: ${currentUrl}`);

    if (currentUrl.includes('sign_in')) {
      console.log('   ERROR: Redirected to login - user may not be admin');
      // Take screenshot anyway
      await page.screenshot({ path: '/Users/noah-ing/Desktop/knowverse/e2e/screenshots/login_required.png' });
    } else {
      // Verify Mission Control page
      console.log('Test 3: Verifying Mission Control elements...');

      const title = await page.title();
      console.log(`   Page title: ${title}`);

      // Check for key elements with fallback
      const logoText = await page.locator('.mc-logo-text').textContent().catch(() => 'NOT FOUND');
      console.log(`   Logo text: ${logoText}`);

      const metricsCount = await page.locator('.mc-metric-value').count();
      console.log(`   Metrics found: ${metricsCount}`);

      const panelsCount = await page.locator('.mc-panel').count();
      console.log(`   Panels found: ${panelsCount}`);

      const statusDots = await page.locator('.mc-status-dot').count();
      console.log(`   Status indicators: ${statusDots}`);

      // Take screenshot
      const fs = require('fs');
      const screenshotsDir = '/Users/noah-ing/Desktop/knowverse/e2e/screenshots';
      if (!fs.existsSync(screenshotsDir)) {
        fs.mkdirSync(screenshotsDir, { recursive: true });
      }
      await page.screenshot({ path: `${screenshotsDir}/mission_control.png`, fullPage: true });
      console.log('   Screenshot saved\n');

      // Test status API
      console.log('Test 4: Status API...');
      const statusResponse = await page.request.get(`${BASE_URL}/admin/mission_control/status`);
      console.log(`   API Status: ${statusResponse.status()}`);
      if (statusResponse.ok()) {
        const data = await statusResponse.json();
        console.log(`   Timestamp: ${data.timestamp}`);
        console.log(`   Documents: ${data.system?.total_documents || 0}`);
      }
      console.log('\n');
    }

    console.log('========================================');
    console.log('TEST COMPLETE');
    console.log('========================================');

  } catch (error) {
    console.error('TEST ERROR:', error.message);
    throw error;
  } finally {
    if (browser) {
      await browser.close();
      console.log('Browser closed.');
    }
  }
}

run().catch(err => {
  console.error(err);
  process.exit(1);
});
