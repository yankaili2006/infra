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

# 环境变量配置
PCLOUD_HOME="${PCLOUD_HOME:-/home/primihub/pcloud}"
E2B_STORAGE_PATH="${E2B_STORAGE_PATH:-$PCLOUD_HOME/../e2b-storage}"

# 项目路径
PROJECT_ROOT="$PCLOUD_HOME/infra"
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
docker-compose up -d

echo ""
echo "等待服务就绪..."
echo ""

# 等待 PostgreSQL
echo -n "PostgreSQL: "
MAX_WAIT=30
COUNT=0
while [ $COUNT -lt $MAX_WAIT ]; do
    if docker-compose exec -T postgres pg_isready -U postgres &> /dev/null; then
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

# ============================================
# 第五步：启动 Nomad
# ============================================
echo ""
echo "=========================================="
echo -e "${BLUE}[5/7]${NC} 启动 Nomad..."
echo "=========================================="
echo ""

# 检查 Nomad 是否已运行
if pgrep -x "nomad" > /dev/null; then
    echo -e "${GREEN}✓${NC} Nomad 已在运行"
else
    echo "启动 Nomad..."
    
    # 创建 Nomad 配置目录
    mkdir -p /mnt/sdb/e2b-storage/nomad/{data,config}
    
    # 创建 Nomad 配置文件
    cat > /mnt/sdb/e2b-storage/nomad/config/nomad.hcl << 'NOMAD_EOF'
data_dir = "/mnt/sdb/e2b-storage/nomad/data"

server {
  enabled = true
  bootstrap_expect = 1
}

client {
  enabled = true
  
  host_volume "e2b-kernels" {
    path = "/mnt/sdb/e2b-storage/fc-kernels"
    read_only = true
  }
  
  host_volume "e2b-config" {
    path = "/mnt/sdb/e2b-storage/config"
    read_only = true
  }
}

consul {
  address = "127.0.0.1:8500"
}

plugin "docker" {
  config {
    allow_privileged = true
    volumes {
      enabled = true
    }
  }
}
NOMAD_EOF
    
    # 启动 Nomad
    nohup nomad agent -config=/mnt/sdb/e2b-storage/nomad/config/nomad.hcl \
        > /mnt/sdb/e2b-storage/logs/nomad.log 2>&1 &
    
    echo $! > /mnt/sdb/e2b-storage/logs/nomad.pid
    
    echo "等待 Nomad 启动..."
    sleep 5
    
    # 验证 Nomad
    if nomad server members &> /dev/null; then
        echo -e "${GREEN}✓${NC} Nomad 启动成功"
    else
        echo -e "${RED}✗${NC} Nomad 启动失败"
        echo "查看日志: tail -f /mnt/sdb/e2b-storage/logs/nomad.log"
        exit 1
    fi
fi

echo ""

# ============================================
# 第六步：部署 E2B Jobs
# ============================================
echo ""
echo "=========================================="
echo -e "${BLUE}[6/7]${NC} 部署 E2B Jobs..."
echo "=========================================="
echo ""

# 检查 Job 文件是否存在
JOBS_DIR="$SCRIPT_DIR/../jobs"
if [ ! -d "$JOBS_DIR" ]; then
    echo -e "${YELLOW}⚠${NC} Jobs 目录不存在: $JOBS_DIR"
    echo "跳过 Jobs 部署"
else
    # 部署 Orchestrator
    if [ -f "$JOBS_DIR/orchestrator.hcl" ]; then
        echo "部署 Orchestrator..."
        if nomad job run "$JOBS_DIR/orchestrator.hcl" &> /dev/null; then
            echo -e "${GREEN}✓${NC} Orchestrator 已部署"
        else
            echo -e "${YELLOW}⚠${NC} Orchestrator 部署失败（可能已存在）"
        fi
    fi
    
    # 部署 API
    if [ -f "$JOBS_DIR/api.hcl" ]; then
        echo "部署 API..."
        if nomad job run "$JOBS_DIR/api.hcl" &> /dev/null; then
            echo -e "${GREEN}✓${NC} API 已部署"
        else
            echo -e "${YELLOW}⚠${NC} API 部署失败（可能已存在）"
        fi
    fi
    
    # 部署 Envd
    if [ -f "$JOBS_DIR/envd.hcl" ]; then
        echo "部署 Envd..."
        if nomad job run "$JOBS_DIR/envd.hcl" &> /dev/null; then
            echo -e "${GREEN}✓${NC} Envd 已部署"
        else
            echo -e "${YELLOW}⚠${NC} Envd 部署失败（可能已存在）"
        fi
    fi
