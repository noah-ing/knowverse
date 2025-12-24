const { chromium } = require('playwright');

(async () => {
  const browser = await chromium.launch({ headless: false });
  const page = await browser.newPage();

  console.log('Bulk Features Test\n');

  try {
    // Login
    console.log('1. Logging in...');
    await page.goto('http://localhost:3000/users/sign_in');
    await page.fill('input[name="user[email]"]', 'demo@knowverse.test');
    await page.fill('input[name="user[password]"]', 'testpassword123');
    await page.click('input[type="submit"], button[type="submit"]');
    await page.waitForLoadState('networkidle');
    console.log('   Logged in');

    // Go to documents page
    console.log('2. Going to documents page...');
    await page.goto('http://localhost:3000/organizations/1/documents');
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(1000);

    // Take screenshot showing status bar
    await page.screenshot({ path: '/tmp/docs_status_bar.png', fullPage: true });
    console.log('   Screenshot saved: /tmp/docs_status_bar.png');

    // Check for processing status bar
    const statusBar = await page.$('.animate-spin');
    if (statusBar) {
      console.log('3. Processing status bar found (spinning indicator)');
    } else {
      console.log('3. No processing status bar (all documents may be complete)');
    }

    // Check for select all checkbox
    const selectAll = await page.$('[data-bulk-select-target="selectAll"]');
    if (selectAll) {
      console.log('4. Select All checkbox found');
    }

    // Try clicking a document checkbox
    const checkboxes = await page.$$('[data-bulk-select-target="checkbox"]');
    console.log(`5. Found ${checkboxes.length} document checkboxes`);

    if (checkboxes.length >= 3) {
      // Select first 3 documents
      await checkboxes[0].click();
      await checkboxes[1].click();
      await checkboxes[2].click();
      await page.waitForTimeout(500);

      // Check if bulk actions appeared
      const bulkActions = await page.$('[data-bulk-select-target="bulkActions"]:not(.hidden)');
      if (bulkActions) {
        console.log('6. Bulk actions bar appeared after selecting documents');
        const selectedCount = await page.$eval('[data-bulk-select-target="selectedCount"]', el => el.textContent);
        console.log(`   Selected count shows: ${selectedCount}`);
      }

      await page.screenshot({ path: '/tmp/docs_bulk_select.png', fullPage: true });
      console.log('   Screenshot saved: /tmp/docs_bulk_select.png');
    }

    console.log('\nTest completed successfully!');

  } catch (error) {
    console.error('\nError:', error.message);
    await page.screenshot({ path: '/tmp/docs_error.png' });
  }

  await page.waitForTimeout(5000);
  await browser.close();
})();
