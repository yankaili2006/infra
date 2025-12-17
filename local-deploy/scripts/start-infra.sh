#!/bin/bash
set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "=========================================="
echo "E2B 本地部署 - 启动基础设施"
echo "=========================================="
echo ""

# 项目路径
PROJECT_ROOT="/root/pcloud/infra"
COMPOSE_DIR="$PROJECT_ROOT/packages/local-dev"

cd "$COMPOSE_DIR"

# 检查 docker-compose.yaml 是否存在
if [ ! -f "docker-compose.yaml" ]; then
    echo -e "${RED}✗${NC} docker-compose.yaml 不存在"
    exit 1
fi

# 检查 Docker 是否运行
if ! docker info &> /dev/null; then
    echo -e "${RED}✗${NC} Docker 守护进程未运行"
    echo "请启动 Docker: sudo systemctl start docker"
    exit 1
fi

echo "启动基础设施服务..."
echo ""

# 启动所有服务
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

# 等待 ClickHouse
echo -n "ClickHouse: "
COUNT=0
while [ $COUNT -lt $MAX_WAIT ]; do
    if docker compose exec -T clickhouse clickhouse-client --query "SELECT 1" &> /dev/null 2>&1; then
        echo -e "${GREEN}✓ 就绪${NC}"
        break
    fi
    echo -n "."
    sleep 1
    COUNT=$((COUNT + 1))
done

if [ $COUNT -eq $MAX_WAIT ]; then
    echo -e "${YELLOW}⚠ 超时 (可能不影响核心功能)${NC}"
fi

echo ""
echo "服务状态:"
docker compose ps

echo ""
echo -e "${GREEN}✓ 基础设施已启动${NC}"
echo ""
echo "访问地址:"
echo "  PostgreSQL: localhost:5432"
echo "  Redis:      localhost:6379"
echo "  ClickHouse: localhost:9000 (HTTP: 8123)"
echo "  Grafana:    http://localhost:53000"
echo ""
echo "查看日志: docker compose -f $COMPOSE_DIR/docker-compose.yaml logs -f [service]"
echo ""
