#!/bin/bash
set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=================================="
echo "E2B 本地部署 - 存储目录创建"
echo "=================================="
echo ""

# 从 .env.local 读取路径配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$(cd "$SCRIPT_DIR/.." && pwd)/.env.local"

if [ ! -f "$ENV_FILE" ]; then
    echo -e "${RED}✗${NC} 环境配置文件不存在: $ENV_FILE"
    exit 1
fi

echo "从配置文件读取路径: $ENV_FILE"
echo ""

# 导出环境变量
set -a
source "$ENV_FILE"
set +a

# 定义所有需要创建的目录
declare -a STORAGE_DIRS=(
    "$LOCAL_TEMPLATE_STORAGE_BASE_PATH"
    "$BUILD_CACHE_BUCKET_NAME"
    "$ORCHESTRATOR_BASE_PATH"
    "$SANDBOX_DIR"
    "$SANDBOX_CACHE_DIR"
    "$SNAPSHOT_CACHE_DIR"
    "$TEMPLATE_CACHE_DIR"
    "$SHARED_CHUNK_CACHE_PATH"
    "/mnt/sdb/e2b-storage/nomad-local"
    "/mnt/sdb/e2b-storage/consul-local"
    "/mnt/sdb/e2b-storage/logs"
)

# 创建目录
echo "创建存储目录..."
echo ""

for dir in "${STORAGE_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        echo -e "${YELLOW}ℹ${NC} 目录已存在: $dir"
    else
        mkdir -p "$dir"
        echo -e "${GREEN}✓${NC} 已创建: $dir"
    fi

    # 确保目录权限正确
    chmod 755 "$dir"

    # 如果以 sudo 运行，设置正确的所有者
    if [ -n "$SUDO_USER" ]; then
        chown -R "$SUDO_USER:$SUDO_USER" "$dir"
    fi
done

echo ""

# 显示目录大小
echo "存储目录概览:"
echo ""
for dir in "${STORAGE_DIRS[@]}"; do
    SIZE=$(du -sh "$dir" 2>/dev/null | cut -f1)
    echo "  $dir: $SIZE"
done

echo ""

# 检查磁盘空间
echo "磁盘空间检查:"
echo ""

# 检查 /tmp 分区
TMP_SPACE=$(df -h /tmp | awk 'NR==2 {print $4}')
echo "  /tmp 可用空间: $TMP_SPACE"

# 获取唯一的挂载点
MOUNT_POINTS=$(for dir in "${STORAGE_DIRS[@]}"; do df "$dir" | awk 'NR==2 {print $6}'; done | sort -u)

echo ""
echo "相关挂载点:"
for mp in $MOUNT_POINTS; do
    AVAIL=$(df -h "$mp" | awk 'NR==2 {print $4}')
    USED=$(df -h "$mp" | awk 'NR==2 {print $3}')
    TOTAL=$(df -h "$mp" | awk 'NR==2 {print $2}')
    PERCENT=$(df -h "$mp" | awk 'NR==2 {print $5}')
    echo "  $mp: $USED / $TOTAL ($PERCENT) - 可用: $AVAIL"
done

echo ""

# 创建符号链接（可选，便于访问）
SHORTCUTS_DIR="$HOME/e2b-storage"

if [ -n "$SUDO_USER" ]; then
    SHORTCUTS_DIR="/home/$SUDO_USER/e2b-storage"
fi

echo "创建快捷访问目录: $SHORTCUTS_DIR"
mkdir -p "$SHORTCUTS_DIR"

ln -sf "$LOCAL_TEMPLATE_STORAGE_BASE_PATH" "$SHORTCUTS_DIR/templates"
ln -sf "$SANDBOX_CACHE_DIR" "$SHORTCUTS_DIR/sandboxes"
ln -sf "$ORCHESTRATOR_BASE_PATH" "$SHORTCUTS_DIR/orchestrator"
ln -sf "/mnt/sdb/e2b-storage/logs" "$SHORTCUTS_DIR/logs"

if [ -n "$SUDO_USER" ]; then
    chown -h "$SUDO_USER:$SUDO_USER" "$SHORTCUTS_DIR"/*
fi

echo -e "${GREEN}✓${NC} 快捷访问目录已创建"
echo ""

# 创建 README
README_FILE="$SHORTCUTS_DIR/README.txt"
cat > "$README_FILE" <<EOF
E2B 本地部署存储目录
============================

此目录包含指向 E2B 各种存储位置的符号链接，便于快速访问。

创建时间: $(date)

目录说明:
---------

templates/      - 模板存储目录
                  包含构建的沙箱模板文件

sandboxes/      - 沙箱缓存目录
                  活动沙箱的运行时数据

orchestrator/   - Orchestrator 工作目录
                  Orchestrator 服务的临时文件和状态

logs/           - 日志目录
                  各服务的日志文件

完整路径列表:
------------

EOF

for dir in "${STORAGE_DIRS[@]}"; do
    echo "$dir" >> "$README_FILE"
done

cat >> "$README_FILE" <<EOF

清理指南:
--------

# 停止所有服务后清理缓存
rm -rf /mnt/sdb/e2b-storage/e2b-sandbox-cache/*
rm -rf /mnt/sdb/e2b-storage/e2b-snapshot-cache/*
rm -rf /mnt/sdb/e2b-storage/e2b-template-cache/*
rm -rf /mnt/sdb/e2b-storage/e2b-chunk-cache/*

# 完全重置（将删除所有数据，包括模板）
sudo bash /mnt/sdb/pcloud/infra/local-deploy/scripts/cleanup.sh

磁盘空间监控:
------------

# 查看各目录大小
du -h --max-depth=1 /mnt/sdb/e2b-storage/e2b-*

# 查看最大的文件
find /mnt/sdb/e2b-storage/e2b-* -type f -exec du -h {} + | sort -rh | head -20
EOF

if [ -n "$SUDO_USER" ]; then
    chown "$SUDO_USER:$SUDO_USER" "$README_FILE"
fi

echo -e "${GREEN}✓${NC} README 已创建: $README_FILE"
echo ""

# 总结
echo "=================================="
echo "存储目录创建完成"
echo "=================================="
echo ""
echo -e "${GREEN}✓${NC} 所有存储目录已创建并配置正确权限"
echo ""
echo "快捷访问目录: $SHORTCUTS_DIR"
echo "  templates/      - 模板存储"
echo "  sandboxes/      - 沙箱缓存"
echo "  orchestrator/   - Orchestrator 工作目录"
echo "  logs/           - 日志目录"
echo ""
echo "下一步: 运行 06-build-binaries.sh 构建 Go 二进制文件"
echo ""
