#!/bin/bash
set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=================================="
echo "E2B 本地部署 - 初始化数据库"
echo "=================================="
echo ""

# 项目路径
PROJECT_ROOT="/mnt/sdb/pcloud/infra"
COMPOSE_DIR="$PROJECT_ROOT/packages/local-dev"
DB_DIR="$PROJECT_ROOT/packages/db"

# 加载环境变量
ENV_FILE="$PROJECT_ROOT/local-deploy/.env.local"

if [ ! -f "$ENV_FILE" ]; then
    echo -e "${RED}✗${NC} 环境配置文件不存在: $ENV_FILE"
    exit 1
fi

echo "加载环境变量: $ENV_FILE"
set -a
source "$ENV_FILE"
set +a
echo ""

# 验证数据库连接字符串
if [ -z "$POSTGRES_CONNECTION_STRING" ]; then
    echo -e "${RED}✗${NC} POSTGRES_CONNECTION_STRING 未设置"
    exit 1
fi

echo "数据库连接: $POSTGRES_CONNECTION_STRING"
echo ""

# 1. 启动基础设施服务
echo "1. 启动基础设施服务 (Docker Compose)..."
echo ""

cd "$COMPOSE_DIR"

if [ ! -f "docker-compose.yaml" ]; then
    echo -e "${RED}✗${NC} docker-compose.yaml 不存在: $COMPOSE_DIR/docker-compose.yaml"
    exit 1
fi

# 检查 Docker 是否运行
if ! docker info &> /dev/null; then
    echo -e "${RED}✗${NC} Docker 守护进程未运行"
    echo "请启动 Docker: sudo systemctl start docker"
    exit 1
fi

echo "启动基础设施服务..."
echo "  - PostgreSQL"
echo "  - Redis"
echo "  - ClickHouse"
echo "  - Grafana Stack (Loki, Tempo, Mimir)"
echo ""

# 启动服务（仅基础设施，不包括可能已添加的 nginx）
docker compose up -d postgres redis clickhouse grafana loki tempo mimir otel-collector

echo ""
echo -e "${GREEN}✓${NC} 基础设施服务已启动"
echo ""

# 2. 等待服务就绪
echo "2. 等待服务就绪..."
echo ""

# 等待 PostgreSQL
echo "等待 PostgreSQL..."
MAX_TRIES=30
TRIES=0

while [ $TRIES -lt $MAX_TRIES ]; do
    if docker compose exec -T postgres pg_isready -U postgres &> /dev/null; then
        echo -e "${GREEN}✓${NC} PostgreSQL 已就绪"
        break
    fi

    TRIES=$((TRIES + 1))
    echo "  尝试 $TRIES/$MAX_TRIES..."
    sleep 2
done

if [ $TRIES -eq $MAX_TRIES ]; then
    echo -e "${RED}✗${NC} PostgreSQL 启动超时"
    exit 1
fi

# 等待 Redis
echo "等待 Redis..."
TRIES=0

while [ $TRIES -lt $MAX_TRIES ]; do
    if docker compose exec -T redis redis-cli ping &> /dev/null; then
        echo -e "${GREEN}✓${NC} Redis 已就绪"
        break
    fi

    TRIES=$((TRIES + 1))
    echo "  尝试 $TRIES/$MAX_TRIES..."
    sleep 2
done

if [ $TRIES -eq $MAX_TRIES ]; then
    echo -e "${RED}✗${NC} Redis 启动超时"
    exit 1
fi

# 等待 ClickHouse
echo "等待 ClickHouse..."
TRIES=0

while [ $TRIES -lt $MAX_TRIES ]; do
    if docker compose exec -T clickhouse clickhouse-client --query "SELECT 1" &> /dev/null; then
        echo -e "${GREEN}✓${NC} ClickHouse 已就绪"
        break
    fi

    TRIES=$((TRIES + 1))
    echo "  尝试 $TRIES/$MAX_TRIES..."
    sleep 2
done

if [ $TRIES -eq $MAX_TRIES ]; then
    echo -e "${YELLOW}⚠${NC} ClickHouse 启动超时（可能不影响核心功能）"
fi

echo ""

# 3. 运行数据库迁移
echo "3. 运行数据库迁移..."
echo ""

cd "$DB_DIR"

# 检查是否有 migrations 目录
if [ ! -d "migrations" ]; then
    echo -e "${RED}✗${NC} 迁移目录不存在: $DB_DIR/migrations"
    exit 1
fi

