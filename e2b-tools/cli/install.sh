#!/bin/bash
# E2B CLI 安装脚本

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}E2B CLI 安装程序${NC}"
echo ""

# 检查依赖
echo "检查依赖..."
for cmd in curl jq; do
    if ! command -v $cmd &>/dev/null; then
        echo "缺少依赖: $cmd"
        echo "安装: sudo apt-get install $cmd"
        exit 1
    fi
done

# 复制工具到 /usr/local/bin
echo "安装 e2b 命令..."
sudo cp /tmp/e2b /usr/local/bin/e2b
sudo chmod +x /usr/local/bin/e2b

# 创建配置文件
CONFIG_FILE="$HOME/.e2b_config"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "创建配置文件..."
    cat > "$CONFIG_FILE" << 'EOF'
# E2B CLI 配置文件
export E2B_API_KEY="e2b_53ae1fed82754c17ad8077fbc8bcdd90"
export E2B_API_URL="http://localhost:3000"
export E2B_TEMPLATE_ID="base-template-000-0000-0000-000000000001"
export E2B_TIMEOUT="300"
EOF
    echo "配置文件已创建: $CONFIG_FILE"
fi

# 添加到 bashrc
if ! grep -q "source $CONFIG_FILE" ~/.bashrc 2>/dev/null; then
    echo "" >> ~/.bashrc
    echo "# E2B CLI Configuration" >> ~/.bashrc
    echo "[ -f $CONFIG_FILE ] && source $CONFIG_FILE" >> ~/.bashrc
    echo "已添加到 ~/.bashrc"
fi

echo ""
echo -e "${GREEN}✓ 安装完成!${NC}"
echo ""
echo "使用方法:"
echo "  e2b help       # 查看帮助"
echo "  e2b create     # 创建VM"
echo "  e2b ls         # 列出VM"
echo "  e2b info       # 查看VM详情"
echo ""
echo "重新加载shell或运行: source ~/.bashrc"
echo ""
