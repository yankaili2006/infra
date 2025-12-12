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
echo -e "${BOLD}E2B 本地部署 - 验证部署${NC}"
echo "=========================================="
echo ""

# 检查计数
CHECKS_PASSED=0
CHECKS_FAILED=0
CHECKS_WARNING=0

# 检查函数
check_service() {
    local name=$1
    local check_cmd=$2
    local url=$3

    echo -n "检查 $name... "

    if eval "$check_cmd" &> /dev/null; then
        echo -e "${GREEN}✓ 运行中${NC}"
        if [ -n "$url" ]; then
            echo "  访问地址: $url"
        fi
        CHECKS_PASSED=$((CHECKS_PASSED + 1))
        return 0
    else
        echo -e "${RED}✗ 未运行${NC}"
        CHECKS_FAILED=$((CHECKS_FAILED + 1))
        return 1
    fi
}

check_port() {
    local name=$1
    local port=$2

    echo -n "检查端口 $port ($name)... "

    if lsof -Pi :$port -sTCP:LISTEN -t >/dev/null 2>&1; then
        echo -e "${GREEN}✓ 监听中${NC}"
        CHECKS_PASSED=$((CHECKS_PASSED + 1))
        return 0
    else
        echo -e "${RED}✗ 未监听${NC}"
        CHECKS_FAILED=$((CHECKS_FAILED + 1))
        return 1
    fi
}

check_http() {
    local name=$1
    local url=$2
    local expected_code=${3:-200}

    echo -n "检查 HTTP $name ($url)... "

    response=$(curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "000")

    if [ "$response" == "$expected_code" ]; then
        echo -e "${GREEN}✓ HTTP $response${NC}"
        CHECKS_PASSED=$((CHECKS_PASSED + 1))
        return 0
    else
        echo -e "${RED}✗ HTTP $response (期望: $expected_code)${NC}"
        CHECKS_FAILED=$((CHECKS_FAILED + 1))
        return 1
    fi
}

# 1. 检查基础设施服务
echo "=========================================="
echo "1. 基础设施服务"
echo "=========================================="
echo ""

check_service "PostgreSQL" "docker compose -f /home/primihub/pcloud/infra/packages/local-dev/docker-compose.yaml exec -T postgres pg_isready -U postgres"
check_service "Redis" "docker compose -f /home/primihub/pcloud/infra/packages/local-dev/docker-compose.yaml exec -T redis redis-cli ping"
check_service "ClickHouse" "docker compose -f /home/primihub/pcloud/infra/packages/local-dev/docker-compose.yaml exec -T clickhouse clickhouse-client --query 'SELECT 1'"

echo ""

# 2. 检查 Consul
echo "=========================================="
echo "2. Consul 服务"
echo "=========================================="
echo ""

check_service "Consul Agent" "consul members" "http://localhost:8500"
check_port "Consul HTTP" 8500

if command -v consul &> /dev/null && consul members &> /dev/null; then
    echo ""
    echo "Consul 成员:"
    consul members
    echo ""
    echo "Consul 服务:"
    consul catalog services
fi

echo ""

# 3. 检查 Nomad
echo "=========================================="
echo "3. Nomad 服务"
echo "=========================================="
echo ""

check_service "Nomad Agent" "nomad node status" "http://localhost:4646"
check_port "Nomad HTTP" 4646

if command -v nomad &> /dev/null && nomad node status &> /dev/null; then
    echo ""
    echo "Nomad 节点:"
    nomad node status
    echo ""
    echo "Nomad Jobs:"
    nomad job status
fi

echo ""

# 4. 检查 Nomad Jobs
echo "=========================================="
echo "4. Nomad Jobs 状态"
echo "=========================================="
echo ""

if command -v nomad &> /dev/null && nomad node status &> /dev/null; then
    declare -a EXPECTED_JOBS=("api" "orchestrator" "template-manager" "client-proxy")

    for job in "${EXPECTED_JOBS[@]}"; do
        echo -n "检查 Job: $job... "

        if nomad job status "$job" &> /dev/null; then
            STATUS=$(nomad job status "$job" | grep "^Status" | awk '{print $3}')
            RUNNING=$(nomad job status "$job" | grep -c "running" || echo "0")

            if [ "$STATUS" == "running" ] && [ "$RUNNING" -gt 0 ]; then
                echo -e "${GREEN}✓ $STATUS ($RUNNING allocations)${NC}"
                CHECKS_PASSED=$((CHECKS_PASSED + 1))
            else
                echo -e "${YELLOW}⚠ $STATUS ($RUNNING allocations)${NC}"
                CHECKS_WARNING=$((CHECKS_WARNING + 1))
            fi
        else
            echo -e "${RED}✗ 不存在${NC}"
            CHECKS_FAILED=$((CHECKS_FAILED + 1))
        fi
    done
