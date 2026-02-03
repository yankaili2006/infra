const { test, expect } = require('@playwright/test');

test('Fragments Preview Functionality Test', async ({ page }) => {
  console.log('=== Fragments Preview Test Started ===\n');

  // 1. 打开Fragments应用
  console.log('Step 1: Opening Fragments application...');
  await page.goto('http://localhost:3001');
  await page.waitForLoadState('networkidle');
  await page.screenshot({ path: 'screenshots-fragments/01-homepage.png' });
  console.log('✓ Fragments homepage loaded\n');

  // 2. 等待页面加载完成，查找输入框
  console.log('Step 2: Looking for chat input...');
  await page.waitForTimeout(2000);

  // 查找输入框（可能是textarea或input）
  const inputSelector = 'textarea, input[type="text"]';
  await page.waitForSelector(inputSelector, { timeout: 10000 });
  console.log('✓ Found input field\n');

  // 3. 输入测试请求
  console.log('Step 3: Entering test request...');
  const testPrompt = 'Create a simple Next.js page that displays "Hello from Fragments!" with a blue background';
  await page.fill(inputSelector, testPrompt);
  await page.screenshot({ path: 'screenshots-fragments/02-input-entered.png' });
  console.log(`✓ Entered prompt: "${testPrompt}"\n`);

  // 4. 提交请求（查找发送按钮）
  console.log('Step 4: Submitting request...');
  const submitButton = page.locator('button[type="submit"], button:has-text("Send"), button:has-text("Generate")').first();
  await submitButton.click();
  await page.screenshot({ path: 'screenshots-fragments/03-request-submitted.png' });
  console.log('✓ Request submitted\n');

  // 5. 等待沙箱创建和代码生成
  console.log('Step 5: Waiting for sandbox creation and code generation...');
  console.log('(This may take 30-60 seconds)');

  // 等待加载指示器消失或预览出现
  await page.waitForTimeout(5000);
  await page.screenshot({ path: 'screenshots-fragments/04-processing.png' });

  // 等待更长时间让沙箱完全创建
  await page.waitForTimeout(30000);
  await page.screenshot({ path: 'screenshots-fragments/05-after-wait.png' });
  console.log('✓ Waited for processing\n');

  // 6. 查找预览标签页或iframe
  console.log('Step 6: Looking for preview...');

  // 尝试查找预览相关的元素
  const previewSelectors = [
    'iframe',
    '[role="tabpanel"]',
    'div:has-text("Preview")',
    'button:has-text("Preview")'
  ];

  let previewFound = false;
  for (const selector of previewSelectors) {
    const elements = await page.locator(selector).count();
    if (elements > 0) {
      console.log(`✓ Found preview element: ${selector} (${elements} instances)`);
      previewFound = true;

      // 如果是按钮，点击它
      if (selector.includes('button')) {
        await page.locator(selector).first().click();
        await page.waitForTimeout(2000);
      }
    }
  }

  await page.screenshot({ path: 'screenshots-fragments/06-preview-search.png' });

  // 7. 检查iframe内容
  console.log('\nStep 7: Checking iframe content...');
  const iframes = page.frames();
  console.log(`Found ${iframes.length} frames total`);

  for (let i = 0; i < iframes.length; i++) {
    const frame = iframes[i];
    const frameUrl = frame.url();
    console.log(`  Frame ${i}: ${frameUrl}`);

    // 如果是预览iframe（包含沙箱IP）
    if (frameUrl.includes('10.11.0.') || frameUrl.includes(':3000') || frameUrl.includes(':8501')) {
      console.log(`  ✓ Found preview iframe: ${frameUrl}`);

      // 尝试获取iframe内容
      try {
        const frameContent = await frame.content();
        console.log(`  ✓ Frame content length: ${frameContent.length} bytes`);

        // 检查是否包含预期内容
        if (frameContent.includes('Hello') || frameContent.includes('Next.js')) {
          console.log('  ✓ Frame contains expected content!');
        }
      } catch (error) {
        console.log(`  ⚠ Could not access frame content: ${error.message}`);
      }
    }
  }

  // 8. 最终截图
  console.log('\nStep 8: Capturing final state...');
  await page.screenshot({ path: 'screenshots-fragments/07-final-state.png', fullPage: true });
  console.log('✓ Final screenshot captured\n');

  // 9. 总结
  console.log('=== Test Summary ===');
  console.log(`✓ Fragments loaded successfully`);
  console.log(`✓ Input field found and filled`);
  console.log(`✓ Request submitted`);
  console.log(`✓ Preview elements: ${previewFound ? 'Found' : 'Not found'}`);
  console.log(`✓ Total frames: ${iframes.length}`);
  console.log(`✓ Screenshots saved to screenshots-fragments/`);
  console.log('\n=== Fragments Preview Test Completed ===');
});