fi

echo ""

# ============================================
# 第七步：验证部署
# ============================================
echo ""
echo "=========================================="
echo -e "${BLUE}[7/7]${NC} 验证部署..."
echo "=========================================="
echo ""

# 检查 Docker 服务
echo "Docker 服务状态:"
docker compose -f $PCLOUD_HOME/infra/packages/local-dev/docker-compose.yaml ps
echo ""

# 检查 Consul
echo "Consul 状态:"
if consul members &> /dev/null; then
    consul members | head -n 2
    echo -e "${GREEN}✓${NC} Consul 运行正常"
else
    echo -e "${RED}✗${NC} Consul 未运行"
fi
echo ""

# 检查 Nomad
echo "Nomad 状态:"
if nomad server members &> /dev/null; then
    nomad server members
    echo -e "${GREEN}✓${NC} Nomad 运行正常"
else
    echo -e "${RED}✗${NC} Nomad 未运行"
fi
echo ""

# 检查 Nomad Jobs
echo "Nomad Jobs 状态:"
nomad job status 2>/dev/null || echo "无运行中的 Jobs"
echo ""

# 计算总耗时
END_TIME=$(date +%s)
TOTAL_TIME=$((END_TIME - START_TIME))
MINUTES=$((TOTAL_TIME / 60))
SECONDS=$((TOTAL_TIME % 60))

echo ""
echo "=========================================="
echo -e "${GREEN}${BOLD}✓ E2B 基础设施启动完成${NC}"
echo "=========================================="
echo ""
echo "总耗时: ${MINUTES}分${SECONDS}秒"
echo ""

echo "服务访问地址:"
echo "  PostgreSQL:   localhost:5432"
echo "  Redis:        localhost:6379"
echo "  ClickHouse:   localhost:9000 (HTTP: 8123)"
echo "  Consul UI:    http://localhost:8500"
echo "  Nomad UI:     http://localhost:4646"
echo "  E2B API:      http://localhost:3000"
echo ""

echo "查看日志:"
echo "  Consul:  tail -f $E2B_STORAGE_PATH/logs/consul.log"
echo "  Nomad:   tail -f $E2B_STORAGE_PATH/logs/nomad.log"
echo "  Docker:  docker compose -f $PCLOUD_HOME/infra/packages/local-dev/docker-compose.yaml logs -f"
echo ""

echo "停止服务:"
echo "  bash $SCRIPT_DIR/stop-all.sh"
echo ""

echo -e "${GREEN}🎉 E2B 已就绪！${NC}"
echo ""

# ============================================
# 第六步：显示状态和下一步
# ============================================
echo -e "${BLUE}[6/6]${NC} 显示服务状态..."
echo ""

echo "=========================================="
echo -e "${GREEN}✓ E2B 基础设施已完全启动${NC}"
echo "=========================================="
echo ""

# 计算耗时
END_TIME=$(date +%s)
TOTAL_TIME=$((END_TIME - START_TIME))
MINUTES=$((TOTAL_TIME / 60))
SECONDS=$((TOTAL_TIME % 60))
echo "总耗时: ${MINUTES}分${SECONDS}秒"
echo ""

echo "服务状态:"
echo ""
echo "Docker 服务:"
docker compose -f "$COMPOSE_DIR/docker-compose.yaml" ps
echo ""

echo "Consul 状态:"
if consul members &> /dev/null; then
    consul members
else
    echo -e "${YELLOW}⚠${NC} Consul 未运行"
fi
echo ""

echo "Nomad 状态:"
if nomad server members &> /dev/null; then
    nomad server members
    echo ""
    nomad node status
else
    echo -e "${YELLOW}⚠${NC} Nomad 未运行"
