#!/bin/bash
set -e

# ==========================================
# E2B 本地 VM 创建脚本 (低 CPU 优化版)
# 描述: 禁用遥测和无用服务，降低 CPU 占用
# ==========================================

# 1. 配置路径和变量
export ORCHESTRATOR_BIN="/mnt/sdb/pcloud/infra/packages/orchestrator/bin/orchestrator"
export NODE_ID="ebf61fd6-cd3f-6909-2922-4bd50a6beeff"
export LOG_FILE="/tmp/orchestrator_full.log"
export WORK_DIR="/mnt/sdb/pcloud/infra"

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo "=========================================="
echo "E2B VM Manual Launcher (Optimized)"
echo "=========================================="

# 2. 彻底清理环境
echo "1. Cleaning up existing processes..."
# 强制杀死所有 orchestrator 进程，包括僵尸进程
if pgrep -f "orchestrator" > /dev/null; then
    sudo pkill -9 -f "orchestrator" || true
    echo "   - Killed old orchestrator processes (SIGKILL)"
fi
# 清理端口
sudo fuser -k 5008/tcp 5007/tcp 5010/tcp > /dev/null 2>&1 || true
echo "   - Ports cleaned"

# 3. 启动 Orchestrator (Server Mode)
echo "2. Starting Orchestrator..."

# 环境变量优化：禁用所有遥测和外部上报
export ENVIRONMENT='dev'
export NODE_ID="$NODE_ID"
export POSTGRES_CONNECTION_STRING='postgres://postgres:postgres@127.0.0.1:5432/postgres?sslmode=disable'
export CLICKHOUSE_CONNECTION_STRING='clickhouse://clickhouse:clickhouse@127.0.0.1:9000/clickhouse'
export REDIS_URL='127.0.0.1:6379'
export STORAGE_PROVIDER='Local'
export ARTIFACTS_REGISTRY_PROVIDER='Local'
export LOCAL_TEMPLATE_STORAGE_BASE_PATH='/mnt/sdb/e2b-storage/e2b-template-storage'
export ORCHESTRATOR_BASE_PATH='/mnt/sdb/e2b-storage/e2b-orchestrator'
export TEMPLATE_STORAGE_BASE_PATH='/mnt/sdb/e2b-storage/e2b-template-storage'
export TEMPLATE_BUCKET_NAME='skip'
export BUILD_CACHE_BUCKET_NAME='/mnt/sdb/e2b-storage/e2b-build-cache'
export TEMPLATE_CACHE_DIR='/mnt/sdb/e2b-storage/e2b-template-cache'

# --- 关键优化：禁用 OpenTelemetry 和其他上报 ---
export OTEL_SDK_DISABLED=true
export OTEL_TRACES_EXPORTER=none
export OTEL_METRICS_EXPORTER=none
export OTEL_LOGS_EXPORTER=none
export ANALYTICS_COLLECTOR_API_TOKEN=""
export POSTHOG_API_KEY=""
# ---------------------------------------------

# 使用 sudo -E 保留上述环境变量
sudo -E nohup "$ORCHESTRATOR_BIN" --service orchestrator > "$LOG_FILE" 2>&1 &

ORCHESTRATOR_PID=$!
echo "   - Orchestrator started with PID $ORCHESTRATOR_PID"
echo "   - Logging to $LOG_FILE"

# 4. 等待健康检查
echo "3. Waiting for Orchestrator to be healthy..."
MAX_RETRIES=30
COUNT=0
HEALTHY=false

while [ $COUNT -lt $MAX_RETRIES ]; do
    if curl -s http://localhost:5008/health | grep -q "healthy"; then
        echo -e "   ${GREEN}✅ Orchestrator is HEALTHY!${NC}"
        HEALTHY=true
        break
    fi
    COUNT=$((COUNT+1))
    sleep 1
    echo -n "."
done
echo ""

if [ "$HEALTHY" = false ]; then
    echo -e "${RED}❌ Orchestrator failed to start within ${MAX_RETRIES}s${NC}"
    echo "--- Last 20 lines of log ---"
    tail -n 20 "$LOG_FILE"
    exit 1
fi

# 5. 运行 gRPC 客户端创建 VM
echo "4. Creating VM via gRPC..."
if [ -f "$WORK_DIR/create_vm_grpc.go" ]; then
    cd "$WORK_DIR" && go run create_vm_grpc.go
else
    echo -e "${RED}❌ Error: create_vm_grpc.go not found in $WORK_DIR${NC}"
    exit 1
fi

# 6. 验证结果
echo "5. Verifying VM process..."
if ps aux | grep -v grep | grep -q firecracker; then
    echo -e "${GREEN}🎉 SUCCESS: Firecracker VM process found running!${NC}"
    ps aux | grep -v grep | grep firecracker
else
    echo -e "${RED}⚠️  Warning: Firecracker process not found immediately. Check orchestrator logs.${NC}"
fi

echo ""
echo "=========================================="
echo "Note: The Orchestrator (PID $ORCHESTRATOR_PID) is running in the background."
echo "To stop it and save CPU, run: sudo kill $ORCHESTRATOR_PID"
echo "=========================================="
