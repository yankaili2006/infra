#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=========================================="
echo "E2B 本地部署 - 停止所有服务"
echo "=========================================="
echo ""

# 项目路径
PROJECT_ROOT="/home/primihub/pcloud/infra"
COMPOSE_DIR="$PROJECT_ROOT/packages/local-dev"

# 1. 停止 Nomad Jobs
echo "1. 停止 Nomad Jobs..."
if command -v nomad &> /dev/null && nomad node status &> /dev/null 2>&1; then
    JOBS=$(nomad job status -short 2>/dev/null | tail -n +2 | awk '{print $1}')
    if [ -n "$JOBS" ]; then
        for job in $JOBS; do
            echo "  停止 Job: $job"
            nomad job stop -purge "$job" || true
        done
        echo -e "${GREEN}✓${NC} Nomad Jobs 已停止"
    else
        echo "  没有运行的 Jobs"
    fi
else
    echo "  Nomad 未运行，跳过"
fi
echo ""

# 2. 停止 Nomad
echo "2. 停止 Nomad..."
if pgrep -x "nomad" > /dev/null; then
    pkill -SIGTERM nomad
    sleep 2
    if pgrep -x "nomad" > /dev/null; then
        pkill -SIGKILL nomad
    fi
    echo -e "${GREEN}✓${NC} Nomad 已停止"
else
    echo "  Nomad 未运行"
fi
echo ""

# 3. 停止 Consul
echo "3. 停止 Consul..."
if pgrep -x "consul" > /dev/null; then
    pkill -SIGTERM consul
    sleep 2
    if pgrep -x "consul" > /dev/null; then
        pkill -SIGKILL consul
    fi
    echo -e "${GREEN}✓${NC} Consul 已停止"
else
    echo "  Consul 未运行"
fi
echo ""

# 4. 停止 Docker Compose 服务
echo "4. 停止基础设施 (Docker Compose)..."
if [ -f "$COMPOSE_DIR/docker-compose.yaml" ]; then
    cd "$COMPOSE_DIR"
    if docker compose ps --quiet 2>/dev/null | grep -q .; then
        docker compose down
        echo -e "${GREEN}✓${NC} Docker 服务已停止"
    else
        echo "  Docker 服务未运行"
    fi
else
    echo "  docker-compose.yaml 不存在，跳过"
fi
echo ""

# 5. 停止可能残留的 Orchestrator 进程
echo "5. 停止残留进程..."
if pgrep -f "orchestrator" > /dev/null; then
    echo "  发现 orchestrator 进程，正在停止..."
    pkill -f "orchestrator" || true
    sleep 1
    if pgrep -f "orchestrator" > /dev/null; then
        pkill -9 -f "orchestrator" || true
    fi
    echo -e "${GREEN}✓${NC} Orchestrator 进程已停止"
else
    echo "  没有残留的 orchestrator 进程"
fi
echo ""

# 6. 清理 Firecracker VMs (如果有残留)
echo "6. 清理 Firecracker VMs..."
if pgrep -f "firecracker" > /dev/null; then
    echo "  发现 firecracker 进程，正在停止..."
    pkill -f "firecracker" || true
    sleep 1
    if pgrep -f "firecracker" > /dev/null; then
        pkill -9 -f "firecracker" || true
    fi
    echo -e "${GREEN}✓${NC} Firecracker VMs 已停止"
else
    echo "  没有运行的 Firecracker VMs"
fi
echo ""

# 7. 显示残留进程
echo "7. 检查残留进程..."
REMAINING=$(pgrep -f "nomad|consul|orchestrator|firecracker" || true)
if [ -n "$REMAINING" ]; then
    echo -e "${YELLOW}⚠${NC} 发现残留进程:"
    ps aux | grep -E "nomad|consul|orchestrator|firecracker" | grep -v grep || true
    echo ""
    echo "如需强制清理，运行: pkill -9 -f 'nomad|consul|orchestrator|firecracker'"
else
    echo "  没有残留进程"
fi
echo ""

# 总结
echo "=========================================="
echo -e "${GREEN}✓ 所有服务已停止${NC}"
echo "=========================================="
echo ""

echo "清理临时数据（可选）:"
echo "  bash cleanup.sh"
echo ""

echo "重新启动:"
echo "  bash start-all.sh"
echo ""
