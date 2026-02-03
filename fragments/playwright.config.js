module.exports = {
  testDir: './',
  testMatch: '**/*.spec.js',
  timeout: 120000,
  use: {
    headless: true,  // 使用headless模式（服务器无X Server）
    viewport: { width: 1280, height: 720 },
    screenshot: 'on',
    video: 'retain-on-failure',
  },
};
