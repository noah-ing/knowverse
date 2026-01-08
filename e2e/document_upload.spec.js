// @ts-check
const { test, expect } = require('@playwright/test');
const fs = require('fs');
const path = require('path');

// Create screenshots directory
const screenshotsDir = path.join(__dirname, '..', 'frontend_audit_screenshots', 'v8-003');
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

// Helper: Login as test user
async function loginAsTestUser(page) {
  await page.goto('/users/sign_in');
  await page.waitForLoadState('networkidle');

  await page.fill('input[type="email"], input[name="user[email]"]', 'admin@example.com');
  await page.fill('input[type="password"]', 'password');
  await page.click('button[type="submit"], input[type="submit"]');
  await page.waitForLoadState('networkidle');
  await page.waitForTimeout(2000);

  // Verify login succeeded
  const url = page.url();
  if (url.includes('sign_in')) {
    throw new Error('Login failed - still on sign_in page');
  }
  console.log('✓ Logged in as test user');
}

test.describe('V8-003: Document Upload and Management', () => {

  // Test 1: Navigate to documents section after login
  test('1. navigate to documents section', async ({ page }) => {
    await loginAsTestUser(page);

    // Navigate to documents
    await page.goto('/documents');
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(1000);

    const ssPath = path.join(screenshotsDir, '01_documents_page.png');
    await page.screenshot({ path: ssPath, fullPage: true });
    logScreenshot('01_documents_page.png', 'Documents page after login');

    const url = page.url();
    console.log(`Documents page URL: ${url}`);

    // Check page loaded successfully
    const title = await page.title();
    console.log(`Page title: ${title}`);

    // Look for documents heading or section
    const heading = page.locator('h1, h2');
    if (await heading.count() > 0) {
      const headingText = await heading.first().textContent();
      console.log(`Main heading: ${headingText}`);
    }

    // Check for document list or empty state
    const documentList = page.locator('[data-controller*="document"], .document-list, .documents, table');
    const emptyState = page.locator('.empty-state, :text("No documents"), :text("no documents"), :text("Upload")');

    if (await documentList.count() > 0) {
      console.log('✓ Document list/table found');
    } else if (await emptyState.count() > 0) {
      console.log('✓ Empty state message found');
    } else {
      logIssue('LOW', 'DOC-001', 'Unclear documents state', 'Documents page loaded but unclear if list or empty state');
    }
  });

  // Test 2: Test file upload UI - check for drag-drop and file picker
  test('2. file upload UI elements', async ({ page }) => {
    await loginAsTestUser(page);
    await page.goto('/documents');
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(1000);

    // Look for upload button or area
    const uploadButton = page.locator('button:has-text("upload"), button:has-text("Upload"), a:has-text("upload"), a:has-text("Upload"), [data-action*="upload"]');
    const dropZone = page.locator('[data-dropzone], .dropzone, .drop-zone, .upload-area, [data-controller*="upload"], [data-controller*="dropzone"]');
    const fileInput = page.locator('input[type="file"]');

    // Check for upload button
    if (await uploadButton.count() > 0) {
      console.log('✓ Upload button found');

      // Click to open upload modal/section
      await uploadButton.first().click();
      await page.waitForTimeout(1000);

      const ssPath = path.join(screenshotsDir, '02_upload_modal.png');
      await page.screenshot({ path: ssPath, fullPage: true });
      logScreenshot('02_upload_modal.png', 'Upload modal/section opened');
    } else {
      logIssue('HIGH', 'DOC-002', 'No upload button', 'Could not find upload button on documents page');
    }

    // Check for drag-drop zone
    const dragDropArea = await dropZone.count();
    if (dragDropArea > 0) {
      console.log('✓ Drag-drop zone found');

      // Check for visual indicators
      const dropText = page.locator(':text("drag"), :text("Drag"), :text("drop"), :text("Drop")');
      if (await dropText.count() > 0) {
        console.log('✓ Drag-drop instructions visible');
      } else {
        logIssue('LOW', 'DOC-003', 'No drag-drop instructions', 'Drag-drop zone exists but no clear instructions');
      }
    } else {
      console.log('⚠ No dedicated drag-drop zone found (may use standard file input)');
    }

    // Check for file input
    if (await fileInput.count() > 0) {
      console.log('✓ File input element found');

      // Check accepted file types
      const accept = await fileInput.getAttribute('accept');
      if (accept) {
        console.log(`  Accepted file types: ${accept}`);
      } else {
        logIssue('LOW', 'DOC-004', 'No file type restrictions', 'File input has no accept attribute');
      }

      // Check multiple file upload
      const multiple = await fileInput.getAttribute('multiple');
      console.log(`  Multiple files: ${multiple !== null ? 'Yes' : 'No'}`);
    } else {
      logIssue('MEDIUM', 'DOC-005', 'No file input', 'Could not find file input element');
    }

    const ssPath = path.join(screenshotsDir, '03_upload_ui_elements.png');
    await page.screenshot({ path: ssPath, fullPage: true });
    logScreenshot('03_upload_ui_elements.png', 'Upload UI elements');
  });

  // Test 3: Test file upload with a test file
  test('3. file upload process', async ({ page }) => {
    await loginAsTestUser(page);
    await page.goto('/documents');
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(1000);

    // Create a test file
    const testFilePath = path.join(screenshotsDir, 'test_document.txt');
    fs.writeFileSync(testFilePath, 'This is a test document for KnowVerse audit.\n\nIt contains sample text to test the document upload functionality.');

    // Try to trigger upload
    const uploadButton = page.locator('button:has-text("upload"), button:has-text("Upload"), a:has-text("upload"), a:has-text("Upload"), [data-action*="upload"]');

    if (await uploadButton.count() > 0) {
      await uploadButton.first().click();
      await page.waitForTimeout(1000);
    }

    // Find and use file input
    const fileInput = page.locator('input[type="file"]');

    if (await fileInput.count() > 0) {
      // Make input visible if hidden
      await fileInput.evaluate(input => {
        input.style.display = 'block';
        input.style.visibility = 'visible';
        input.style.opacity = '1';
      });

      // Upload file
      await fileInput.setInputFiles(testFilePath);
      console.log('✓ File selected for upload');

      const ssPath1 = path.join(screenshotsDir, '04_file_selected.png');
      await page.screenshot({ path: ssPath1, fullPage: true });
      logScreenshot('04_file_selected.png', 'File selected for upload');

      // Wait for upload to process
      await page.waitForTimeout(3000);

      // Check for progress indicator
      const progressIndicator = page.locator('.progress, [role="progressbar"], .uploading, .upload-progress, [data-controller*="progress"]');
      if (await progressIndicator.count() > 0) {
        console.log('✓ Upload progress indicator found');
      } else {
        console.log('⚠ No visible upload progress indicator');
      }

      // Check for upload button/submit
      const submitButton = page.locator('button:has-text("submit"), button:has-text("Submit"), button:has-text("save"), button:has-text("Save"), button[type="submit"]');
      if (await submitButton.count() > 0) {
        await submitButton.first().click();
        await page.waitForTimeout(2000);
        console.log('✓ Upload submit clicked');
      }

      const ssPath2 = path.join(screenshotsDir, '05_upload_progress.png');
      await page.screenshot({ path: ssPath2, fullPage: true });
      logScreenshot('05_upload_progress.png', 'Upload in progress');

      // Wait for completion and check result
      await page.waitForTimeout(5000);

      const ssPath3 = path.join(screenshotsDir, '06_upload_result.png');
      await page.screenshot({ path: ssPath3, fullPage: true });
      logScreenshot('06_upload_result.png', 'Upload result');

      // Check for success/error messages
      const successMsg = page.locator('.alert-success, .flash-success, :text("uploaded"), :text("success")');
      const errorMsg = page.locator('.alert-danger, .alert-error, .error, :text("failed"), :text("error")');

      if (await successMsg.count() > 0) {
        const msg = await successMsg.first().textContent();
        console.log(`✓ Upload success: ${msg?.trim()}`);
      } else if (await errorMsg.count() > 0) {
        const msg = await errorMsg.first().textContent();
        console.log(`⚠ Upload error: ${msg?.trim()}`);
        logIssue('MEDIUM', 'DOC-006', 'Upload error', `File upload failed: ${msg?.trim()}`);
      } else {
        console.log('⚠ No clear success/error feedback after upload');
      }
    } else {
      logIssue('HIGH', 'DOC-007', 'Cannot upload file', 'No file input available for upload');
    }

    // Cleanup test file
    try {
      fs.unlinkSync(testFilePath);
    } catch (e) {
      // ignore cleanup errors
    }
  });

  // Test 4: Verify upload progress indicators
  test('4. upload progress indicators', async ({ page }) => {
    await loginAsTestUser(page);
    await page.goto('/documents');
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(1000);

    // Look for any loading/progress UI patterns
    const progressElements = page.locator('.progress, [role="progressbar"], .spinner, .loading, [data-controller*="progress"], .animate-spin, .processing');

    if (await progressElements.count() > 0) {
      console.log('✓ Progress UI elements available in DOM');
    } else {
      console.log('ℹ No visible progress elements (may appear during upload)');
    }

    // Check for Turbo stream processing indicators
    const turboFrame = page.locator('turbo-frame');
    if (await turboFrame.count() > 0) {
      console.log(`✓ ${await turboFrame.count()} Turbo frames found (supports streaming updates)`);
    }

    // Check for Stimulus controllers related to progress
    const progressControllers = page.locator('[data-controller*="upload"], [data-controller*="progress"], [data-controller*="file"]');
    if (await progressControllers.count() > 0) {
      console.log('✓ Stimulus upload/progress controllers found');
    }

    const ssPath = path.join(screenshotsDir, '07_progress_ui.png');
    await page.screenshot({ path: ssPath, fullPage: true });
    logScreenshot('07_progress_ui.png', 'Progress UI patterns');
  });

  // Test 5: Document list view
  test('5. document list view and layout', async ({ page }) => {
    await loginAsTestUser(page);
    await page.goto('/documents');
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(1000);

    const ssPath = path.join(screenshotsDir, '08_document_list.png');
    await page.screenshot({ path: ssPath, fullPage: true });
    logScreenshot('08_document_list.png', 'Document list view');

    // Check for list/grid/table layout
    const tableView = page.locator('table, [role="table"]');
    const gridView = page.locator('.grid, [data-view="grid"]');
    const listView = page.locator('.list, ul.documents, [data-view="list"]');

    if (await tableView.count() > 0) {
      console.log('✓ Table layout found');

      // Check table headers
      const headers = page.locator('th, [role="columnheader"]');
      const headerCount = await headers.count();
      console.log(`  Table headers: ${headerCount}`);

      // Get header names
      const headerTexts = [];
      for (let i = 0; i < Math.min(headerCount, 10); i++) {
        const text = await headers.nth(i).textContent();
        if (text) headerTexts.push(text.trim());
      }
      console.log(`  Columns: ${headerTexts.join(', ')}`);
    } else if (await gridView.count() > 0 || await listView.count() > 0) {
      console.log('✓ Grid/List layout found');
    } else {
      console.log('⚠ No standard list/table/grid layout detected');
    }

    // Check for document items
    const docItems = page.locator('.document, .document-item, tr:has(td), [data-document-id], .doc-card');
    const itemCount = await docItems.count();
    console.log(`  Document items visible: ${itemCount}`);

    if (itemCount > 0) {
      // Check for document info (title, date, status)
      const firstDoc = docItems.first();
      const docText = await firstDoc.textContent();
      console.log(`  First document preview: ${docText?.substring(0, 100)}...`);
    }

    // Check for view toggle (list/grid)
    const viewToggle = page.locator('[data-action*="view"], .view-toggle, button:has-text("grid"), button:has-text("list")');
    if (await viewToggle.count() > 0) {
      console.log('✓ View toggle found');
    }
  });

  // Test 6: Document search functionality
  test('6. document search', async ({ page }) => {
    await loginAsTestUser(page);
    await page.goto('/documents');
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(1000);

    // Find search input
    const searchInput = page.locator('input[type="search"], input[name*="search"], input[name*="query"], input[placeholder*="search"], input[placeholder*="Search"]');

    if (await searchInput.count() > 0) {
      console.log('✓ Search input found');

      // Try searching
      await searchInput.first().fill('test');

      // Check for search button or auto-search
      const searchButton = page.locator('button[type="submit"]:has-text("search"), button:has-text("Search")');
      if (await searchButton.count() > 0) {
        await searchButton.first().click();
      } else {
        // May be auto-search, press Enter
        await searchInput.first().press('Enter');
      }

      await page.waitForTimeout(2000);

      const ssPath = path.join(screenshotsDir, '09_search_results.png');
      await page.screenshot({ path: ssPath, fullPage: true });
      logScreenshot('09_search_results.png', 'Document search results');

      // Check URL for search params
      const url = page.url();
      if (url.includes('search') || url.includes('query') || url.includes('q=')) {
        console.log('✓ Search params reflected in URL');
      }

      // Check for results or no-results message
      const results = page.locator('.document, .search-result, tr:has(td)');
      const noResults = page.locator(':text("No results"), :text("no documents"), :text("not found")');

      if (await results.count() > 0) {
        console.log(`✓ ${await results.count()} search results shown`);
      } else if (await noResults.count() > 0) {
        console.log('✓ No results message shown');
      }
    } else {
      logIssue('MEDIUM', 'DOC-008', 'No document search', 'Documents page missing search functionality');
    }
  });

  // Test 7: Document filtering
  test('7. document filtering', async ({ page }) => {
    await loginAsTestUser(page);
    await page.goto('/documents');
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(1000);

    // Look for filter controls
    const filterDropdown = page.locator('select[name*="filter"], select[name*="status"], select[name*="type"], [data-controller*="filter"]');
    const filterButtons = page.locator('button:has-text("filter"), button:has-text("Filter"), [data-filter]');
    const filterTabs = page.locator('[role="tablist"], .tabs, .filter-tabs');

    if (await filterDropdown.count() > 0) {
      console.log('✓ Filter dropdown found');

      // Get filter options
      const options = await filterDropdown.first().locator('option').allTextContents();
      console.log(`  Filter options: ${options.join(', ')}`);

      // Try selecting a filter
      if (options.length > 1) {
        await filterDropdown.first().selectOption({ index: 1 });
        await page.waitForTimeout(1500);

        const ssPath = path.join(screenshotsDir, '10_filtered_results.png');
        await page.screenshot({ path: ssPath, fullPage: true });
        logScreenshot('10_filtered_results.png', 'Filtered document results');
      }
    } else if (await filterButtons.count() > 0) {
      console.log('✓ Filter buttons found');
    } else if (await filterTabs.count() > 0) {
      console.log('✓ Filter tabs found');
    } else {
      logIssue('LOW', 'DOC-009', 'Limited filtering', 'Documents page has limited or no filtering options');
    }

    // Check for sort controls
    const sortControls = page.locator('select[name*="sort"], [data-sort], th[data-action*="sort"], .sortable');
    if (await sortControls.count() > 0) {
      console.log('✓ Sort controls found');
    } else {
      console.log('⚠ No obvious sort controls');
    }
  });

  // Test 8: Document deletion
  test('8. document deletion flow', async ({ page }) => {
    await loginAsTestUser(page);
    await page.goto('/documents');
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(1000);

    // Find delete button on a document
    const deleteButton = page.locator('button:has-text("delete"), button:has-text("Delete"), a:has-text("delete"), a:has-text("Delete"), [data-action*="delete"], .delete-btn, [data-turbo-method="delete"]');

    if (await deleteButton.count() > 0) {
      console.log(`✓ ${await deleteButton.count()} delete button(s) found`);

      const ssPath1 = path.join(screenshotsDir, '11_delete_button.png');
      await page.screenshot({ path: ssPath1, fullPage: true });
      logScreenshot('11_delete_button.png', 'Document delete buttons');

      // Check if delete requires confirmation
      // Set up dialog handler
      let dialogAppeared = false;
      let dialogMessage = '';
      page.on('dialog', async dialog => {
        dialogAppeared = true;
        dialogMessage = dialog.message();
        console.log(`✓ Confirmation dialog: ${dialogMessage}`);
        await dialog.dismiss(); // Don't actually delete
      });

      // Click first delete button
      await deleteButton.first().click();
      await page.waitForTimeout(1500);

      // Check for modal confirmation instead of dialog
      const confirmModal = page.locator('[data-controller*="modal"], .modal, [role="dialog"], .confirmation-modal');
      if (await confirmModal.count() > 0) {
        console.log('✓ Confirmation modal appeared');
        dialogAppeared = true;

        const ssPath2 = path.join(screenshotsDir, '12_delete_confirmation.png');
        await page.screenshot({ path: ssPath2, fullPage: true });
        logScreenshot('12_delete_confirmation.png', 'Delete confirmation dialog');

        // Cancel deletion
        const cancelBtn = page.locator('button:has-text("cancel"), button:has-text("Cancel"), button:has-text("No")');
        if (await cancelBtn.count() > 0) {
          await cancelBtn.first().click();
          await page.waitForTimeout(500);
        }
      }

      if (!dialogAppeared) {
        logIssue('HIGH', 'DOC-010', 'No delete confirmation', 'Document deletion has no confirmation dialog (destructive action)');
      }
    } else {
      console.log('⚠ No delete buttons visible (may need to select documents first)');

      // Check for bulk selection
      const checkbox = page.locator('input[type="checkbox"]');
      if (await checkbox.count() > 0) {
        console.log('  Checkboxes found - bulk actions may require selection');
      }
    }
  });

  // Test 9: Document detail view
  test('9. document detail view', async ({ page }) => {
    await loginAsTestUser(page);
    await page.goto('/documents');
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(1000);

    // Try to open a document
    const docLink = page.locator('a[href*="/documents/"], .document-title a, tr a');

    if (await docLink.count() > 0) {
      await docLink.first().click();
      await page.waitForLoadState('networkidle');
      await page.waitForTimeout(1500);

      const ssPath = path.join(screenshotsDir, '13_document_detail.png');
      await page.screenshot({ path: ssPath, fullPage: true });
      logScreenshot('13_document_detail.png', 'Document detail view');

      const url = page.url();
      console.log(`Document detail URL: ${url}`);

      // Check for document details
      const docTitle = page.locator('h1, h2, .document-title');
      if (await docTitle.count() > 0) {
        const title = await docTitle.first().textContent();
        console.log(`✓ Document title: ${title?.trim()}`);
      }

      // Check for metadata
      const metadata = page.locator('.metadata, .document-info, .details');
      if (await metadata.count() > 0) {
        console.log('✓ Document metadata section found');
      }

      // Check for content preview
      const content = page.locator('.content, .document-content, .preview');
      if (await content.count() > 0) {
        console.log('✓ Document content/preview section found');
      }

      // Check for action buttons
      const editBtn = page.locator('button:has-text("edit"), a:has-text("Edit")');
      const downloadBtn = page.locator('button:has-text("download"), a:has-text("Download")');

      if (await editBtn.count() > 0) console.log('✓ Edit action available');
      if (await downloadBtn.count() > 0) console.log('✓ Download action available');
    } else {
      console.log('⚠ No document links found to test detail view');
    }
  });

  // Test 10: Pagination
  test('10. pagination', async ({ page }) => {
    await loginAsTestUser(page);
    await page.goto('/documents');
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(1000);

    // Check for pagination
    const pagination = page.locator('.pagination, nav[aria-label*="pagination"], [data-controller*="pagination"], .pagy');
    const pageLinks = page.locator('a[href*="page="], .page-link, .pagination a');
    const loadMore = page.locator('button:has-text("more"), button:has-text("Load"), a:has-text("more")');

    if (await pagination.count() > 0) {
      console.log('✓ Pagination controls found');

      const ssPath = path.join(screenshotsDir, '14_pagination.png');
      await page.screenshot({ path: ssPath, fullPage: true });
      logScreenshot('14_pagination.png', 'Pagination controls');

      // Try clicking next page if available
      const nextBtn = page.locator('a:has-text("Next"), a:has-text("next"), .next a, a[rel="next"]');
      if (await nextBtn.count() > 0) {
        await nextBtn.first().click();
        await page.waitForLoadState('networkidle');
        await page.waitForTimeout(1000);

        const ssPath2 = path.join(screenshotsDir, '15_page_2.png');
        await page.screenshot({ path: ssPath2, fullPage: true });
        logScreenshot('15_page_2.png', 'Second page of documents');

        // Check URL includes page param
        const url = page.url();
        if (url.includes('page=')) {
          console.log('✓ Page parameter in URL');
        }
      }
    } else if (await loadMore.count() > 0) {
      console.log('✓ Load more button found (infinite scroll pattern)');
    } else {
      console.log('ℹ No pagination controls (may have fewer documents)');
    }
  });
});

// After all tests, write summary
test.afterAll(async () => {
  console.log('\n' + '='.repeat(60));
  console.log('V8-003 DOCUMENT UPLOAD AND MANAGEMENT AUDIT SUMMARY');
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
  const resultsPath = path.join(screenshotsDir, 'document_audit_results.json');
  fs.writeFileSync(resultsPath, JSON.stringify({
    screenshots,
    issues: auditIssues,
    timestamp: new Date().toISOString()
  }, null, 2));
  console.log(`\n📁 Results saved to: ${resultsPath}`);
});
