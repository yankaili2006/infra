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
echo ""

read -p "是否继续? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "已取消"
    exit 0
fi

echo ""
START_TIME=$(date +%s)

# 步骤 1: 启动基础设施
echo ""
echo "=========================================="
echo -e "${BLUE}步骤 1/4: 启动基础设施${NC}"
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
echo -e "${BLUE}步骤 4/4: 部署 Nomad Jobs${NC}"
echo "=========================================="
echo ""

if bash "$SCRIPT_DIR/deploy-all-jobs.sh"; then
    echo -e "${GREEN}✓ Jobs 已部署${NC}"
else
    echo -e "${YELLOW}⚠ Jobs 部署可能存在问题${NC}"
    echo "请检查 nomad job status 查看详情"
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
echo "  Client Proxy: http://localhost:3002"
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
echo "  tail -f /tmp/e2b-logs/*.log   # Nomad/Consul 日志"
echo "  nomad alloc logs -f <id>      # Job 日志"
echo "  docker compose logs -f        # Docker 日志"
echo ""

echo "停止服务:"
echo "  bash $SCRIPT_DIR/stop-all.sh"
echo ""

echo -e "${GREEN}🎉 E2B 已就绪！${NC}"
echo ""
