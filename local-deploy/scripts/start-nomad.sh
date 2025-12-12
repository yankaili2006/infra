#!/bin/bash
set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=========================================="
echo "E2B 本地部署 - 启动 Nomad"
echo "=========================================="
echo ""

# 检查 Nomad 是否已安装
if ! command -v nomad &> /dev/null; then
    echo -e "${RED}✗${NC} Nomad 未安装"
    echo "请先运行: sudo bash 08-install-nomad-consul.sh"
    exit 1
fi

# 配置文件
CONFIG_FILE="/home/primihub/pcloud/infra/local-deploy/nomad-dev.hcl"

if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}✗${NC} Nomad 配置文件不存在: $CONFIG_FILE"
    exit 1
fi

# 检查 Consul 是否运行
if ! consul members &> /dev/null; then
    echo -e "${YELLOW}⚠${NC} Consul 未运行，Nomad 需要 Consul 进行服务发现"
    read -p "是否先启动 Consul? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        bash "$(dirname "$0")/start-consul.sh"
    else
        echo "继续启动 Nomad（服务发现功能可能受限）"
    fi
fi

# 检查是否已经在运行
if pgrep -x "nomad" > /dev/null; then
    echo -e "${YELLOW}⚠${NC} Nomad 已在运行"
    nomad server members || true
    nomad node status || true
    exit 0
fi

echo "启动 Nomad (dev 模式)..."
echo "配置文件: $CONFIG_FILE"
echo ""

# 验证配置
echo "验证配置文件..."
if ! nomad config validate "$CONFIG_FILE"; then
    echo -e "${RED}✗${NC} 配置文件无效"
    exit 1
fi
echo -e "${GREEN}✓${NC} 配置有效"
echo ""

# 后台启动 Nomad
nohup nomad agent -config="$CONFIG_FILE" \
    > /tmp/e2b-logs/nomad.log 2>&1 &

NOMAD_PID=$!
echo "Nomad PID: $NOMAD_PID"

# 等待 Nomad 就绪
echo -n "等待 Nomad 就绪"
MAX_WAIT=30
COUNT=0
while [ $COUNT -lt $MAX_WAIT ]; do
    if nomad server members &> /dev/null; then
        echo -e " ${GREEN}✓${NC}"
        break
    fi
    echo -n "."
    sleep 1
    COUNT=$((COUNT + 1))
done

if [ $COUNT -eq $MAX_WAIT ]; then
    echo -e " ${RED}✗ 超时${NC}"
    echo "查看日志: tail -f /tmp/e2b-logs/nomad.log"
    exit 1
fi

echo ""
echo "Nomad 服务器成员:"
nomad server members

echo ""
echo "Nomad 节点状态:"
nomad node status

echo ""
echo -e "${GREEN}✓ Nomad 已启动${NC}"
echo ""
echo "访问地址: http://localhost:4646"
echo "日志文件: /tmp/e2b-logs/nomad.log"
echo ""
echo "常用命令:"
echo "  nomad node status           # 查看节点"
echo "  nomad job status            # 查看作业"
echo "  tail -f /tmp/e2b-logs/nomad.log  # 查看日志"
echo "  pkill nomad                 # 停止服务"
echo ""
