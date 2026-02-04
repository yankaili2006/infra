#!/bin/bash
# 下载 Chrome for Testing 并备份到 OSS
# 用法: ./download-chrome-for-testing.sh [version] [platform]

set -e

# 配置
VERSION="${1:-145.0.7632.6}"
PLATFORM="${2:-mac-arm64}"
CHROME_URL="https://cdn.playwright.dev/builds/cft/${VERSION}/${PLATFORM}/chrome-${PLATFORM}.zip"
FILENAME="chrome-${PLATFORM}-${VERSION}.zip"
OSS_BUCKET="oss://primihub"
OSS_PATH="software/chrome-for-testing"

# 颜色
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${GREEN}[Chrome]${NC} $1"; }
warn() { echo -e "${YELLOW}[Chrome]${NC} $1"; }
err() { echo -e "${RED}[Chrome]${NC} $1"; }

echo ""
echo "=========================================="
echo "Chrome for Testing 下载与备份工具"
echo "=========================================="
echo ""
echo "版本: ${VERSION}"
echo "平台: ${PLATFORM}"
echo "URL: ${CHROME_URL}"
echo ""

# 检查是否需要代理
if [ -n "$HTTP_PROXY" ] || [ -n "$HTTPS_PROXY" ]; then
    log "检测到代理配置:"
    [ -n "$HTTP_PROXY" ] && echo "  HTTP_PROXY: $HTTP_PROXY"
    [ -n "$HTTPS_PROXY" ] && echo "  HTTPS_PROXY: $HTTPS_PROXY"
else
    warn "未检测到代理配置"
    echo ""
    echo "如果需要使用代理，请设置环境变量:"
    echo "  export HTTP_PROXY=http://proxy-server:port"
    echo "  export HTTPS_PROXY=http://proxy-server:port"
    echo ""
    read -p "是否继续尝试直接下载? [y/N]: " confirm
    [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && { log "取消"; exit 0; }
fi

echo ""

# 方法1: 使用 wget
log "[方法1] 尝试使用 wget 下载..."
if wget --timeout=30 --tries=3 -O "/tmp/${FILENAME}" "${CHROME_URL}" 2>&1 | tail -20; then
    log "✓ wget 下载成功"
    DOWNLOAD_SUCCESS=true
else
    warn "✗ wget 下载失败"
    DOWNLOAD_SUCCESS=false
fi

# 方法2: 如果 wget 失败，尝试 curl
if [ "$DOWNLOAD_SUCCESS" = "false" ]; then
    echo ""
    log "[方法2] 尝试使用 curl 下载..."
    if curl -L --max-time 300 --retry 3 -o "/tmp/${FILENAME}" "${CHROME_URL}"; then
        log "✓ curl 下载成功"
        DOWNLOAD_SUCCESS=true
    else
        warn "✗ curl 下载失败"
    fi
fi

# 如果下载失败，提供手动方案
if [ "$DOWNLOAD_SUCCESS" = "false" ]; then
    err "自动下载失败"
    echo ""
    echo "=========================================="
    echo "手动下载方案"
    echo "=========================================="
    echo ""
    echo "1. 在可以访问 Google 的机器上下载文件:"
    echo "   ${CHROME_URL}"
    echo ""
    echo "2. 将文件上传到服务器:"
    echo "   scp ${FILENAME} user@server:/tmp/"
    echo ""
    echo "3. 运行上传脚本:"
    echo "   ./download-chrome-for-testing.sh --upload /tmp/${FILENAME}"
    echo ""
    exit 1
fi

# 检查文件大小
FILE_SIZE=$(du -h "/tmp/${FILENAME}" | cut -f1)
log "下载完成: ${FILENAME} (${FILE_SIZE})"
echo ""

# 上传到 OSS
log "上传到 OSS..."
if command -v ossutil &>/dev/null; then
    OSSUTIL_CMD="ossutil"
elif command -v ossutil64 &>/dev/null; then
    OSSUTIL_CMD="ossutil64"
else
    err "ossutil 未安装"
    echo ""
    echo "请安装 ossutil:"
    echo "  wget https://gosspublic.alicdn.com/ossutil/1.7.19/ossutil64 -O ~/bin/ossutil"
    echo "  chmod +x ~/bin/ossutil"
    exit 1
fi

OSS_FULL_PATH="${OSS_BUCKET}/${OSS_PATH}/${FILENAME}"
log "上传到: ${OSS_FULL_PATH}"

if ${OSSUTIL_CMD} cp "/tmp/${FILENAME}" "${OSS_FULL_PATH}" -f --progress; then
    log "✓ 上传成功"
else
    err "✗ 上传失败"
    exit 1
fi

echo ""

# 验证上传
log "验证上传..."
if ${OSSUTIL_CMD} stat "${OSS_FULL_PATH}" > /dev/null 2>&1; then
    log "✓ 文件已存在于 OSS"
    ${OSSUTIL_CMD} stat "${OSS_FULL_PATH}" | grep -E "File Size|Last-Modified"
else
    err "✗ 验证失败"
    exit 1
fi

# 清理本地文件
log "清理本地文件..."
rm -f "/tmp/${FILENAME}"

echo ""
echo "=========================================="
echo "✓ 完成"
echo "=========================================="
echo ""
echo "文件已备份到: ${OSS_FULL_PATH}"
echo ""
echo "在其他服务器上下载:"
echo "  ${OSSUTIL_CMD} cp ${OSS_FULL_PATH} ./"
echo ""
