#!/bin/bash
set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "=========================================="
echo "E2B 本地部署 - 完整启动脚本"
echo "=========================================="
echo ""

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PCLOUD_HOME="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# 加载环境变量配置
if [ -f "$PCLOUD_HOME/config/env.sh" ]; then
    source "$PCLOUD_HOME/config/env.sh"
fi

# 设置默认值
PCLOUD_HOME="${PCLOUD_HOME:-/home/primihub/pcloud}"
PROJECT_ROOT="$PCLOUD_HOME/infra"

# ============================================
# 第一步：检查系统要求
# ============================================
echo -e "${BLUE}[1/5]${NC} 检查系统要求..."
echo ""

# 检查 KVM 模块
if ! lsmod | grep -q "^kvm "; then
    echo -e "${YELLOW}⚠${NC} KVM 模块未加载，正在加载..."
    sudo modprobe kvm
    if grep -q 'vmx' /proc/cpuinfo; then
        sudo modprobe kvm_intel
    elif grep -q 'svm' /proc/cpuinfo; then
        sudo modprobe kvm_amd
    fi
fi
echo -e "${GREEN}✓${NC} KVM 模块已加载"

# 检查 NBD 模块
if ! lsmod | grep -q "^nbd "; then
    echo -e "${YELLOW}⚠${NC} NBD 模块未加载，正在加载..."
    sudo modprobe nbd max_part=8 nbds_max=64
fi
echo -e "${GREEN}✓${NC} NBD 模块已加载"

# 检查用户是否在 kvm 组
if ! groups | grep -q kvm; then
    echo -e "${YELLOW}⚠${NC} 当前用户不在 kvm 组"
    echo "  正在添加用户到 kvm 组..."
    sudo usermod -aG kvm $USER
    echo -e "${GREEN}✓${NC} 用户已添加到 kvm 组"
    echo -e "${YELLOW}⚠${NC} 请重新登录或运行 'newgrp kvm' 以使组权限生效"
    echo ""
    read -p "按 Enter 继续（如果已经重新登录）或 Ctrl+C 退出..."
fi
echo -e "${GREEN}✓${NC} 用户在 kvm 组中"

# 检查 /dev/kvm 权限
if [ ! -r /dev/kvm ] || [ ! -w /dev/kvm ]; then
    echo -e "${YELLOW}⚠${NC} /dev/kvm 权限不足，正在设置..."
    sudo chmod 666 /dev/kvm
fi
echo -e "${GREEN}✓${NC} /dev/kvm 权限正常"

# 检查 Go 是否安装
if ! command -v go &> /dev/null; then
    echo -e "${RED}✗${NC} Go 未安装"
    echo "请先运行: sudo $SCRIPT_DIR/02-install-deps.sh"
    exit 1
fi
echo -e "${GREEN}✓${NC} Go 已安装: $(go version | awk '{print $3}')"

# 检查 Docker 是否运行
if ! docker info &> /dev/null; then
    echo -e "${RED}✗${NC} Docker 未运行"
    echo "请启动 Docker: sudo systemctl start docker"
    exit 1
fi
echo -e "${GREEN}✓${NC} Docker 运行正常"

echo ""

# ============================================
# 第二步：检查内核参数
# ============================================
echo -e "${BLUE}[2/5]${NC} 检查内核参数..."
echo ""

# 检查 IP 转发
if [ "$(sysctl -n net.ipv4.ip_forward)" != "1" ]; then
    echo -e "${YELLOW}⚠${NC} IP 转发未启用，正在启用..."
    sudo sysctl -w net.ipv4.ip_forward=1 > /dev/null
fi
echo -e "${GREEN}✓${NC} IP 转发已启用"

# 检查 bridge-nf-call-iptables
if [ "$(sysctl -n net.bridge.bridge-nf-call-iptables 2>/dev/null || echo 0)" != "1" ]; then
    echo -e "${YELLOW}⚠${NC} bridge-nf-call-iptables 未启用，正在启用..."
    sudo modprobe br_netfilter 2>/dev/null || true
    sudo sysctl -w net.bridge.bridge-nf-call-iptables=1 > /dev/null 2>&1 || true
fi
echo -e "${GREEN}✓${NC} 网桥参数已配置"

echo ""

