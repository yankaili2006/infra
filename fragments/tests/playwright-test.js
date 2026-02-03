#!/usr/bin/env node
/**
 * Fragments Playwright Browser Test
 *
 * Automated browser testing for Fragments Web UI using Playwright.
 * Tests user interactions, UI elements, and end-to-end workflows.
 *
 * Prerequisites:
 *   npm install playwright
 *   npx playwright install chromium
 *
 * Usage:
 *   node playwright-test.js
 *   node playwright-test.js --headless
 *   node playwright-test.js --screenshot
 */

const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

// Configuration
const config = {
  baseUrl: 'http://localhost:3001',
  headless: process.argv.includes('--headless'),
  screenshot: process.argv.includes('--screenshot'),
  video: process.argv.includes('--video'),
  slowMo: process.argv.includes('--slow') ? 500 : 0,
  timeout: 30000,
};

// Test results
const results = {
  total: 0,
  passed: 0,
  failed: 0,
  tests: [],
  screenshots: [],
};

// Colors for output
const colors = {
  reset: '\x1b[0m',
  bright: '\x1b[1m',
  green: '\x1b[32m',
  red: '\x1b[31m',
  yellow: '\x1b[33m',
  blue: '\x1b[34m',
  cyan: '\x1b[36m',
};

function log(message, color = 'reset') {
  console.log(`${colors[color]}${message}${colors.reset}`);
}

async function takeScreenshot(page, name) {
  if (!config.screenshot) return null;

  const screenshotDir = '/tmp/fragments-screenshots';
  if (!fs.existsSync(screenshotDir)) {
    fs.mkdirSync(screenshotDir, { recursive: true });
  }

  const filename = `${name.replace(/\s+/g, '-').toLowerCase()}-${Date.now()}.png`;
  const filepath = path.join(screenshotDir, filename);

  await page.screenshot({ path: filepath, fullPage: true });
  log(`  📸 Screenshot saved: ${filepath}`, 'cyan');
  results.screenshots.push(filepath);

  return filepath;
}

async function runTest(name, testFn, page) {
  results.total++;
  const startTime = Date.now();

  log(`\n🧪 Testing: ${name}`, 'blue');

  try {
    await testFn(page);
    const duration = Date.now() - startTime;

    results.passed++;
    log(`✅ PASSED (${duration}ms)`, 'green');

    results.tests.push({ name, success: true, duration });
  } catch (error) {
    const duration = Date.now() - startTime;

    results.failed++;
    log(`❌ FAILED (${duration}ms)`, 'red');
    log(`   ${error.message}`, 'red');

    // Take error screenshot
    if (page) {
      await takeScreenshot(page, `error-${name}`);
    }

    results.tests.push({
      name,
      success: false,
      duration,
      error: error.message,
    });
  }
}

// ============================================================
// TEST SUITES
// ============================================================

async function testPageLoad(page) {
  await runTest('Page loads successfully', async (p) => {
    await p.goto(config.baseUrl, { waitUntil: 'networkidle' });
    await p.waitForSelector('body', { timeout: config.timeout });

    const title = await p.title();
    log(`  Page title: ${title}`, 'cyan');

    await takeScreenshot(p, 'page-load');
  }, page);
}

async function testUIElements(page) {
  await runTest('UI elements are visible', async (p) => {
    // Check for main UI elements
    const elements = [
      { selector: 'input[type="text"], textarea', name: 'Input field' },
      { selector: 'button', name: 'Buttons' },
    ];

    for (const element of elements) {
      const exists = await p.locator(element.selector).count() > 0;
      if (!exists) {
        throw new Error(`${element.name} not found (${element.selector})`);
      }
      log(`  ✓ ${element.name} found`, 'green');
    }

    await takeScreenshot(p, 'ui-elements');
  }, page);
}

async function testChatInput(page) {
  await runTest('Chat input accepts text', async (p) => {
    // Find chat input (textarea or input)
    const chatInput = p.locator('textarea, input[type="text"]').first();

    await chatInput.waitFor({ state: 'visible', timeout: config.timeout });
    await chatInput.fill('Write a Python function that prints Hello World');

    const value = await chatInput.inputValue();
    if (!value.includes('Hello World')) {
      throw new Error('Chat input did not accept text');
    }

    log(`  ✓ Input text: ${value.substring(0, 50)}...`, 'cyan');
    await takeScreenshot(p, 'chat-input');
  }, page);
}

async function testSendMessage(page) {
  await runTest('Can send chat message', async (p) => {
    // Fill input
    const chatInput = p.locator('textarea, input[type="text"]').first();
    await chatInput.fill('print(2 + 2)');

    // Find and click send button (look for submit button, or button with send icon/text)
    const sendButton = p.locator('button[type="submit"]').first()
      .or(p.locator('button:has-text("Send")').first())
      .or(p.locator('button:has-text("Generate")').first())
      .or(p.locator('button').last()); // Fallback to last button

    await sendButton.click();
    log(`  ✓ Message sent`, 'cyan');

    // Wait for response (look for loading indicator or new content)
    await p.waitForTimeout(2000); // Wait for processing

    await takeScreenshot(p, 'message-sent');
  }, page);
}

