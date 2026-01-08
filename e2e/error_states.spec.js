// @ts-check
const { test, expect } = require('@playwright/test');
const fs = require('fs');
const path = require('path');

// Create screenshots directory
const screenshotsDir = path.join(__dirname, '..', 'frontend_audit_screenshots', 'v8-007');
if (!fs.existsSync(screenshotsDir)) {
  fs.mkdirSync(screenshotsDir, { recursive: true });
}

// Collect issues during tests
let auditIssues = [];
let screenshots = [];
let positiveFindings = [];

function logIssue(severity, id, title, description, screenshot = null) {
  auditIssues.push({ severity, id, title, description, screenshot });
  console.log(`[${severity}] ${id}: ${title}`);
}

function logPositive(finding) {
  positiveFindings.push(finding);
  console.log(`✓ ${finding}`);
}

function logScreenshot(filename, description) {
  screenshots.push({ filename, description });
  console.log(`📸 Screenshot: ${filename}`);
}

// Helper to login before tests
async function login(page) {
  await page.goto('/users/sign_in');
  await page.waitForLoadState('networkidle');
  await page.fill('input[type="email"], input[name="user[email]"]', 'admin@example.com');
  await page.fill('input[type="password"]', 'password');
  await page.click('button[type="submit"], input[type="submit"]');
  await page.waitForLoadState('networkidle');
  await page.waitForTimeout(1500);
}

// Helper to dismiss cookie banner
async function dismissCookieBanner(page) {
  const acceptAll = page.locator('button:has-text("Accept All")');
  if (await acceptAll.count() > 0 && await acceptAll.isVisible()) {
    await acceptAll.click();
    await page.waitForTimeout(500);
    console.log('✓ Cookie banner dismissed');
  }
}