# ============================================
# 第三步：启动 Docker 基础服务
# ============================================
echo -e "${BLUE}[3/5]${NC} 启动 Docker 基础服务..."
echo ""

COMPOSE_DIR="$PROJECT_ROOT/packages/local-dev"

if [ ! -f "$COMPOSE_DIR/docker-compose.yaml" ]; then
    echo -e "${RED}✗${NC} docker-compose.yaml 不存在: $COMPOSE_DIR"
    exit 1
fi

cd "$COMPOSE_DIR"

# 启动服务
docker compose up -d

echo ""
echo "等待服务就绪..."
echo ""

# 等待 PostgreSQL
echo -n "PostgreSQL: "
MAX_WAIT=30
COUNT=0
while [ $COUNT -lt $MAX_WAIT ]; do
    if docker compose exec -T postgres pg_isready -U postgres &> /dev/null; then
        echo -e "${GREEN}✓ 就绪${NC}"
        break
    fi
    echo -n "."
    sleep 1
    COUNT=$((COUNT + 1))
done

if [ $COUNT -eq $MAX_WAIT ]; then
    echo -e "${RED}✗ 超时${NC}"
fi

# 等待 Redis
echo -n "Redis: "
COUNT=0
while [ $COUNT -lt $MAX_WAIT ]; do
    if docker compose exec -T redis redis-cli ping &> /dev/null 2>&1; then
        echo -e "${GREEN}✓ 就绪${NC}"
        break
    fi
    echo -n "."
    sleep 1
    COUNT=$((COUNT + 1))
done

if [ $COUNT -eq $MAX_WAIT ]; then
    echo -e "${RED}✗ 超时${NC}"
fi

echo ""

# ============================================
# 第四步：检查 E2B 二进制文件
# ============================================
echo -e "${BLUE}[4/5]${NC} 检查 E2B 二进制文件..."
echo ""

API_BIN="$PROJECT_ROOT/packages/api/bin/api"
ORCH_BIN="$PROJECT_ROOT/packages/orchestrator/bin/orchestrator"

if [ ! -f "$API_BIN" ]; then
    echo -e "${YELLOW}⚠${NC} API 二进制文件不存在"
    echo "  位置: $API_BIN"
    echo "  请运行: cd $PROJECT_ROOT/packages/api && go build -o bin/api ./main.go"
else
    echo -e "${GREEN}✓${NC} API 二进制文件存在 ($(du -h $API_BIN | awk '{print $1}'))"
fi

if [ ! -f "$ORCH_BIN" ]; then
    echo -e "${YELLOW}⚠${NC} Orchestrator 二进制文件不存在"
    echo "  位置: $ORCH_BIN"
    echo "  请运行: cd $PROJECT_ROOT/packages/orchestrator && go build -o bin/orchestrator ."
else
    echo -e "${GREEN}✓${NC} Orchestrator 二进制文件存在 ($(du -h $ORCH_BIN | awk '{print $1}'))"
fi

echo ""

# ============================================
# 第五步：显示状态和下一步
# ============================================
echo -e "${BLUE}[5/5]${NC} 启动完成"
echo ""

echo "=========================================="
echo -e "${GREEN}✓ E2B 基础设施已启动${NC}"
echo "=========================================="
echo ""

echo "服务状态:"
docker compose ps
echo ""

echo "访问地址:"
echo "  PostgreSQL: localhost:5432"
echo "  Redis:      localhost:6379"
echo "  ClickHouse: localhost:9000 (HTTP: 8123)"
echo ""

echo "下一步操作:"
echo ""
echo "1. 启动 Consul (服务发现):"
echo "   cd $PROJECT_ROOT/local-deploy/scripts"
echo "   ./start-consul.sh"
echo ""
echo "2. 启动 Nomad (任务编排):"
echo "   ./start-nomad.sh"
echo ""
echo "3. 部署 E2B 服务:"
echo "   nomad job run $PROJECT_ROOT/local-deploy/jobs/orchestrator.hcl"
echo "   nomad job run $PROJECT_ROOT/local-deploy/jobs/api.hcl"
echo ""
echo "4. 验证服务:"
echo "   curl http://localhost:3000/health"
echo ""

echo "查看日志:"
echo "  Docker: docker compose -f $COMPOSE_DIR/docker-compose.yaml logs -f [service]"
echo "  Nomad:  nomad alloc logs <alloc-id>"
echo ""