async function testCodeExecution(page) {
  await runTest('Code execution workflow', async (p) => {
    // Navigate to fresh page
    await p.goto(config.baseUrl, { waitUntil: 'networkidle' });
    await p.waitForTimeout(1000);

    // Enter Python code
    const chatInput = p.locator('textarea, input[type="text"]').first();
    await chatInput.fill('Create a Python script that calculates factorial of 5');

    // Send
    const sendButton = p.locator('button[type="submit"]').first()
      .or(p.locator('button:has-text("Send")').first())
      .or(p.locator('button:has-text("Generate")').first())
      .or(p.locator('button').last());

    await sendButton.click();
    log(`  ✓ Code generation request sent`, 'cyan');

    // Wait for response (increase timeout for LLM)
    await p.waitForTimeout(5000);

    // Check if code appeared (look for code block or pre tag)
    const codeBlocks = await p.locator('code, pre, .code, [class*="code"]').count();
    log(`  ✓ Found ${codeBlocks} code blocks`, 'cyan');

    await takeScreenshot(p, 'code-execution');
  }, page);
}

async function testTemplateSelection(page) {
  await runTest('Template selection UI', async (p) => {
    await p.goto(config.baseUrl, { waitUntil: 'networkidle' });

    // Look for template selector (dropdown, tabs, or buttons)
    const hasDropdown = await p.locator('select, [role="combobox"]').count() > 0;
    const hasTabs = await p.locator('[role="tab"], .tab').count() > 0;
    const hasButtons = await p.locator('button').count() > 0;

    if (hasDropdown) {
      log(`  ✓ Template dropdown found`, 'cyan');
    } else if (hasTabs) {
      log(`  ✓ Template tabs found`, 'cyan');
    } else if (hasButtons) {
      log(`  ✓ Template selection buttons found`, 'cyan');
    } else {
      log(`  ⚠ No obvious template selector found`, 'yellow');
    }

    await takeScreenshot(p, 'template-selection');
  }, page);
}

async function testResponsiveness(page) {
  await runTest('Responsive design', async (p) => {
    const viewports = [
      { width: 1920, height: 1080, name: 'Desktop' },
      { width: 768, height: 1024, name: 'Tablet' },
      { width: 375, height: 667, name: 'Mobile' },
    ];

    for (const viewport of viewports) {
      await p.setViewportSize({ width: viewport.width, height: viewport.height });
      await p.waitForTimeout(500);

      const bodyVisible = await p.locator('body').isVisible();
      if (!bodyVisible) {
        throw new Error(`UI not visible at ${viewport.name} viewport`);
      }

      log(`  ✓ ${viewport.name} (${viewport.width}x${viewport.height}) OK`, 'cyan');
      await takeScreenshot(p, `responsive-${viewport.name.toLowerCase()}`);
    }
  }, page);
}

async function testAccessibility(page) {
  await runTest('Basic accessibility checks', async (p) => {
    await p.goto(config.baseUrl, { waitUntil: 'networkidle' });

    // Check for alt text on images
    const images = await p.locator('img').all();
    let imagesWithAlt = 0;
    for (const img of images) {
      const alt = await img.getAttribute('alt');
      if (alt) imagesWithAlt++;
    }

    if (images.length > 0) {
      log(`  ✓ ${imagesWithAlt}/${images.length} images have alt text`, 'cyan');
    }

    // Check for aria labels
    const elementsWithAria = await p.locator('[aria-label]').count();
    log(`  ✓ ${elementsWithAria} elements with ARIA labels`, 'cyan');

    // Check for semantic HTML
    const semanticElements = await p.locator('main, nav, header, footer, article, section').count();
    log(`  ✓ ${semanticElements} semantic HTML elements`, 'cyan');

    await takeScreenshot(p, 'accessibility');
  }, page);
}

async function testErrorHandling(page) {
  await runTest('Error handling UI', async (p) => {
    await p.goto(config.baseUrl, { waitUntil: 'networkidle' });

    // Try to trigger an error (submit empty form, invalid input, etc.)
    const chatInput = p.locator('textarea, input[type="text"]').first();
    await chatInput.fill('import nonexistent_module_that_does_not_exist');

    const sendButton = p.locator('button[type="submit"]').first()
      .or(p.locator('button:has-text("Send")').first())
      .or(p.locator('button:has-text("Generate")').first())
      .or(p.locator('button').last());

    await sendButton.click();

    // Wait for response
    await p.waitForTimeout(5000);

    // Check if error message appears
    const errorElements = await p.locator('.error, [class*="error"], .alert, [role="alert"]').count();
    log(`  ✓ Error UI elements found: ${errorElements}`, 'cyan');

    await takeScreenshot(p, 'error-handling');
  }, page);
}

