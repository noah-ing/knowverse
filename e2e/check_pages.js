const { chromium } = require('playwright');

async function run() {
  const browser = await chromium.launch({ headless: true });
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });

  // Login with proper wait
  console.log('=== LOGGING IN ===');
  await page.goto('http://localhost:3000/users/sign_in');
  await page.waitForSelector('input[type="email"]');
  await page.fill('input[type="email"]', 'noah.ing@protonmail.com');
  await page.fill('input[type="password"]', 'No$$ah10304632');

  // Click submit and wait for navigation
  await Promise.all([
    page.waitForURL(url => !url.toString().includes('sign_in'), { timeout: 10000 }).catch(() => {}),
    page.click('button[type="submit"], input[type="submit"]')
  ]);

  // Additional wait for any redirects
  await page.waitForTimeout(1500);

  // Check login status
  const afterLoginUrl = page.url();
  console.log('After login URL:', afterLoginUrl);

  if (afterLoginUrl.includes('sign_in')) {
    console.log('ERROR: Login failed - still on sign in page');
    await page.screenshot({ path: '/Users/noah-ing/Desktop/knowverse/e2e/screenshots/login_failed.png' });

    // Check for error message
    const errorText = await page.locator('.alert, .flash-alert, [role="alert"]').textContent().catch(() => 'No error visible');
    console.log('Error message:', errorText);
    await browser.close();
    return;
  }

  console.log('Login successful!\n');

  // Check regular admin dashboard first (route is /admin/ not /admin/dashboard)
  console.log('=== CHECKING /admin/ ===');
  await page.goto('http://localhost:3000/admin/');
  await page.waitForLoadState('domcontentloaded');
  await page.waitForTimeout(1000);

  const dashboardUrl = page.url();
  const dashboardTitle = await page.title();
  console.log('URL:', dashboardUrl);
  console.log('Title:', dashboardTitle);

  await page.screenshot({ path: '/Users/noah-ing/Desktop/knowverse/e2e/screenshots/admin_dashboard.png', fullPage: true });
  console.log('Screenshot saved: admin_dashboard.png');

  // Check mission control
  console.log('\n=== CHECKING /admin/mission_control ===');
  await page.goto('http://localhost:3000/admin/mission_control');
  await page.waitForLoadState('domcontentloaded');
  await page.waitForTimeout(1000);

  const mcUrl = page.url();
  const mcTitle = await page.title();
  console.log('URL:', mcUrl);
  console.log('Title:', mcTitle);

  await page.screenshot({ path: '/Users/noah-ing/Desktop/knowverse/e2e/screenshots/mission_control_new.png', fullPage: true });
  console.log('Screenshot saved: mission_control_new.png');

  // Check page structure
  const header = await page.locator('h1').first().textContent().catch(() => 'NOT FOUND');
  console.log('H1 Header:', header);

  const metricValues = await page.locator('.mc-metric-value').allTextContents();
  console.log('Metric Values:', metricValues);

  const panels = await page.locator('.mc-panel').count();
  console.log('Panels:', panels);

  const statusItems = await page.locator('.mc-status-item').count();
  console.log('Status Items:', statusItems);

  const gauges = await page.locator('.mc-gauge').count();
  console.log('Gauges:', gauges);

  const pipelineNodes = await page.locator('.mc-pipeline-node').count();
  console.log('Pipeline Nodes:', pipelineNodes);

  await browser.close();
  console.log('\nDone!');
}

run().catch(console.error);
