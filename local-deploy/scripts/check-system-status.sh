#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

echo ""
echo "=========================================="
echo -e "${BOLD}E2B 系统状态检查${NC}"
echo "=========================================="
echo ""

# 检查函数
check_service() {
    local name=$1
    local check_cmd=$2

    echo -n "  $name: "
    if eval "$check_cmd" &> /dev/null; then
        echo -e "${GREEN}✓ 运行中${NC}"
        return 0
    else
        echo -e "${RED}✗ 未运行${NC}"
        return 1
    fi
}

check_port() {
    local name=$1
    local port=$2
    local url=$3

    echo -n "  $name (端口 $port): "
    if curl -s -o /dev/null -w "%{http_code}" "$url" | grep -q "200\|302\|404"; then
        echo -e "${GREEN}✓ 可访问${NC}"
        return 0
    else
        echo -e "${RED}✗ 不可访问${NC}"
        return 1
    fi
}

# 1. 基础设施服务
echo -e "${BLUE}[1/5] 基础设施服务${NC}"
check_service "Consul" "pgrep -x consul"
check_service "Nomad" "pgrep -x nomad"
echo ""

# 2. Docker 服务
echo -e "${BLUE}[2/5] Docker 服务${NC}"
if command -v docker &> /dev/null; then
    check_service "PostgreSQL" "docker ps | grep -q postgres"
    check_service "Redis" "docker ps | grep -q redis"
    check_service "ClickHouse" "docker ps | grep -q clickhouse"
    check_service "Grafana" "docker ps | grep -q grafana"
else
    echo -e "  ${YELLOW}⚠ Docker 未安装${NC}"
fi
echo ""

# 3. Nomad Jobs
echo -e "${BLUE}[3/5] Nomad Jobs${NC}"
if command -v nomad &> /dev/null && nomad server members &> /dev/null; then
    API_STATUS=$(nomad job status api 2>/dev/null | grep -o "running\|pending\|dead" | head -1)
    ORCH_STATUS=$(nomad job status orchestrator 2>/dev/null | grep -o "running\|pending\|dead" | head -1)

    echo -n "  API: "
    if [ "$API_STATUS" = "running" ]; then
        echo -e "${GREEN}✓ 运行中${NC}"
    elif [ "$API_STATUS" = "pending" ]; then
        echo -e "${YELLOW}⚠ 启动中${NC}"
    else
        echo -e "${RED}✗ 未运行${NC}"
    fi

    echo -n "  Orchestrator: "
    if [ "$ORCH_STATUS" = "running" ]; then
        echo -e "${GREEN}✓ 运行中${NC}"
    elif [ "$ORCH_STATUS" = "pending" ]; then
        echo -e "${YELLOW}⚠ 启动中${NC}"
    else
        echo -e "${RED}✗ 未运行${NC}"
    fi
else
    echo -e "  ${YELLOW}⚠ Nomad 未运行${NC}"
fi
echo ""

# 4. 前端应用
echo -e "${BLUE}[4/5] 前端应用${NC}"
check_service "Fragments" "pgrep -f 'next dev.*fragments'"
check_service "Surf" "pgrep -f 'next dev.*surf'"
echo ""

# 5. 端口可访问性
echo -e "${BLUE}[5/5] 服务端口检查${NC}"
check_port "API" "3000" "http://localhost:3000/health"
check_port "Fragments" "3001" "http://localhost:3001"
check_port "Surf" "3003" "http://localhost:3003"
check_port "Consul UI" "8500" "http://localhost:8500"
check_port "Nomad UI" "4646" "http://localhost:4646"
echo ""

# 总结
echo "=========================================="
echo -e "${BOLD}服务访问地址${NC}"
echo "=========================================="
echo ""
echo "  API:          http://localhost:3000"
echo "  Fragments:    http://localhost:3001"
echo "  Surf:         http://localhost:3003"
echo "  Consul UI:    http://localhost:8500"
echo "  Nomad UI:     http://localhost:4646"
echo "  Grafana:      http://localhost:53000"
echo ""

echo "=========================================="
echo -e "${BOLD}常用命令${NC}"
echo "=========================================="
echo ""
echo "  启动所有服务:   bash start-all.sh"
echo "  停止所有服务:   bash stop-all.sh"
echo "  查看 Nomad 作业: nomad job status"
echo "  查看服务日志:   tail -f /mnt/sdb/e2b-storage/logs/*.log"
echo ""