test.describe('V8-007: Error States and Edge Cases', () => {

  // Test 1: 404 page appearance
  test('1. 404 page appearance', async ({ page }) => {
    // Navigate to a non-existent page
    await page.goto('/nonexistent-page-12345');
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(1000);

    const ssPath = path.join(screenshotsDir, '01_404_page.png');
    await page.screenshot({ path: ssPath, fullPage: true });
    logScreenshot('01_404_page.png', '404 error page');

    // Check page title or heading for 404
    const pageContent = await page.content();
    const title = await page.title();

    console.log(`Page title: ${title}`);
    console.log(`URL: ${page.url()}`);

    // Check for user-friendly 404 content
    const has404Heading = await page.locator('h1:has-text("404"), h1:has-text("Not Found"), h2:has-text("404")').count() > 0;
    const hasErrorMessage = await page.locator('text=/page.*not found|cannot be found|doesn\'t exist/i').count() > 0;
    const hasHomeLink = await page.locator('a:has-text("Home"), a:has-text("Go back"), a:has-text("Return")').count() > 0;

    // Check for debug information (bad)
    const hasDebugInfo = pageContent.includes('ActionController') ||
                         pageContent.includes('Rails.root') ||
                         pageContent.includes('RAILS_ENV') ||
                         pageContent.includes('stack trace') ||
                         pageContent.includes('exception');

    if (has404Heading) {
      logPositive('404 page has clear heading');
    } else {
      logIssue('MEDIUM', 'FE-023', 'No clear 404 heading', 'The 404 page lacks a clear "Page Not Found" heading');
    }

    if (hasErrorMessage) {
      logPositive('404 page has helpful error message');
    }

    if (hasHomeLink) {
      logPositive('404 page has link back to home');
    } else {
      logIssue('MEDIUM', 'FE-024', 'No navigation from 404', '404 page lacks clear navigation back to main site');
    }

    if (hasDebugInfo) {
      logIssue('CRITICAL', 'FE-001', '404 page exposes debug info',
        'The 404 page shows Rails debug/exception information in production mode',
        '01_404_page.png');
    } else {
      logPositive('404 page does not expose debug information');
    }

    // Try another 404 route with different format
    await page.goto('/api/nonexistent');
    await page.waitForLoadState('networkidle');

    const ssPath2 = path.join(screenshotsDir, '02_404_api.png');
    await page.screenshot({ path: ssPath2, fullPage: true });
    logScreenshot('02_404_api.png', 'API 404 response');

    const responseContent = await page.content();
    console.log(`API 404 response type: ${responseContent.includes('json') ? 'JSON' : 'HTML'}`);
  });

  // Test 2: Form validation error messages - Registration
  test('2. form validation - registration', async ({ page }) => {
    await page.goto('/users/sign_up');
    await page.waitForLoadState('networkidle');
    await dismissCookieBanner(page);
    await page.waitForTimeout(500);

    const ssPath = path.join(screenshotsDir, '03_registration_empty.png');
    await page.screenshot({ path: ssPath, fullPage: true });
    logScreenshot('03_registration_empty.png', 'Registration form empty state');

    // Submit empty form - use specific selector to avoid cookie banner button
    const submitButton = page.locator('input[type="submit"][value*="Create"], button:has-text("Sign up"), input[value*="Sign up"]').first();
    await submitButton.click();
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(1000);

    const ssPath2 = path.join(screenshotsDir, '04_registration_validation.png');
    await page.screenshot({ path: ssPath2, fullPage: true });
    logScreenshot('04_registration_validation.png', 'Registration form validation errors');

    // Check for validation errors
    const errorMessages = page.locator('.error, .invalid-feedback, [class*="error"], #error_explanation, .alert-danger, .field_with_errors');
    const errorCount = await errorMessages.count();

    if (errorCount > 0) {
      logPositive(`Form validation: ${errorCount} error messages displayed`);
      const errorText = await errorMessages.first().textContent();
      console.log(`  Sample error: "${errorText?.slice(0, 100)}"`);
    } else {
      // Check for HTML5 validation
      const invalidFields = await page.evaluate(() => {
        const inputs = document.querySelectorAll('input:invalid');
        return inputs.length;
      });

      if (invalidFields > 0) {
        logPositive(`HTML5 validation: ${invalidFields} fields marked invalid`);
      } else {
        logIssue('HIGH', 'FE-025', 'No registration validation feedback',
          'No visible error messages when submitting empty registration form');
      }
    }

    // Test invalid email format
    await page.fill('input[name="user[email]"], input[type="email"]', 'invalid-email');
    await page.fill('input[name="user[password]"], input[type="password"]', 'pass');
    await submitButton.click();
    await page.waitForTimeout(1000);

    const ssPath3 = path.join(screenshotsDir, '05_registration_invalid_email.png');
    await page.screenshot({ path: ssPath3, fullPage: true });
    logScreenshot('05_registration_invalid_email.png', 'Invalid email validation');

    // Test password too short
    await page.fill('input[name="user[email]"], input[type="email"]', 'test@example.com');
    await page.fill('input[name="user[password]"], input[type="password"]', 'abc');
    await submitButton.click();
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(1000);

    const ssPath4 = path.join(screenshotsDir, '06_registration_short_password.png');
    await page.screenshot({ path: ssPath4, fullPage: true });
    logScreenshot('06_registration_short_password.png', 'Short password validation');

    const passwordError = await page.locator('text=/too short|minimum|at least 6/i').count();
    if (passwordError > 0) {
      logPositive('Password length validation message displayed');
    }
  });

  // Test 3: Form validation - Login
  test('3. form validation - login', async ({ page }) => {
    await page.goto('/users/sign_in');
    await page.waitForLoadState('networkidle');
    await dismissCookieBanner(page);
    await page.waitForTimeout(500);

    // Test with invalid credentials
    await page.fill('input[name="user[email]"], input[type="email"]', 'nonexistent@example.com');
    await page.fill('input[name="user[password]"], input[type="password"]', 'wrongpassword123');

    const ssPath = path.join(screenshotsDir, '07_login_before_submit.png');
    await page.screenshot({ path: ssPath, fullPage: true });
    logScreenshot('07_login_before_submit.png', 'Login form before invalid submit');

    // Use specific selector to avoid cookie banner button
    await page.locator('input[type="submit"][value*="Sign in"], button:has-text("Sign in")').first().click();
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(1500);

    const ssPath2 = path.join(screenshotsDir, '08_login_error.png');
    await page.screenshot({ path: ssPath2, fullPage: true });
    logScreenshot('08_login_error.png', 'Login error state');

    // Check for error message
    const errorMessage = page.locator('.alert, .flash, [class*="error"], [class*="danger"], .notice');
    const flashMessage = page.locator('[class*="flash"], #flash-messages, .flash-message');

    const hasError = await errorMessage.count() > 0 || await flashMessage.count() > 0;

    if (hasError) {
      const errorText = await errorMessage.first().textContent().catch(() => '');
      const flashText = await flashMessage.first().textContent().catch(() => '');
      console.log(`Error message: "${errorText || flashText}"`);
      logPositive('Login error message displayed');
    } else {
      logIssue('HIGH', 'FE-002', 'No login error feedback',
        'No visible error message when login fails with invalid credentials',
        '08_login_error.png');
    }

    // Check if URL changed or stayed on login
    const currentUrl = page.url();
    console.log(`After failed login, URL: ${currentUrl}`);

    if (currentUrl.includes('sign_in')) {
      logPositive('User stays on login page after failed attempt');
    }
  });

  // Test 4: Empty states - no documents
  test('4. empty state - no documents', async ({ page }) => {
    await login(page);
    await dismissCookieBanner(page);

    // Navigate to documents
    await page.goto('/documents');
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(1000);

    const ssPath = path.join(screenshotsDir, '09_documents_state.png');
    await page.screenshot({ path: ssPath, fullPage: true });
    logScreenshot('09_documents_state.png', 'Documents page state');

    // Check for empty state message
    const emptyMessage = page.locator('text=/no documents|empty|upload.*first|get started/i');
    const hasEmptyState = await emptyMessage.count() > 0;

    if (hasEmptyState) {
      logPositive('Documents page shows clear empty state message');
    }

    // Check for helpful CTA in empty state
    const uploadCTA = page.locator('a:has-text("Upload"), button:has-text("Upload"), a[href*="upload"], a[href*="new"]');
    if (await uploadCTA.count() > 0) {
      logPositive('Empty state has upload CTA');
    }

    // Search for non-existent document
    const searchInput = page.locator('input[type="search"], input[placeholder*="search"], input[name*="search"], input[name="q"]');
    if (await searchInput.count() > 0) {
      await searchInput.fill('nonexistent-document-xyz-12345');

      // Submit search
      const searchForm = page.locator('form[action*="search"], form:has(input[name="q"])');
      if (await searchForm.count() > 0) {
        await searchForm.first().evaluate(form => form.submit());
      } else {
        await searchInput.press('Enter');
      }

      await page.waitForLoadState('networkidle');
      await page.waitForTimeout(1000);

      const ssPath2 = path.join(screenshotsDir, '10_search_no_results.png');
      await page.screenshot({ path: ssPath2, fullPage: true });
      logScreenshot('10_search_no_results.png', 'Search with no results');

      // Check for no results message
      const noResults = page.locator('text=/no results|no documents found|nothing found|no matches/i');
      if (await noResults.count() > 0) {
        logPositive('Search shows clear "no results" message');
      } else {
        logIssue('LOW', 'FE-026', 'Unclear no-results message',
          'Search for non-existent documents does not show clear feedback');
      }
    }
  });

  // Test 5: Empty state - no conversations
  test('5. empty state - no conversations', async ({ page }) => {
    await login(page);
    await dismissCookieBanner(page);

    // Navigate to RAG/chat
    await page.goto('/rag');
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(1000);

    const ssPath = path.join(screenshotsDir, '11_rag_empty_state.png');
    await page.screenshot({ path: ssPath, fullPage: true });
    logScreenshot('11_rag_empty_state.png', 'RAG chat empty state');

    // Check for welcome/empty state
    const welcomeMessage = page.locator('text=/start.*conversation|ask.*question|welcome|get started/i');
    const hasWelcome = await welcomeMessage.count() > 0;

    if (hasWelcome) {
      logPositive('RAG chat shows helpful welcome message for new users');
    }

    // Check for conversation history
    const conversations = page.locator('[class*="conversation"] a, [class*="history"] a, aside a');
    const convCount = await conversations.count();
    console.log(`Existing conversations: ${convCount}`);

    // Look for "no conversations" message if list is empty
    const noConversations = page.locator('text=/no conversations|no history|start your first/i');
    if (await noConversations.count() > 0) {
      logPositive('Shows clear empty state when no conversations exist');
    }
  });

  // Test 6: Unauthorized access handling
  test('6. unauthorized access handling', async ({ page }) => {
    // Try to access protected page without login
    await page.goto('/documents');
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(1000);

    const ssPath = path.join(screenshotsDir, '12_unauthorized_redirect.png');
    await page.screenshot({ path: ssPath, fullPage: true });
    logScreenshot('12_unauthorized_redirect.png', 'Unauthorized access redirect');

    const currentUrl = page.url();
    console.log(`Unauthorized access redirected to: ${currentUrl}`);

    // Check if redirected to login
    if (currentUrl.includes('sign_in')) {
      logPositive('Unauthorized access properly redirects to login');
    } else {
      logIssue('HIGH', 'FE-027', 'Protected route accessible without auth',
        'Documents page does not redirect unauthorized users to login');
    }

    // Check for flash message explaining why
    const flashMessage = page.locator('text=/sign in|log in|authenticated/i');
    if (await flashMessage.count() > 0) {
      logPositive('User sees explanation for redirect');
    }

    // Try admin page without auth
    await page.goto('/admin');
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(1000);

    const ssPath2 = path.join(screenshotsDir, '13_admin_unauthorized.png');
    await page.screenshot({ path: ssPath2, fullPage: true });
    logScreenshot('13_admin_unauthorized.png', 'Admin page unauthorized');

    const adminUrl = page.url();
    if (adminUrl.includes('sign_in') || adminUrl === 'http://localhost:3000/') {
      logPositive('Admin routes protected from unauthorized access');
    } else {
      logIssue('CRITICAL', 'FE-028', 'Admin accessible without auth',
        'Admin pages may be accessible without proper authentication');
    }
  });

  // Test 7: Session timeout simulation
  test('7. session timeout behavior', async ({ page }) => {
    await login(page);
    await dismissCookieBanner(page);

    // Navigate to a protected page
    await page.goto('/documents');
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(500);

    const ssPath = path.join(screenshotsDir, '14_authenticated_page.png');
    await page.screenshot({ path: ssPath, fullPage: true });
    logScreenshot('14_authenticated_page.png', 'Authenticated documents page');

    // Clear session cookies to simulate timeout
    await page.context().clearCookies();
    console.log('Cleared cookies to simulate session timeout');

    // Try to access protected page again
    await page.goto('/documents');
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(1000);

    const ssPath2 = path.join(screenshotsDir, '15_session_timeout.png');
    await page.screenshot({ path: ssPath2, fullPage: true });
    logScreenshot('15_session_timeout.png', 'After session timeout');

    const currentUrl = page.url();
    if (currentUrl.includes('sign_in')) {
      logPositive('Session expiry redirects to login');
    } else {
      logIssue('HIGH', 'FE-029', 'Session not validated on requests',
        'Protected pages may be cached and shown after session expires');
    }

    // Check for session expired message
    const sessionMessage = page.locator('text=/session.*expired|sign in.*again|log in.*continue/i');
    if (await sessionMessage.count() > 0) {
      logPositive('Session expiry shows clear message');
    }
  });

  // Test 8: Invalid URL parameters
  test('8. invalid URL parameters', async ({ page }) => {
    await login(page);
    await dismissCookieBanner(page);

    // Try with invalid document ID
    await page.goto('/documents/invalid-id-xyz');
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(1000);

    const ssPath = path.join(screenshotsDir, '16_invalid_doc_id.png');
    await page.screenshot({ path: ssPath, fullPage: true });
    logScreenshot('16_invalid_doc_id.png', 'Invalid document ID');

    const pageContent = await page.content();
    const url = page.url();

    console.log(`Invalid doc ID URL: ${url}`);

    // Check for proper error handling
    const hasError = pageContent.includes('not found') ||
                     pageContent.includes('404') ||
                     pageContent.includes('does not exist') ||
                     url.includes('404') ||
                     url.includes('documents'); // Redirected back to list

    if (hasError || !pageContent.includes('exception')) {
      logPositive('Invalid document ID handled gracefully');
    } else {
      logIssue('MEDIUM', 'FE-030', 'Invalid ID exposes error',
        'Invalid document ID may show raw exception');
    }

    // Try with SQL injection-like parameter
    await page.goto('/documents/1%27OR%271%27=%271');
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(1000);

    const ssPath2 = path.join(screenshotsDir, '17_sql_injection_test.png');
    await page.screenshot({ path: ssPath2, fullPage: true });
    logScreenshot('17_sql_injection_test.png', 'SQL injection-like parameter test');

    const injectionContent = await page.content();
    if (!injectionContent.includes('SQL') && !injectionContent.includes('syntax error')) {
      logPositive('Malformed parameters do not expose SQL errors');
    } else {
      logIssue('CRITICAL', 'FE-031', 'SQL error exposure',
        'Malformed URL parameters may expose SQL-related errors');
    }
  });

  // Test 9: Form CSRF protection
  test('9. form CSRF protection', async ({ page }) => {
    await page.goto('/users/sign_in');
    await page.waitForLoadState('networkidle');

    // Check for CSRF token in form
    const csrfToken = await page.locator('input[name="authenticity_token"]').count();
    const csrfMeta = await page.locator('meta[name="csrf-token"]').count();

    if (csrfToken > 0 || csrfMeta > 0) {
      logPositive('CSRF protection tokens found in forms');
      console.log(`  Hidden token inputs: ${csrfToken}`);
      console.log(`  Meta CSRF token: ${csrfMeta}`);
    } else {
      logIssue('CRITICAL', 'FE-032', 'Missing CSRF protection',
        'Forms may lack CSRF token protection');
    }

    const ssPath = path.join(screenshotsDir, '18_csrf_check.png');
    await page.screenshot({ path: ssPath, fullPage: true });
    logScreenshot('18_csrf_check.png', 'CSRF token verification');
  });

  // Test 10: JavaScript error monitoring
  test('10. JavaScript error monitoring', async ({ page }) => {
    const jsErrors = [];

    page.on('pageerror', error => {
      jsErrors.push(error.message);
      console.log(`JS Error: ${error.message}`);
    });

    page.on('console', msg => {
      if (msg.type() === 'error') {
        console.log(`Console error: ${msg.text()}`);
      }
    });

    await login(page);
    await dismissCookieBanner(page);

    // Navigate through multiple pages to catch JS errors
    const routes = ['/documents', '/rag', '/search', '/vectors'];

    for (const route of routes) {
      await page.goto(route);
      await page.waitForLoadState('networkidle');
      await page.waitForTimeout(500);
      console.log(`Checked ${route} for JS errors`);
    }

    if (jsErrors.length === 0) {
      logPositive('No JavaScript errors detected during navigation');
    } else {
      logIssue('MEDIUM', 'FE-033', 'JavaScript errors detected',
        `${jsErrors.length} JS errors: ${jsErrors.join('; ').slice(0, 200)}`);
    }

    const ssPath = path.join(screenshotsDir, '19_js_error_check.png');
    await page.screenshot({ path: ssPath, fullPage: true });
    logScreenshot('19_js_error_check.png', 'JavaScript error check');
  });

  // Test 11: Network error simulation (offline mode)
  test('11. network error handling', async ({ page, context }) => {
    await login(page);
    await dismissCookieBanner(page);
    await page.goto('/rag');
    await page.waitForLoadState('networkidle');

    // Take baseline screenshot
    const ssPath = path.join(screenshotsDir, '20_rag_online.png');
    await page.screenshot({ path: ssPath, fullPage: true });
    logScreenshot('20_rag_online.png', 'RAG page online');

    // Enable offline mode
    await context.setOffline(true);
    console.log('Enabled offline mode');

    // Try to interact with the page
    const queryInput = page.locator('[data-rag-target="query"]');
    if (await queryInput.count() > 0) {
      await queryInput.fill('Test message while offline');

      const submitButton = page.locator('[data-rag-target="submit"]');
      if (await submitButton.count() > 0) {
        await submitButton.click();
        await page.waitForTimeout(3000);

        const ssPath2 = path.join(screenshotsDir, '21_rag_offline_submit.png');
        await page.screenshot({ path: ssPath2, fullPage: true });
        logScreenshot('21_rag_offline_submit.png', 'RAG submit while offline');

        // Check for error handling
        const errorIndicator = page.locator('text=/error|failed|offline|network/i');
        if (await errorIndicator.count() > 0) {
          logPositive('Network error shown to user when offline');
        } else {
          console.log('No explicit offline error message (may handle silently)');
        }
      }
    }

    // Restore online mode
    await context.setOffline(false);
    console.log('Restored online mode');
  });

  // Test 12: 500 error handling (if we can trigger it)
  test('12. server error handling', async ({ page }) => {
    // Try to access known broken admin pages from previous audit
    const brokenPages = [
      '/admin/llm_providers',
      '/admin/distributed/dashboard',
      '/admin/embedding_cache/dashboard'
    ];

    await login(page);
    await dismissCookieBanner(page);

    for (const route of brokenPages) {
      await page.goto(route);
      await page.waitForLoadState('networkidle');
      await page.waitForTimeout(500);

      const pageContent = await page.content();
      const hasRailsError = pageContent.includes('NoMethodError') ||
                            pageContent.includes('ActionView::Template::Error') ||
                            pageContent.includes('Rails.root');

      if (hasRailsError) {
        console.log(`${route}: Shows Rails error page`);
        logIssue('CRITICAL', 'FE-034', 'Rails error exposed on admin pages',
          `Admin page ${route} exposes internal Rails error details`);
      }
    }

    const ssPath = path.join(screenshotsDir, '22_server_error_check.png');
    await page.screenshot({ path: ssPath, fullPage: true });
    logScreenshot('22_server_error_check.png', 'Server error handling check');
  });

});

// After all tests, write summary
test.afterAll(async () => {
  console.log('\n' + '='.repeat(60));
  console.log('V8-007 ERROR STATES AND EDGE CASES AUDIT SUMMARY');
  console.log('='.repeat(60));

  console.log('\n📸 SCREENSHOTS CAPTURED:');
  screenshots.forEach(s => {
    console.log(`  - ${s.filename}: ${s.description}`);
  });

  console.log('\n✅ POSITIVE FINDINGS:');
  positiveFindings.forEach(f => {
    console.log(`  - ${f}`);
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
  const resultsPath = path.join(screenshotsDir, 'error_states_audit_results.json');
  fs.writeFileSync(resultsPath, JSON.stringify({
    screenshots,
    positiveFindings,
    issues: auditIssues,
    timestamp: new Date().toISOString()
  }, null, 2));
  console.log(`\n📁 Results saved to: ${resultsPath}`);
});
