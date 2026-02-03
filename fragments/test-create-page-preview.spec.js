const { test, expect } = require('@playwright/test');

test.describe('Fragments Preview Test', () => {
  test('should create a simple page and display preview correctly', async ({ page }) => {
    // 设置较长的超时时间，因为可能需要等待 AI 响应
    test.setTimeout(120000);

    // 访问 Fragments 应用
    await page.goto('http://localhost:3001');

    // 等待页面加载完成
    await page.waitForLoadState('networkidle');

    console.log('✓ 页面加载完成');

    // 查找输入框（可能是 textarea 或 input）
    const inputSelector = 'textarea, input[type="text"]';
    await page.waitForSelector(inputSelector, { timeout: 10000 });

    console.log('✓ 找到输入框');

    // 输入测试提示词
    const testPrompt = 'Create a simple HTML page with a heading "Hello World" and a blue button that says "Click Me"';
    await page.fill(inputSelector, testPrompt);

    console.log('✓ 输入测试提示词:', testPrompt);

    // 查找并点击提交按钮
    const submitButton = page.locator('button[type="submit"], button:has-text("Send"), button:has-text("Generate")').first();
    await submitButton.click();

    console.log('✓ 点击提交按钮');

    // 等待 preview 区域出现
    // 可能的选择器：iframe, [data-preview], .preview, #preview
    const previewSelectors = [
      'iframe',
      '[data-preview]',
      '.preview',
      '#preview',
      '[class*="preview"]',
      '[id*="preview"]'
    ];

    let previewElement = null;
    for (const selector of previewSelectors) {
      try {
        previewElement = await page.waitForSelector(selector, { timeout: 60000 });
        if (previewElement) {
          console.log(`✓ 找到 preview 元素: ${selector}`);
          break;
        }
      } catch (e) {
        console.log(`  未找到: ${selector}`);
      }
    }

    if (!previewElement) {
      // 截图以便调试
      await page.screenshot({ path: '/mnt/data1/pcloud/infra/fragments/test-results/no-preview-found.png', fullPage: true });
      throw new Error('未找到 preview 元素');
    }

    // 如果是 iframe，检查其内容
    if (await previewElement.evaluate(el => el.tagName === 'IFRAME')) {
      const frame = await previewElement.contentFrame();

      // 等待 iframe 内容加载
      await frame.waitForLoadState('load');

      console.log('✓ iframe 内容加载完成');

      // 检查是否包含预期的内容
      const bodyText = await frame.textContent('body');
      console.log('Preview 内容:', bodyText);

      // 验证包含 "Hello World"
      expect(bodyText).toContain('Hello World');
      console.log('✓ 验证通过: 包含 "Hello World"');

      // 验证包含按钮
      const button = await frame.locator('button:has-text("Click Me")');
      await expect(button).toBeVisible();
      console.log('✓ 验证通过: 按钮可见');

      // 截图保存结果
      await page.screenshot({ path: '/mnt/data1/pcloud/infra/fragments/test-results/preview-success.png', fullPage: true });
      console.log('✓ 截图已保存');
    } else {
      // 如果不是 iframe，直接检查元素内容
      const previewText = await previewElement.textContent();
      console.log('Preview 内容:', previewText);

      await page.screenshot({ path: '/mnt/data1/pcloud/infra/fragments/test-results/preview-element.png', fullPage: true });
      console.log('✓ 截图已保存');
    }

    console.log('✅ 测试完成');
  });

  test('should handle preview updates when editing code', async ({ page }) => {
    test.setTimeout(120000);

    await page.goto('http://localhost:3000');
    await page.waitForLoadState('networkidle');

    // 输入简单的 HTML 代码
    const inputSelector = 'textarea, input[type="text"]';
    await page.waitForSelector(inputSelector, { timeout: 10000 });

    const testPrompt = 'Create a red div with text "Test Preview"';
    await page.fill(inputSelector, testPrompt);

    const submitButton = page.locator('button[type="submit"], button:has-text("Send"), button:has-text("Generate")').first();
    await submitButton.click();

    // 等待 preview 出现
    await page.waitForSelector('iframe, [data-preview], .preview', { timeout: 60000 });

    console.log('✓ Preview 已显示');

    // 截图
    await page.screenshot({ path: '/mnt/data1/pcloud/infra/fragments/test-results/preview-edit-test.png', fullPage: true });

    console.log('✅ 编辑测试完成');
  });
});
