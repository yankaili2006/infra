# Chrome for Testing 下载解决方案

## 问题描述

服务器无法直接访问 Google Cloud Storage (storage.googleapis.com)，导致无法下载 Chrome for Testing。

**目标文件：**
- URL: https://cdn.playwright.dev/builds/cft/145.0.7632.6/mac-arm64/chrome-mac-arm64.zip
- 版本: 145.0.7632.6 (Playwright Chromium v1208)
- 平台: mac-arm64
- 目标位置: oss://primihub/software/chrome-for-testing/

## 解决方案

### 方案一：使用代理服务器（推荐）

如果有可用的代理服务器：

```bash
# 设置代理
export HTTP_PROXY=http://proxy-server:port
export HTTPS_PROXY=http://proxy-server:port

# 运行下载脚本
cd /mnt/data1/pcloud/infra/local-deploy/scripts
./download-chrome-for-testing.sh 145.0.7632.6 mac-arm64
```

### 方案二：从其他机器下载后上传

#### 步骤 1: 在可访问 Google 的机器上下载

```bash
# 在 Mac/Linux 上
wget https://cdn.playwright.dev/builds/cft/145.0.7632.6/mac-arm64/chrome-mac-arm64.zip

# 或使用 curl
curl -L -O https://cdn.playwright.dev/builds/cft/145.0.7632.6/mac-arm64/chrome-mac-arm64.zip
```

#### 步骤 2: 上传到服务器

```bash
# 使用 scp
scp chrome-mac-arm64.zip primihub@server:/tmp/chrome-mac-arm64-145.0.7632.6.zip

# 或使用 rsync
rsync -avz --progress chrome-mac-arm64.zip primihub@server:/tmp/chrome-mac-arm64-145.0.7632.6.zip
```

#### 步骤 3: 在服务器上传到 OSS

```bash
# 登录服务器
ssh primihub@server

# 上传到 OSS
ossutil cp /tmp/chrome-mac-arm64-145.0.7632.6.zip \
  oss://primihub/software/chrome-for-testing/chrome-mac-arm64-145.0.7632.6.zip \
  -f --progress

# 验证上传
ossutil stat oss://primihub/software/chrome-for-testing/chrome-mac-arm64-145.0.7632.6.zip

# 清理本地文件
rm /tmp/chrome-mac-arm64-145.0.7632.6.zip
```

### 方案三：使用国内镜像（如果有）

某些 CDN 服务可能提供 Chrome for Testing 的镜像：

```bash
# 检查是否有可用的镜像
# 例如：淘宝 NPM 镜像、华为云镜像等

# 如果找到镜像，替换 URL 后下载
wget <mirror-url>/chrome-mac-arm64.zip
```

### 方案四：使用 VPN

如果有 VPN 服务：

```bash
# 连接 VPN
# 然后运行下载脚本
./download-chrome-for-testing.sh 145.0.7632.6 mac-arm64
```

## 自动化脚本使用

### 基本用法

```bash
cd /mnt/data1/pcloud/infra/local-deploy/scripts

# 下载并上传到 OSS
./download-chrome-for-testing.sh [version] [platform]

# 示例：下载 mac-arm64 版本
./download-chrome-for-testing.sh 145.0.7632.6 mac-arm64

# 示例：下载 linux 版本
./download-chrome-for-testing.sh 145.0.7632.6 linux
```

### 支持的平台

- `mac-arm64` - macOS Apple Silicon
- `mac-x64` - macOS Intel
- `linux` - Linux x64
- `win32` - Windows 32-bit
- `win64` - Windows 64-bit

## 从 OSS 下载到其他服务器

在其他服务器上使用已备份的 Chrome：

```bash
# 列出可用的 Chrome 版本
ossutil ls oss://primihub/software/chrome-for-testing/

# 下载特定版本
ossutil cp oss://primihub/software/chrome-for-testing/chrome-mac-arm64-145.0.7632.6.zip ./

# 解压
unzip chrome-mac-arm64-145.0.7632.6.zip

# 使用 Chrome
./chrome-mac-arm64/Google\ Chrome\ for\ Testing.app/Contents/MacOS/Google\ Chrome\ for\ Testing --version
```

## Playwright 集成

如果是为 Playwright 使用：

```bash
# 设置 Playwright 使用自定义 Chrome
export PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH=/path/to/chrome-mac-arm64/Google\ Chrome\ for\ Testing.app/Contents/MacOS/Google\ Chrome\ for\ Testing

# 或在代码中设置
const browser = await chromium.launch({
  executablePath: '/path/to/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing'
});
```

## 网络诊断

### 检查 Google 连接

```bash
# 测试 HTTPS 连接
curl -I --connect-timeout 10 https://www.google.com

# 测试 DNS 解析
nslookup storage.googleapis.com

# 测试路由
traceroute storage.googleapis.com
```

### 检查代理配置

```bash
# 查看当前代理设置
echo $HTTP_PROXY
echo $HTTPS_PROXY
echo $NO_PROXY

# 测试代理连接
curl -x $HTTP_PROXY -I https://www.google.com
```

## 常见问题

### Q: 为什么需要 Chrome for Testing？

A: Chrome for Testing 是专门为自动化测试设计的 Chrome 版本，与 Playwright 等测试框架配合使用。它提供稳定的 API 和可预测的行为。

### Q: 可以使用普通的 Chrome 吗？

A: 可以，但 Chrome for Testing 更适合自动化测试，因为：
- 版本固定，不会自动更新
- 没有自动更新机制
- 与 Playwright 版本精确匹配

### Q: 文件很大，上传很慢怎么办？

A: Chrome for Testing 压缩包通常 100-200MB，建议：
- 使用有线网络而非 WiFi
- 在网络空闲时段上传
- 使用 ossutil 的断点续传功能：`--checkpoint-dir`

### Q: 如何验证下载的文件完整性？

A: 可以使用 MD5 或 SHA256 校验：

```bash
# 计算 MD5
md5sum chrome-mac-arm64-145.0.7632.6.zip

# 计算 SHA256
sha256sum chrome-mac-arm64-145.0.7632.6.zip

# 与官方提供的校验和对比
```

## 相关资源

- **Chrome for Testing 官方页面**: https://googlechromelabs.github.io/chrome-for-testing/
- **Playwright 文档**: https://playwright.dev/docs/browsers
- **下载脚本**: `/mnt/data1/pcloud/infra/local-deploy/scripts/download-chrome-for-testing.sh`

## 备份策略

建议备份多个版本和平台的 Chrome for Testing：

```bash
# 备份常用版本
./download-chrome-for-testing.sh 145.0.7632.6 mac-arm64
./download-chrome-for-testing.sh 145.0.7632.6 linux
./download-chrome-for-testing.sh 145.0.7632.6 win64

# 列出已备份的版本
ossutil ls oss://primihub/software/chrome-for-testing/
```

## 更新日志

- **2026-02-04**: 创建文档，添加多种下载方案
- **版本**: 145.0.7632.6 (Playwright Chromium v1208)
