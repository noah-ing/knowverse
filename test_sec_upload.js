const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');

(async () => {
  const browser = await chromium.launch({ headless: false });
  const page = await browser.newPage();

  console.log('SEC Files Batch Upload Test\n');

  try {
    // Login
    console.log('1. Logging in...');
    await page.goto('http://localhost:3000/users/sign_in');
    await page.fill('input[name="user[email]"]', 'demo@knowverse.test');
    await page.fill('input[name="user[password]"]', 'testpassword123');
    await page.click('input[type="submit"], button[type="submit"]');
    await page.waitForLoadState('networkidle');
    console.log('   Logged in');

    // Go to upload page
    console.log('2. Navigating to upload page...');
    await page.goto('http://localhost:3000/organizations/1/documents/new');
    await page.waitForLoadState('networkidle');

    // Get SEC files
    const secDir = '/Users/noah-ing/Desktop/knowverse/test_uploads/sec_filings';
    const secFiles = fs.readdirSync(secDir)
      .filter(f => f.endsWith('.txt'))
      .map(f => path.join(secDir, f));

    console.log(`3. Found ${secFiles.length} SEC files:`);
    secFiles.forEach(f => {
      const stats = fs.statSync(f);
      console.log(`   - ${path.basename(f)} (${(stats.size/1024).toFixed(0)} KB)`);
    });

    // Select files
    console.log('4. Selecting files...');
    const fileInput = await page.$('#batch-file-input');
    await fileInput.setInputFiles(secFiles);
    await page.waitForTimeout(1000);

    // Check counts
    const fileCount = await page.$eval('[data-batch-upload-target="fileCount"]', el => el.textContent);
    console.log(`   Selected: ${fileCount} files`);

    // Screenshot before submit
    await page.screenshot({ path: '/tmp/sec_before_submit.png', fullPage: true });

    // Submit
    console.log('5. Submitting (this may take a while for large files)...');
    const submitBtn = await page.$('[data-batch-upload-target="submitButton"]');
    await submitBtn.click();

    // Wait for processing (could take several minutes)
    console.log('   Waiting for upload and processing...');
    await page.waitForURL('**/documents', { timeout: 300000 }); // 5 min timeout
    await page.waitForTimeout(2000);

    // Check result
    console.log('6. Checking result...');
    const flash = await page.$('.notice, .alert, [role="alert"]');
    if (flash) {
      const text = await flash.textContent();
      console.log('   Flash:', text.trim());
    }

    await page.screenshot({ path: '/tmp/sec_after_submit.png', fullPage: true });
    console.log('\nTest completed!');

  } catch (error) {
    console.error('\nError:', error.message);
    await page.screenshot({ path: '/tmp/sec_error.png' });
  }

  await page.waitForTimeout(5000);
  await browser.close();
})();