# 计算迁移文件数量
MIGRATION_COUNT=$(ls migrations/*.sql 2>/dev/null | wc -l)
echo "发现 $MIGRATION_COUNT 个迁移文件"
echo ""

# 检查是否安装了 goose
if ! command -v goose &> /dev/null; then
    echo "goose 未安装，正在安装..."
    go install github.com/pressly/goose/v3/cmd/goose@latest
    export PATH="$PATH:$(go env GOPATH)/bin"
fi

# 验证 goose 安装
if ! command -v goose &> /dev/null; then
    echo -e "${RED}✗${NC} goose 安装失败"
    echo "请手动安装: go install github.com/pressly/goose/v3/cmd/goose@latest"
    exit 1
fi

echo "使用 goose 运行迁移..."
echo "连接字符串: $POSTGRES_CONNECTION_STRING"
echo ""

# 运行迁移
if goose -dir migrations -table _migrations postgres "$POSTGRES_CONNECTION_STRING" up; then
    echo ""
    echo -e "${GREEN}✓${NC} 数据库迁移完成"
else
    echo ""
    echo -e "${RED}✗${NC} 数据库迁移失败"
    exit 1
fi

# 显示当前版本
echo ""
echo "当前数据库版本:"
goose -dir migrations -table _migrations postgres "$POSTGRES_CONNECTION_STRING" status || true

echo ""

# 4. Seed 数据（可选）
echo "4. 初始化测试数据..."
echo ""

cd "$PROJECT_ROOT/packages/shared"

if [ -d "script" ]; then
    cd script

    # 检查是否有 seed 脚本
    if [ -f "Makefile" ] && grep -q "seed-db" Makefile; then
        echo "运行 seed 脚本..."

        # 导出必要的环境变量
        export POSTGRES_CONNECTION_STRING

        if make seed-db; then
            echo -e "${GREEN}✓${NC} 测试数据已创建"
        else
            echo -e "${YELLOW}⚠${NC} 测试数据创建失败（可能不影响部署）"
        fi
    else
        echo -e "${YELLOW}ℹ${NC} 未找到 seed 脚本，跳过"
    fi
else
    echo -e "${YELLOW}ℹ${NC} shared/script 目录不存在，跳过 seed"
fi

echo ""

# 5. 验证数据库
echo "5. 验证数据库..."
echo ""

# 连接到 PostgreSQL 并检查表
echo "检查数据库表..."
TABLE_COUNT=$(docker compose -f "$COMPOSE_DIR/docker-compose.yaml" exec -T postgres \
    psql -U postgres -d postgres -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';" | xargs)

echo "  公共模式中的表数量: $TABLE_COUNT"

if [ "$TABLE_COUNT" -gt 0 ]; then
    echo -e "${GREEN}✓${NC} 数据库表已创建"

    echo ""
    echo "表列表:"
    docker compose -f "$COMPOSE_DIR/docker-compose.yaml" exec -T postgres \
        psql -U postgres -d postgres -c "SELECT tablename FROM pg_tables WHERE schemaname = 'public' ORDER BY tablename;" || true
else
    echo -e "${YELLOW}⚠${NC} 数据库中没有表"
fi

echo ""

# 6. 显示服务状态
echo "6. 服务状态..."
echo ""

cd "$COMPOSE_DIR"
docker compose ps

echo ""

# 7. 总结
echo "=================================="
echo "数据库初始化完成"
echo "=================================="
echo ""

echo -e "${GREEN}✓${NC} 基础设施服务已启动"
echo -e "${GREEN}✓${NC} 数据库迁移已完成"
echo -e "${GREEN}✓${NC} 数据库表已创建 ($TABLE_COUNT 个表)"
echo ""

echo "服务访问:"
echo "  PostgreSQL: localhost:5432"
echo "  Redis:      localhost:6379"
echo "  ClickHouse: localhost:9000 (HTTP: 8123)"
echo "  Grafana:    http://localhost:53000"
echo ""

echo "数据库连接:"
echo "  psql: docker compose -f $COMPOSE_DIR/docker-compose.yaml exec postgres psql -U postgres"
echo "  Redis: docker compose -f $COMPOSE_DIR/docker-compose.yaml exec redis redis-cli"
echo ""

echo "查看日志:"
echo "  docker compose -f $COMPOSE_DIR/docker-compose.yaml logs -f [service]"
echo ""

echo "停止服务:"
echo "  docker compose -f $COMPOSE_DIR/docker-compose.yaml down"
echo ""

echo -e "${GREEN}✓ 初始化完成！${NC}"
echo ""
echo "下一步: 运行 00-init-all.sh 或直接启动服务"
echo "  bash local-deploy/scripts/start-all.sh"
echo ""