else
    echo -e "${RED}✗ Nomad 未运行，无法检查 Jobs${NC}"
    CHECKS_FAILED=$((CHECKS_FAILED + 4))
fi

echo ""

# 5. 检查服务端口
echo "=========================================="
echo "5. 服务端口"
echo "=========================================="
echo ""

check_port "API" 3000
check_port "Client Proxy" 3002
check_port "Orchestrator gRPC" 5008
check_port "Orchestrator Proxy" 5007
check_port "Template Manager" 5009

echo ""

# 6. 检查 HTTP 端点
echo "=========================================="
echo "6. HTTP 端点"
echo "=========================================="
echo ""

if command -v curl &> /dev/null; then
    check_http "API Health" "http://localhost:3000/health"
    check_http "Grafana" "http://localhost:53000/" 302
    check_http "Nomad UI" "http://localhost:4646/ui" 301
    check_http "Consul UI" "http://localhost:8500/ui" 301
else
    echo -e "${YELLOW}⚠ curl 未安装，跳过 HTTP 检查${NC}"
fi

echo ""

# 7. 检查存储目录
echo "=========================================="
echo "7. 存储目录"
echo "=========================================="
echo ""

declare -a STORAGE_DIRS=(
    "/tmp/e2b-template-storage"
    "/tmp/e2b-orchestrator"
    "/tmp/e2b-sandbox-cache"
    "/tmp/nomad-local"
    "/tmp/consul-local"
)

for dir in "${STORAGE_DIRS[@]}"; do
    echo -n "检查 $dir... "
    if [ -d "$dir" ]; then
        SIZE=$(du -sh "$dir" 2>/dev/null | cut -f1)
        echo -e "${GREEN}✓ 存在 ($SIZE)${NC}"
        CHECKS_PASSED=$((CHECKS_PASSED + 1))
    else
        echo -e "${RED}✗ 不存在${NC}"
        CHECKS_FAILED=$((CHECKS_FAILED + 1))
    fi
done

echo ""

# 8. 检查内核模块
echo "=========================================="
echo "8. 内核模块"
echo "=========================================="
echo ""

declare -a REQUIRED_MODULES=("kvm" "nbd")

for module in "${REQUIRED_MODULES[@]}"; do
    echo -n "检查模块 $module... "
    if lsmod | grep -q "^$module "; then
        echo -e "${GREEN}✓ 已加载${NC}"
        CHECKS_PASSED=$((CHECKS_PASSED + 1))
    else
        echo -e "${RED}✗ 未加载${NC}"
        CHECKS_FAILED=$((CHECKS_FAILED + 1))
    fi
done

# 检查 /dev/kvm
echo -n "检查 /dev/kvm... "
if [ -e /dev/kvm ]; then
    echo -e "${GREEN}✓ 存在${NC}"
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
else
    echo -e "${RED}✗ 不存在${NC}"
    CHECKS_FAILED=$((CHECKS_FAILED + 1))
fi

echo ""

# 9. 总结
echo "=========================================="
echo "验证总结"
echo "=========================================="
echo ""

TOTAL=$((CHECKS_PASSED + CHECKS_FAILED + CHECKS_WARNING))

echo "总检查项: $TOTAL"
echo -e "${GREEN}通过: $CHECKS_PASSED${NC}"
echo -e "${YELLOW}警告: $CHECKS_WARNING${NC}"
echo -e "${RED}失败: $CHECKS_FAILED${NC}"
echo ""

if [ $CHECKS_FAILED -eq 0 ] && [ $CHECKS_WARNING -eq 0 ]; then
    echo -e "${GREEN}${BOLD}✓ 所有检查通过！部署正常运行${NC}"
    echo ""
    echo "🎉 E2B 本地部署已就绪！"
    exit 0
elif [ $CHECKS_FAILED -eq 0 ]; then
    echo -e "${YELLOW}⚠ 存在警告，但核心功能应该正常${NC}"
    echo ""
    echo "建议检查警告项目"
    exit 0
else
    echo -e "${RED}✗ 部分检查失败，请解决问题${NC}"
    echo ""
    echo "常见问题排查:"
    echo "  1. 检查服务日志: tail -f /tmp/e2b-logs/*.log"
    echo "  2. 检查 Nomad Jobs: nomad job status"
    echo "  3. 检查 Docker: docker compose ps"
    echo "  4. 重启服务: bash stop-all.sh && bash start-all.sh"
    exit 1
fi
