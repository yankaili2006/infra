#!/bin/bash
set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=========================================="
echo "E2B 本地部署 - 启动 Consul"
echo "=========================================="
echo ""

# 检查 Consul 是否已安装
if ! command -v consul &> /dev/null; then
    echo -e "${RED}✗${NC} Consul 未安装"
    echo "请先运行: sudo bash 08-install-nomad-consul.sh"
    exit 1
fi

# 数据目录
DATA_DIR="/tmp/consul-local"
mkdir -p "$DATA_DIR"

# 检查是否已经在运行
if pgrep -x "consul" > /dev/null; then
    echo -e "${YELLOW}⚠${NC} Consul 已在运行"
    consul members || true
    exit 0
fi

echo "启动 Consul (dev 模式)..."
echo "数据目录: $DATA_DIR"
echo ""

# 后台启动 Consul（绑定到主网卡，允许所有接口的客户端访问）
nohup consul agent \
    -dev \
    -data-dir="$DATA_DIR" \
    -bind=192.168.99.5 \
    -client=0.0.0.0 \
    > /tmp/e2b-logs/consul.log 2>&1 &

CONSUL_PID=$!
echo "Consul PID: $CONSUL_PID"

# 等待 Consul 就绪
echo -n "等待 Consul 就绪"
MAX_WAIT=30
COUNT=0
while [ $COUNT -lt $MAX_WAIT ]; do
    if consul members &> /dev/null; then
        echo -e " ${GREEN}✓${NC}"
        break
    fi
    echo -n "."
    sleep 1
    COUNT=$((COUNT + 1))
done

if [ $COUNT -eq $MAX_WAIT ]; then
    echo -e " ${RED}✗ 超时${NC}"
    exit 1
fi

echo ""
echo "Consul 成员:"
consul members

echo ""
echo -e "${GREEN}✓ Consul 已启动${NC}"
echo ""
echo "访问地址: http://localhost:8500"
echo "日志文件: /tmp/e2b-logs/consul.log"
echo ""
echo "查看日志: tail -f /tmp/e2b-logs/consul.log"
echo "停止服务: pkill consul"
echo ""
