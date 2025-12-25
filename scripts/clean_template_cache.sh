#!/bin/bash
# E2B Template Cache清理脚本
# 用途: 清理损坏的template cache，强制系统从chunk cache重建
# 使用场景: 当VM创建失败且看到"CRC64 validation failed"错误时

set -e

echo "======================================================================="
echo "  E2B Template Cache 清理工具"
echo "======================================================================="
echo ""

# 配置
TEMPLATE_CACHE_DIR="${TEMPLATE_CACHE_DIR:-/mnt/sdb/e2b-storage/e2b-template-cache}"

if [ ! -d "$TEMPLATE_CACHE_DIR" ]; then
    echo "⚠️  警告: Template cache目录不存在: $TEMPLATE_CACHE_DIR"
    exit 1
fi

echo "📁 Template Cache目录: $TEMPLATE_CACHE_DIR"
echo ""

# 检查是否有缓存
CACHE_COUNT=$(find "$TEMPLATE_CACHE_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)

if [ "$CACHE_COUNT" -eq 0 ]; then
    echo "✅ Template cache已经是空的，无需清理"
    exit 0
fi

echo "🗂️  发现 $CACHE_COUNT 个缓存条目"
echo ""

# 显示将要删除的内容
echo "将要删除的缓存:"
du -sh "$TEMPLATE_CACHE_DIR"/* 2>/dev/null || true
echo ""

# 确认删除
if [ "$1" != "-f" ] && [ "$1" != "--force" ]; then
    read -p "确认清理template cache? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "❌ 已取消"
        exit 1
    fi
fi

# 执行清理
echo "🧹 开始清理..."

# 尝试普通删除
rm -rf "$TEMPLATE_CACHE_DIR"/* 2>/dev/null || {
    echo "⚠️  需要sudo权限清理root拥有的文件"
    # 这里不自动sudo，让用户手动执行
    echo ""
    echo "请手动执行:"
    echo "  sudo rm -rf $TEMPLATE_CACHE_DIR/*"
    exit 1
}

echo "✅ Template cache清理完成！"
echo ""
echo "📝 下一步:"
echo "  1. 重启orchestrator: nomad job restart orchestrator"
echo "  2. 测试VM创建"
echo ""
