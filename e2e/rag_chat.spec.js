// @ts-check
const { test, expect } = require('@playwright/test');
const fs = require('fs');
const path = require('path');

// Create screenshots directory
const screenshotsDir = path.join(__dirname, '..', 'frontend_audit_screenshots', 'v8-004');
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

test.describe('V8-004: RAG Chat Interface', () => {

  // Test 1: Navigate to RAG chat interface
  test('1. navigate to RAG chat interface', async ({ page }) => {
    await login(page);

    // Look for RAG link in navigation
    const ragLink = page.locator('a:has-text("RAG"), a[href*="rag"], a[href*="chat"], a:has-text("Chat")');

    if (await ragLink.count() > 0) {
      console.log('✓ RAG/Chat link found in navigation');
      await ragLink.first().click();
      await page.waitForLoadState('networkidle');
      await page.waitForTimeout(1000);
    } else {
      // Try direct navigation
      console.log('Trying direct navigation to /rag or /chats...');
      await page.goto('/rag');
      await page.waitForLoadState('networkidle');
    }

    const ssPath = path.join(screenshotsDir, '01_rag_page.png');
    await page.screenshot({ path: ssPath, fullPage: true });
    logScreenshot('01_rag_page.png', 'RAG chat interface');

    const url = page.url();
    console.log(`Current URL: ${url}`);

    // Check for chat-related UI elements
    const chatContainer = page.locator('[data-controller*="chat"], .chat-container, #chat, [class*="chat"], [class*="conversation"]');
    const messageInput = page.locator('textarea, input[type="text"][placeholder*="message"], input[placeholder*="ask"], [data-controller*="message"]');

    if (await chatContainer.count() > 0 || await messageInput.count() > 0) {
      logPositive('RAG chat interface found');
    } else {
      console.log('⚠ Chat interface not immediately visible - checking page content');
    }
  });

  // Test 2: Check RAG page UI elements
  test('2. RAG page UI elements', async ({ page }) => {
    await login(page);
    await page.goto('/rag');
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(1000);

    const ssPath = path.join(screenshotsDir, '02_rag_ui_elements.png');
    await page.screenshot({ path: ssPath, fullPage: true });
    logScreenshot('02_rag_ui_elements.png', 'RAG page UI elements');

    // Check for message input area
    const textarea = page.locator('textarea');
    const textInput = page.locator('input[type="text"]');
    const hasInput = await textarea.count() > 0 || await textInput.count() > 0;

    if (hasInput) {
      logPositive('Message input found');

      // Check for placeholder text
      const placeholder = await textarea.first().getAttribute('placeholder') || await textInput.first().getAttribute('placeholder');
      if (placeholder) {
        console.log(`  Placeholder: "${placeholder}"`);
      }
    } else {
      logIssue('MEDIUM', 'RAG-001', 'No message input visible', 'Could not find textarea or text input for messages');
    }

    // Check for send button
    const sendButton = page.locator('button:has-text("Send"), button:has-text("Ask"), button[type="submit"], button[aria-label*="send"]');
    if (await sendButton.count() > 0) {
      logPositive('Send button found');
    } else {
      console.log('⚠ No explicit send button (may use Enter key)');
    }

    // Check for conversation list/history
    const historyList = page.locator('[class*="history"], [class*="conversation"], [class*="sidebar"], aside');
    if (await historyList.count() > 0) {
      logPositive('Conversation history/sidebar found');
    }

    // Check for model selector
    const modelSelector = page.locator('select[name*="model"], [class*="model"], [data-controller*="model"]');
    if (await modelSelector.count() > 0) {
      logPositive('Model selector found');
    }

    // Check for new conversation button
    const newChatBtn = page.locator('button:has-text("New"), a:has-text("New"), button:has-text("Create"), [aria-label*="new"]');
    if (await newChatBtn.count() > 0) {
      logPositive('New conversation button found');
    }
  });

  // Test 3: Message input and submission
  test('3. message input and submission', async ({ page }) => {
    await login(page);
    await page.goto('/rag');
    await page.waitForLoadState('networkidle');
    await dismissCookieBanner(page);
    await page.waitForTimeout(500);

    // Find and fill message input - use data-rag-target selector
    const queryInput = page.locator('[data-rag-target="query"]');

    if (await queryInput.count() > 0) {
      const testMessage = 'What documents do I have access to?';
      await queryInput.fill(testMessage);

      const ssPath = path.join(screenshotsDir, '03_message_typed.png');
      await page.screenshot({ path: ssPath, fullPage: true });
      logScreenshot('03_message_typed.png', 'Test message typed');

      // Use the correct submit button selector
      const sendButton = page.locator('[data-rag-target="submit"]');
      if (await sendButton.count() > 0) {
        await sendButton.click();
        logPositive('Submit button clicked');
      } else {
        // Try Ctrl+Enter as per UI hint
        await queryInput.press('Control+Enter');
        console.log('Tried Ctrl+Enter to submit');
      }

      // Wait for response
      await page.waitForTimeout(5000);

      const ssPath2 = path.join(screenshotsDir, '04_after_submit.png');
      await page.screenshot({ path: ssPath2, fullPage: true });
      logScreenshot('04_after_submit.png', 'After message submission');

      // Check for streaming response container
      const responseContainer = page.locator('[data-rag-target="responseContainer"]');
      const streamingResponse = page.locator('[data-rag-target="streamingResponse"]');

      if (await streamingResponse.count() > 0) {
        const responseText = await streamingResponse.textContent();
        if (responseText && responseText.length > 0) {
          logPositive(`Response received: ${responseText.slice(0, 50)}...`);
        }
      }

      // Check for status indicators
      const waitingStatus = page.locator('[data-rag-target="waiting"]');
      const streamingStatus = page.locator('[data-rag-target="streaming"]');
      const completeStatus = page.locator('[data-rag-target="complete"]');

      console.log(`Status elements - waiting: ${await waitingStatus.count()}, streaming: ${await streamingStatus.count()}, complete: ${await completeStatus.count()}`);
    } else {
      logIssue('HIGH', 'RAG-002', 'Cannot test message input', 'No query input found');
    }
  });

  // Test 4: Streaming response display
  test('4. streaming response display', async ({ page }) => {
    await login(page);
    await page.goto('/rag');
    await page.waitForLoadState('networkidle');
    await dismissCookieBanner(page);
    await page.waitForTimeout(500);

    // Find query input using data-rag-target
    const queryInput = page.locator('[data-rag-target="query"]');

    if (await queryInput.count() > 0) {
      await queryInput.fill('Tell me about semantic search');

      // Submit using correct button selector
      const sendButton = page.locator('[data-rag-target="submit"]');
      await sendButton.click();

      // Wait briefly and capture streaming state
      await page.waitForTimeout(500);
      const ssPath = path.join(screenshotsDir, '05_streaming_start.png');
      await page.screenshot({ path: ssPath, fullPage: true });
      logScreenshot('05_streaming_start.png', 'Streaming response start');

      // Check for waiting/analyzing status
      const waitingStatus = page.locator('[data-rag-target="waiting"]');
      if (await waitingStatus.isVisible().catch(() => false)) {
        logPositive('Waiting/analyzing status shown during processing');
      }

      // Wait for more content
      await page.waitForTimeout(2000);
      const ssPath2 = path.join(screenshotsDir, '06_streaming_middle.png');
      await page.screenshot({ path: ssPath2, fullPage: true });
      logScreenshot('06_streaming_middle.png', 'Streaming response middle');

      // Check for streaming status
      const streamingStatus = page.locator('[data-rag-target="streaming"]');
      if (await streamingStatus.isVisible().catch(() => false)) {
        logPositive('Streaming status shown during response generation');
      }

      // Check for streaming cursor
      const cursor = page.locator('[data-rag-target="streamingCursor"]');
      if (await cursor.isVisible().catch(() => false)) {
        logPositive('Streaming cursor visible (typing indicator)');
      }

      // Wait for completion
      await page.waitForTimeout(5000);
      const ssPath3 = path.join(screenshotsDir, '07_streaming_complete.png');
      await page.screenshot({ path: ssPath3, fullPage: true });
      logScreenshot('07_streaming_complete.png', 'Streaming response complete');

      // Check for completion status
      const completeStatus = page.locator('[data-rag-target="complete"]');
      if (await completeStatus.isVisible().catch(() => false)) {
        logPositive('Completion status shown (checkmark)');
      }

      // Check for sources
      const sourcesContainer = page.locator('[data-rag-target="sourcesContainer"]');
      if (await sourcesContainer.isVisible().catch(() => false)) {
        logPositive('Sources section visible in response');
      }

      // Check for feedback buttons
      const feedbackContainer = page.locator('[data-rag-target="feedbackContainer"]');
      if (await feedbackContainer.isVisible().catch(() => false)) {
        logPositive('Feedback buttons (thumbs up/down) visible');
      }
    }
  });

  // Test 5: Conversation history
  test('5. conversation history', async ({ page }) => {
    await login(page);
    await page.goto('/rag');
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(1000);

    const ssPath = path.join(screenshotsDir, '08_conversation_history.png');
    await page.screenshot({ path: ssPath, fullPage: true });
    logScreenshot('08_conversation_history.png', 'Conversation history view');

    // Check for conversation list
    const conversations = page.locator('[class*="conversation"] a, [class*="history"] a, aside a, [class*="chat-list"] a');
    const conversationCount = await conversations.count();
    console.log(`Conversations in sidebar: ${conversationCount}`);

    if (conversationCount > 0) {
      logPositive(`${conversationCount} conversations visible in history`);

      // Click on first conversation
      await conversations.first().click();
      await page.waitForLoadState('networkidle');
      await page.waitForTimeout(1000);

      const ssPath2 = path.join(screenshotsDir, '09_selected_conversation.png');
      await page.screenshot({ path: ssPath2, fullPage: true });
      logScreenshot('09_selected_conversation.png', 'Selected conversation');

      // Check for messages loaded
      const messages = page.locator('[class*="message"], [class*="user"], [class*="assistant"]');
      const messageCount = await messages.count();
      console.log(`Messages in conversation: ${messageCount}`);

      if (messageCount > 0) {
        logPositive('Conversation messages loaded when selected');
      }
    } else {
      console.log('ℹ No conversation history (may be empty state)');
    }
  });

  // Test 6: Loading states and error handling
  test('6. loading states and error handling', async ({ page }) => {
    await login(page);
    await page.goto('/rag');
    await page.waitForLoadState('networkidle');
    await dismissCookieBanner(page);
    await page.waitForTimeout(500);

    // Check for empty state welcome message
    const welcomeMessage = page.locator('h3:has-text("Start a conversation")');
    if (await welcomeMessage.count() > 0) {
      logPositive('Empty state welcome message displayed');

      const ssPath = path.join(screenshotsDir, '10_empty_state.png');
      await page.screenshot({ path: ssPath, fullPage: true });
      logScreenshot('10_empty_state.png', 'RAG empty state');
    }

    // Check for loading state UI (animate-bounce used for typing indicator)
    const typingIndicator = page.locator('.animate-bounce');
    console.log(`Typing indicator elements: ${await typingIndicator.count()}`);

    // Test empty message submission
    const queryInput = page.locator('[data-rag-target="query"]');
    const sendButton = page.locator('[data-rag-target="submit"]');

    if (await queryInput.count() > 0 && await sendButton.count() > 0) {
      // Try submitting empty message
      await queryInput.fill('');
      await sendButton.click();
      await page.waitForTimeout(1000);

      const ssPath2 = path.join(screenshotsDir, '11_empty_submit.png');
      await page.screenshot({ path: ssPath2, fullPage: true });
      logScreenshot('11_empty_submit.png', 'Empty message submission');

      // Check if button is disabled when empty
      const isDisabled = await sendButton.isDisabled();
      if (isDisabled) {
        logPositive('Submit button disabled for empty input');
      } else {
        console.log('ℹ Submit button not disabled for empty input');
      }

      // Try very long message
      const longMessage = 'test '.repeat(500); // Reasonable length to test
      await queryInput.fill(longMessage);
      await sendButton.click();
      await page.waitForTimeout(2000);

      const ssPath3 = path.join(screenshotsDir, '12_long_message.png');
      await page.screenshot({ path: ssPath3, fullPage: true });
      logScreenshot('12_long_message.png', 'Long message submission');
    }
  });

  // Test 7: Mobile viewport (375px)
  test('7. mobile viewport (375px)', async ({ page }) => {
    await page.setViewportSize({ width: 375, height: 812 });
    await login(page);
    await page.goto('/rag');
    await page.waitForLoadState('networkidle');
    await dismissCookieBanner(page);
    await page.waitForTimeout(500);

    const ssPath = path.join(screenshotsDir, '13_mobile_rag.png');
    await page.screenshot({ path: ssPath, fullPage: true });
    logScreenshot('13_mobile_rag.png', 'RAG chat on mobile (375px)');

    // Check for hamburger menu
    const hamburger = page.locator('button[aria-label*="menu"], [class*="hamburger"], button svg[class*="menu"]');
    if (await hamburger.count() > 0) {
      logPositive('Mobile menu toggle found');
    }

    // Check if input is still accessible
    const queryInput = page.locator('[data-rag-target="query"]');
    if (await queryInput.count() > 0 && await queryInput.isVisible()) {
      logPositive('Message input accessible on mobile');
    } else {
      logIssue('MEDIUM', 'RAG-003', 'Input hidden on mobile', 'Message input may not be accessible on mobile viewport');
    }

    // Check if submit button is visible
    const sendButton = page.locator('[data-rag-target="submit"]');
    if (await sendButton.count() > 0 && await sendButton.isVisible()) {
      logPositive('Submit button visible on mobile');
    }
  });

  // Test 8: Tablet viewport (768px)
  test('8. tablet viewport (768px)', async ({ page }) => {
    await page.setViewportSize({ width: 768, height: 1024 });
    await login(page);
    await page.goto('/rag');
    await page.waitForLoadState('networkidle');
    await dismissCookieBanner(page);
    await page.waitForTimeout(500);

    const ssPath = path.join(screenshotsDir, '14_tablet_rag.png');
    await page.screenshot({ path: ssPath, fullPage: true });
    logScreenshot('14_tablet_rag.png', 'RAG chat on tablet (768px)');

    // Check if input and button are accessible on tablet
    const queryInput = page.locator('[data-rag-target="query"]');
    const sendButton = page.locator('[data-rag-target="submit"]');

    if (await queryInput.isVisible() && await sendButton.isVisible()) {
      logPositive('Chat interface fully accessible on tablet');
    }
  });

  // Test 9: Desktop viewport (1280px)
  test('9. desktop viewport (1280px)', async ({ page }) => {
    await page.setViewportSize({ width: 1280, height: 800 });
    await login(page);
    await page.goto('/rag');
    await page.waitForLoadState('networkidle');
    await dismissCookieBanner(page);
    await page.waitForTimeout(500);

    const ssPath = path.join(screenshotsDir, '15_desktop_rag.png');
    await page.screenshot({ path: ssPath, fullPage: true });
    logScreenshot('15_desktop_rag.png', 'RAG chat on desktop (1280px)');

    // Check full layout at max width
    const chatContainer = page.locator('[data-controller="rag"]');
    if (await chatContainer.isVisible()) {
      logPositive('RAG chat container properly sized on desktop');
    }

    // Check input and button are accessible
    const queryInput = page.locator('[data-rag-target="query"]');
    const sendButton = page.locator('[data-rag-target="submit"]');

    if (await queryInput.isVisible() && await sendButton.isVisible()) {
      logPositive('Chat interface fully accessible on desktop');
    }
  });

  // Test 10: Document context in RAG
  test('10. document context in RAG', async ({ page }) => {
    await login(page);
    await page.goto('/rag');
    await page.waitForLoadState('networkidle');
    await dismissCookieBanner(page);
    await page.waitForTimeout(500);

    // Check for conversation ID hidden input
    const conversationId = page.locator('[data-rag-target="conversationId"]');
    if (await conversationId.count() > 0) {
      logPositive('Conversation ID tracking implemented');
    }

    // Check for sources container (used when responses have document sources)
    const sourcesContainer = page.locator('[data-rag-target="sources"]');
    console.log(`Sources container present: ${await sourcesContainer.count() > 0}`);

    // Check for streaming toggle (hidden by default)
    const streamingToggle = page.locator('[data-rag-target="streamingToggle"]');
    if (await streamingToggle.count() > 0) {
      logPositive('Streaming toggle implemented');
    }

    // Take final screenshot of UI structure
    const ssPath = path.join(screenshotsDir, '16_document_context.png');
    await page.screenshot({ path: ssPath, fullPage: true });
    logScreenshot('16_document_context.png', 'Document context UI');

    // Check Ctrl+Enter keyboard shortcut hint
    const keyboardHint = page.locator('kbd:has-text("Ctrl+Enter")');
    if (await keyboardHint.count() > 0) {
      logPositive('Keyboard shortcut hint displayed (Ctrl+Enter)');
    }
  });

});

// After all tests, write summary
test.afterAll(async () => {
  console.log('\n' + '='.repeat(60));
  console.log('V8-004 RAG CHAT INTERFACE AUDIT SUMMARY');
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
  const resultsPath = path.join(screenshotsDir, 'rag_audit_results.json');
  fs.writeFileSync(resultsPath, JSON.stringify({
    screenshots,
    positiveFindings,
    issues: auditIssues,
    timestamp: new Date().toISOString()
  }, null, 2));
  console.log(`\n📁 Results saved to: ${resultsPath}`);
});
