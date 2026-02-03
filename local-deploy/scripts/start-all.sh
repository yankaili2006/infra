#!/bin/bash
set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# 脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PCLOUD_HOME="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# 加载环境变量配置
if [ -f "$PCLOUD_HOME/config/env.sh" ]; then
    source "$PCLOUD_HOME/config/env.sh"
fi

# 设置默认值
PCLOUD_HOME="${PCLOUD_HOME:-/home/primihub/pcloud}"
E2B_STORAGE_PATH="${E2B_STORAGE_PATH:-$PCLOUD_HOME/../e2b-storage}"

echo ""
echo "=========================================="
echo -e "${BOLD}E2B 本地部署 - 启动所有服务${NC}"
echo "=========================================="
echo ""
echo "此脚本将按顺序启动所有服务:"
echo "  1. 基础设施 (PostgreSQL, Redis, ClickHouse, Grafana)"
echo "  2. Consul (服务发现)"
echo "  3. Nomad (作业调度)"
echo "  4. 部署 Nomad Jobs (API, Orchestrator, etc.)"
echo "  5. 前端应用 (Fragments, Surf)"
echo ""

read -p "是否继续? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "已取消"
    exit 0
fi

echo ""
START_TIME=$(date +%s)

# 步骤 0: 系统初始化检查
echo ""
echo "=========================================="
echo -e "${BLUE}步骤 0/5: 系统初始化检查${NC}"
echo "=========================================="
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
    echo -e "${YELLOW}⚠${NC} 当前用户不在 kvm 组，正在添加..."
    sudo usermod -aG kvm $USER
    echo -e "${GREEN}✓${NC} 用户已添加到 kvm 组"
    echo -e "${YELLOW}⚠${NC} 请重新登录或运行 'newgrp kvm' 以使组权限生效"
fi

# 检查 /dev/kvm 权限
if [ ! -r /dev/kvm ] || [ ! -w /dev/kvm ]; then
    echo -e "${YELLOW}⚠${NC} /dev/kvm 权限不足，正在设置..."
    sudo chmod 666 /dev/kvm
fi
echo -e "${GREEN}✓${NC} /dev/kvm 权限正常"

# 检查 IP 转发
if [ "$(sysctl -n net.ipv4.ip_forward)" != "1" ]; then
    echo -e "${YELLOW}⚠${NC} IP 转发未启用，正在启用..."
    sudo sysctl -w net.ipv4.ip_forward=1 > /dev/null
fi
echo -e "${GREEN}✓${NC} IP 转发已启用"

echo ""

# 步骤 1: 启动基础设施
echo ""
echo "=========================================="
echo -e "${BLUE}步骤 1/5: 启动基础设施${NC}"
echo "=========================================="
echo ""

if bash "$SCRIPT_DIR/start-infra.sh"; then
    echo -e "${GREEN}✓ 基础设施已启动${NC}"
else
    echo -e "${RED}✗ 基础设施启动失败${NC}"
    exit 1
fi

# 步骤 2: 启动 Consul
echo ""
echo "=========================================="
echo -e "${BLUE}步骤 2/4: 启动 Consul${NC}"
echo "=========================================="
echo ""

if bash "$SCRIPT_DIR/start-consul.sh"; then
    echo -e "${GREEN}✓ Consul 已启动${NC}"
else
    echo -e "${RED}✗ Consul 启动失败${NC}"
    exit 1
fi

# 步骤 3: 启动 Nomad
echo ""
echo "=========================================="
echo -e "${BLUE}步骤 3/4: 启动 Nomad${NC}"
echo "=========================================="
echo ""

if bash "$SCRIPT_DIR/start-nomad.sh"; then
    echo -e "${GREEN}✓ Nomad 已启动${NC}"
else
    echo -e "${RED}✗ Nomad 启动失败${NC}"
    exit 1
fi

# 等待 Nomad 完全就绪
echo ""
echo "等待 Nomad 完全就绪..."
sleep 5

# 步骤 4: 部署 Jobs
echo ""
echo "=========================================="
echo -e "${BLUE}步骤 4/5: 部署 Nomad Jobs${NC}"
echo "=========================================="
echo ""

if bash "$SCRIPT_DIR/deploy-all-jobs.sh"; then
    echo -e "${GREEN}✓ Jobs 已部署${NC}"
else
    echo -e "${YELLOW}⚠ Jobs 部署可能存在问题${NC}"
    echo "请检查 nomad job status 查看详情"
fi

# 步骤 5: 启动前端应用
echo ""
echo "=========================================="
echo -e "${BLUE}步骤 5/5: 启动前端应用${NC}"
echo "=========================================="
echo ""

if bash "$SCRIPT_DIR/start-frontend-apps.sh"; then
    echo -e "${GREEN}✓ 前端应用已启动${NC}"
else
    echo -e "${YELLOW}⚠ 前端应用启动可能存在问题${NC}"
    echo "请检查日志文件查看详情"
fi

# 计算耗时
END_TIME=$(date +%s)
TOTAL_TIME=$((END_TIME - START_TIME))
MINUTES=$((TOTAL_TIME / 60))
SECONDS=$((TOTAL_TIME % 60))

echo ""
echo "=========================================="
echo -e "${GREEN}${BOLD}✓ 所有服务已启动${NC}"
echo "=========================================="
echo ""
echo "总耗时: ${MINUTES}分${SECONDS}秒"
echo ""

echo "服务访问地址:"
echo "  主页 (Nginx):  http://localhost:80"
echo "  API:          http://localhost:3000"
echo "  Fragments:    http://localhost:3001"
echo "  Client Proxy: http://localhost:3002"
echo "  Surf:         http://localhost:3003"
echo "  Grafana:      http://localhost:53000"
echo "  Nomad UI:     http://localhost:4646"
echo "  Consul UI:    http://localhost:8500"
echo ""

echo "验证部署:"
echo "  bash $SCRIPT_DIR/verify-deployment.sh"
echo ""

echo "查看状态:"
echo "  nomad job status              # Nomad Jobs"
echo "  consul catalog services       # Consul 服务"
echo "  docker compose ps             # Docker 服务"
echo ""

echo "查看日志:"
echo "  tail -f $E2B_STORAGE_PATH/logs/*.log      # 所有日志"
echo "  tail -f $E2B_STORAGE_PATH/logs/fragments.log  # Fragments 日志"
echo "  tail -f $E2B_STORAGE_PATH/logs/surf.log       # Surf 日志"
echo "  nomad alloc logs -f <id>                  # Job 日志"
echo "  docker compose logs -f                    # Docker 日志"
echo ""

echo "停止服务:"
echo "  bash $SCRIPT_DIR/stop-all.sh"
echo ""

echo -e "${GREEN}🎉 E2B 已就绪！${NC}"
echo ""