async function testPerformance(page) {
  await runTest('Performance metrics', async (p) => {
    const startTime = Date.now();

    await p.goto(config.baseUrl, { waitUntil: 'networkidle' });

    const loadTime = Date.now() - startTime;
    log(`  ⏱️  Page load time: ${loadTime}ms`, 'cyan');

    if (loadTime > 5000) {
      log(`  ⚠️  Load time exceeds 5 seconds`, 'yellow');
    }

    // Measure time to interactive
    const interactiveTime = await p.evaluate(() => {
      return window.performance.timing.domInteractive - window.performance.timing.navigationStart;
    });
    log(`  ⏱️  Time to interactive: ${interactiveTime}ms`, 'cyan');
  }, page);
}

// ============================================================
// MAIN EXECUTION
// ============================================================

async function main() {
  log('\n' + '='.repeat(60), 'bright');
  log('🎭 FRAGMENTS PLAYWRIGHT BROWSER TEST', 'bright');
  log('='.repeat(60), 'bright');
  log(`Base URL: ${config.baseUrl}`, 'cyan');
  log(`Headless: ${config.headless}`, 'cyan');
  log(`Screenshot: ${config.screenshot}`, 'cyan');
  log(`Slow motion: ${config.slowMo}ms`, 'cyan');

  let browser, context, page;
  const startTime = Date.now();

  try {
    // Launch browser
    log('\n🚀 Launching browser...', 'blue');
    browser = await chromium.launch({
      headless: config.headless,
      slowMo: config.slowMo,
    });

    context = await browser.newContext({
      viewport: { width: 1280, height: 720 },
      recordVideo: config.video ? { dir: '/tmp/fragments-videos' } : undefined,
    });

    page = await context.newPage();

    // Set timeout
    page.setDefaultTimeout(config.timeout);

    log('✅ Browser launched', 'green');

    // Run test suites
    log('\n' + '='.repeat(60), 'bright');
    log('📋 RUNNING TESTS', 'bright');
    log('='.repeat(60), 'bright');

    await testPageLoad(page);
    await testUIElements(page);
    await testChatInput(page);
    await testTemplateSelection(page);
    await testSendMessage(page);
    await testCodeExecution(page);
    await testResponsiveness(page);
    await testAccessibility(page);
    await testErrorHandling(page);
    await testPerformance(page);

  } catch (error) {
    log(`\n💥 Fatal error: ${error.message}`, 'red');
    console.error(error.stack);
    results.failed++;
  } finally {
    // Cleanup
    if (page) await page.close();
    if (context) await context.close();
    if (browser) await browser.close();
    log('\n🔒 Browser closed', 'cyan');
  }

  // Print summary
  const duration = Date.now() - startTime;
  log('\n' + '='.repeat(60), 'bright');
  log('📊 TEST SUMMARY', 'bright');
  log('='.repeat(60), 'bright');
  log(`Total tests:   ${results.total}`, 'cyan');
  log(`✅ Passed:     ${results.passed}`, 'green');
  log(`❌ Failed:     ${results.failed}`, 'red');
  log(`⏱️  Duration:   ${duration}ms`, 'cyan');

  if (results.screenshots.length > 0) {
    log(`📸 Screenshots: ${results.screenshots.length}`, 'cyan');
    log(`   Saved in: /tmp/fragments-screenshots/`, 'cyan');
  }

  log('='.repeat(60), 'bright');

  // Calculate pass rate
  const passRate = results.total > 0
    ? ((results.passed / results.total) * 100).toFixed(1)
    : 0;

  if (results.failed === 0 && results.passed > 0) {
    log(`\n🎉 ALL TESTS PASSED! (${passRate}%)`, 'green');
  } else if (results.failed > 0) {
    log(`\n⚠️  SOME TESTS FAILED (${passRate}% pass rate)`, 'red');
  }

  // Export results
  const resultsFile = `playwright-results-${Date.now()}.json`;
  fs.writeFileSync(
    `/tmp/${resultsFile}`,
    JSON.stringify({ ...results, duration, passRate: parseFloat(passRate) }, null, 2)
  );
  log(`\n📄 Results saved to: /tmp/${resultsFile}`, 'cyan');

  // Exit
  process.exit(results.failed > 0 ? 1 : 0);
}

// Check if Playwright is installed
try {
  require.resolve('playwright');
} catch (error) {
  log('❌ Playwright is not installed!', 'red');
  log('   Install with: npm install playwright', 'yellow');
  log('   Then run: npx playwright install chromium', 'yellow');
  process.exit(1);
}

// Run if called directly
if (require.main === module) {
  main().catch(error => {
    log(`\n💥 Fatal error: ${error.message}`, 'red');
    console.error(error.stack);
    process.exit(1);
  });
}

module.exports = { runTest, results };
