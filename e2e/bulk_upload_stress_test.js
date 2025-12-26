// @ts-check
const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');

const TEST_FILES_DIR = '/Volumes/monster/knowverse/test_documents';

// Credentials - SET VIA ENV VARS
const CREDENTIALS = {
  email: process.env.TEST_EMAIL || 'your-email@example.com',
  password: process.env.TEST_PASSWORD || 'your-password'
};

async function run() {
  console.log('🚀 Starting bulk upload stress test...\n');

  // Get all test files (exclude mac metadata files)
  const allFiles = fs.readdirSync(TEST_FILES_DIR)
    .filter(f => !f.startsWith('._') && !f.endsWith('.zip') && !f.endsWith('.png'))
    .map(f => path.join(TEST_FILES_DIR, f));

  console.log(`📁 Found ${allFiles.length} test files:\n`);

  // Group by extension
  const byType = {};
  allFiles.forEach(f => {
    const ext = path.extname(f).toLowerCase() || 'no-ext';
    byType[ext] = (byType[ext] || 0) + 1;
  });
  Object.entries(byType).forEach(([ext, count]) => {
    console.log(`   ${ext}: ${count} files`);
  });
  console.log('');

  const browser = await chromium.launch({
    headless: false,
    slowMo: 200
  });

  const page = await browser.newPage();

  try {
    // 1. Login
    console.log('🔐 Logging in...');
    await page.goto('http://localhost:3000/users/sign_in');
    await page.waitForLoadState('networkidle');

    await page.locator('input[type="email"], input[name="user[email]"]').first().fill(CREDENTIALS.email);
    await page.locator('input[type="password"], input[name="user[password]"]').first().fill(CREDENTIALS.password);
    await page.locator('button[type="submit"], input[type="submit"]').first().click();

    await page.waitForLoadState('networkidle');
    await page.waitForFunction(() => !window.location.href.includes('sign_in'), { timeout: 20000 });
    console.log('✅ Logged in successfully\n');

    // 2. Navigate to Documents
    console.log('📂 Navigating to documents...');
    await page.goto('http://localhost:3000/organizations');
    await page.waitForLoadState('networkidle');

    await page.locator('a[href*="/organizations/"]').first().click();
    await page.waitForLoadState('networkidle');

    await page.locator('a:has-text("Documents")').first().click();
    await page.waitForLoadState('networkidle');

    // Get current URL for the organization
    const currentUrl = page.url();
    const orgMatch = currentUrl.match(/\/organizations\/(\d+)/);
    const orgId = orgMatch ? orgMatch[1] : '1';
    console.log(`✅ On documents page (org: ${orgId})\n`);

    // 3. Upload files in batches
    const BATCH_SIZE = 5;
    let uploaded = 0;
    let failed = 0;

    for (let i = 0; i < allFiles.length; i += BATCH_SIZE) {
      const batch = allFiles.slice(i, i + BATCH_SIZE);
      const batchNum = Math.floor(i / BATCH_SIZE) + 1;
      const totalBatches = Math.ceil(allFiles.length / BATCH_SIZE);

      console.log(`\n📦 Uploading batch ${batchNum}/${totalBatches} (${batch.length} files)...`);
      batch.forEach(f => console.log(`   - ${path.basename(f)}`));

      try {
        // Show the upload form by removing hidden class via JavaScript
        await page.evaluate(() => {
          const form = document.getElementById('upload-form');
          if (form) {
            form.classList.remove('hidden');
          }
        });
        await page.waitForTimeout(500);

        // Set files on the file input
        const fileInput = page.locator('#file-upload');
        await fileInput.setInputFiles(batch);
        await page.waitForTimeout(1000);

        // Click the submit button using JavaScript to bypass visibility issues
        await page.evaluate(() => {
          const form = document.getElementById('file-upload-form');
          if (form) {
            form.submit();
          }
        });

        // Wait for form submission and page reload
        await page.waitForLoadState('networkidle');
        await page.waitForTimeout(2000);

        uploaded += batch.length;
        console.log(`   ✅ Batch ${batchNum} submitted`);

      } catch (err) {
        console.log(`   ❌ Batch ${batchNum} failed: ${err.message}`);
        failed += batch.length;

        // Try to recover by going back to documents page
        await page.goto(`http://localhost:3000/organizations/${orgId}/documents`);
        await page.waitForLoadState('networkidle');
      }
    }

    console.log(`\n📊 Upload Summary:`);
    console.log(`   ✅ Submitted: ${uploaded} files`);
    console.log(`   ❌ Failed: ${failed} files`);

    // 4. Refresh and check document count
    console.log('\n🔄 Refreshing page to check uploads...');
    await page.reload();
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(2000);

    // 5. Take screenshot
    const screenshotPath = '/Volumes/monster/knowverse/test_documents/upload_result.png';
    await page.screenshot({ path: screenshotPath, fullPage: true });
    console.log(`📸 Screenshot saved: ${screenshotPath}`);

    // 6. Keep browser open for manual inspection
    console.log('\n✨ Test complete! Browser will stay open for 3 minutes for inspection.');
    console.log('   Check the documents list to verify files were uploaded.\n');

    await page.waitForTimeout(180000);

  } catch (error) {
    console.error('❌ Test failed:', error.message);
    await page.screenshot({ path: '/Volumes/monster/knowverse/test_documents/error.png' });
  } finally {
    await browser.close();
    console.log('🏁 Browser closed.');
  }
}

run().catch(console.error);