fi
echo ""

echo "访问地址:"
echo "  PostgreSQL: localhost:5432"
echo "  Redis:      localhost:6379"
echo "  ClickHouse: localhost:9000 (HTTP: 8123)"
echo "  Grafana:    http://localhost:53000"
echo "  Consul UI:  http://localhost:8500"
echo "  Nomad UI:   http://localhost:4646"
echo "  E2B API:    http://localhost:3000"
echo ""

echo "验证部署:"
echo "  bash $SCRIPT_DIR/verify-deployment.sh"
echo ""

echo "查看日志:"
echo "  Docker: docker compose -f $COMPOSE_DIR/docker-compose.yaml logs -f [service]"
echo "  Consul: tail -f $LOG_DIR/consul.log"
echo "  Nomad:  tail -f $LOG_DIR/nomad.log"
echo "  Jobs:   nomad alloc logs -f <alloc-id>"
echo ""

echo "停止服务:"
echo "  bash $SCRIPT_DIR/stop-all.sh"
echo ""

echo -e "${GREEN}🎉 E2B 已就绪！${NC}"
echo ""

# ============================================
# 第六步：显示服务状态
# ============================================
echo ""
echo "=========================================="
echo -e "${GREEN}✓ 所有服务已启动${NC}"
echo "=========================================="
echo ""

# 计算总耗时
END_TIME=$(date +%s)
TOTAL_TIME=$((END_TIME - START_TIME))
MINUTES=$((TOTAL_TIME / 60))
SECONDS=$((TOTAL_TIME % 60))
echo "总耗时: ${MINUTES}分${SECONDS}秒"
echo ""

echo "服务访问地址:"
echo "  PostgreSQL:   localhost:5432"
echo "  Redis:        localhost:6379"
echo "  ClickHouse:   localhost:9000 (HTTP: 8123)"
echo "  Consul UI:    http://localhost:8500"
echo "  Nomad UI:     http://localhost:4646"
echo "  Grafana:      http://localhost:53000"
echo ""

echo "验证服务:"
echo "  consul members"
echo "  nomad server members"
echo "  nomad node status"
echo "  docker compose ps"
echo ""

echo "查看日志:"
echo "  Consul: tail -f /mnt/sdb/e2b-storage/logs/consul.log"
echo "  Nomad:  tail -f /mnt/sdb/e2b-storage/logs/nomad.log"
echo "  Docker: docker compose logs -f"
echo ""

echo "下一步:"
echo "  部署 E2B Jobs: bash $SCRIPT_DIR/deploy-all-jobs.sh"
echo "  停止服务:     bash $SCRIPT_DIR/stop-infra.sh"
echo ""

echo -e "${GREEN}🎉 E2B 基础设施已就绪！${NC}"
echo ""

echo ""
echo "=========================================="
echo -e "${GREEN}${BOLD}✓ E2B 基础设施已启动${NC}"
echo "=========================================="
echo ""

# 计算耗时
END_TIME=$(date +%s)
TOTAL_TIME=$((END_TIME - START_TIME))
MINUTES=$((TOTAL_TIME / 60))
SECONDS=$((TOTAL_TIME % 60))

echo "总耗时: ${MINUTES}分${SECONDS}秒"
echo ""

echo "服务访问地址:"
echo "  Consul UI:    http://localhost:8500"
echo "  Nomad UI:     http://localhost:4646"
echo "  PostgreSQL:   localhost:5432"
echo "  Redis:        localhost:6379"
echo "  ClickHouse:   localhost:9000 (HTTP: 8123)"
echo "  Grafana:      http://localhost:53000"
echo ""

echo "下一步操作:"
echo "  1. 部署 E2B Jobs:"
echo "     bash $SCRIPT_DIR/deploy-all-jobs.sh"
echo ""
echo "  2. 验证部署:"
echo "     bash $SCRIPT_DIR/verify-deployment.sh"
echo ""
echo "  3. 查看状态:"
echo "     nomad job status"
echo "     consul catalog services"
echo ""

echo -e "${GREEN}🎉 E2B 基础设施已就绪！${NC}"
echo ""
