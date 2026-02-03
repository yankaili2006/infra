#!/bin/bash
# 移动/tmp下的E2B相关文件到infra目录

set -e

# Load environment variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PCLOUD_HOME="$(cd "$SCRIPT_DIR/../../.." && pwd)"
if [ -f "$PCLOUD_HOME/config/env.sh" ]; then
    source "$PCLOUD_HOME/config/env.sh"
fi

PCLOUD_HOME="${PCLOUD_HOME:-/home/primihub/pcloud}"
INFRA_DIR="$PCLOUD_HOME/infra"
TMP_DIR="/tmp"

echo "=== 开始整理E2B相关文件 ==="
echo ""

# 1. 移动CLI工具
echo "[1/5] 移动CLI工具..."
if [ -f "$TMP_DIR/e2b" ]; then
    mv "$TMP_DIR/e2b" "$INFRA_DIR/e2b-tools/cli/e2b"
    echo "  ✓ e2b CLI工具"
fi

if [ -f "$TMP_DIR/install-e2b-cli.sh" ]; then
    mv "$TMP_DIR/install-e2b-cli.sh" "$INFRA_DIR/e2b-tools/cli/install.sh"
    echo "  ✓ CLI安装脚本"
fi

# 2. 移动修复脚本
echo "[2/5] 移动修复脚本..."
for script in fix-*.sh; do
    if [ -f "$TMP_DIR/$script" ]; then
        mv "$TMP_DIR/$script" "$INFRA_DIR/e2b-tools/scripts/"
        echo "  ✓ $script"
    fi
done

# 3. 移动文档
echo "[3/5] 移动文档..."
if [ -f "$TMP_DIR/e2b-vm-usage-guide.md" ]; then
    mv "$TMP_DIR/e2b-vm-usage-guide.md" "$INFRA_DIR/e2b-tools/docs/vm-usage-guide.md"
    echo "  ✓ VM使用指南"
fi

if [ -f "$TMP_DIR/e2b-interactive-shell-guide.md" ]; then
    mv "$TMP_DIR/e2b-interactive-shell-guide.md" "$INFRA_DIR/e2b-tools/docs/interactive-shell-guide.md"
    echo "  ✓ 交互式Shell指南"
fi

if [ -f "$TMP_DIR/e2b-directory-analysis.md" ]; then
    mv "$TMP_DIR/e2b-directory-analysis.md" "$INFRA_DIR/e2b-tools/docs/directory-analysis.md"
    echo "  ✓ 目录分析报告"
fi

# 4. 移动示例代码
echo "[4/5] 移动示例代码..."
if [ -f "$TMP_DIR/e2b-shell-client.go" ]; then
    mv "$TMP_DIR/e2b-shell-client.go" "$INFRA_DIR/e2b-tools/examples/shell-client.go"
    echo "  ✓ Go Shell客户端"
fi

if [ -f "$TMP_DIR/e2b-shell-simple.py" ]; then
    mv "$TMP_DIR/e2b-shell-simple.py" "$INFRA_DIR/e2b-tools/examples/shell-simple.py"
    echo "  ✓ Python Shell示例"
fi

# 5. 清理临时文件
echo "[5/5] 清理临时文件..."
rm -f "$TMP_DIR/.e2b_last_vm"
rm -f "$TMP_DIR/.e2b_cache"
rm -f "$TMP_DIR/metadata-fix.json"
rm -f "$TMP_DIR/vm-create-result.txt"
echo "  ✓ 临时缓存文件已清理"

echo ""
echo "=== 文件整理完成 ==="
echo ""
echo "新的目录结构:"
echo "  $INFRA_DIR/e2b-tools/"
echo "  ├── cli/            # CLI工具"
echo "  ├── scripts/        # 修复脚本"
echo "  ├── docs/           # 文档指南"
echo "  └── examples/       # 示例代码"

