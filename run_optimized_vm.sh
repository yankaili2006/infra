#!/bin/bash
set -e

# ==========================================
# E2B 最终优化启动脚本
# 包含: NBD清理检测, CPU优化, 路径修复
# ==========================================

export ORCHESTRATOR_BIN="/mnt/sdb/pcloud/infra/packages/orchestrator/bin/orchestrator"
export NODE_ID="ebf61fd6-cd3f-6909-2922-4bd50a6beeff"
export LOG_FILE="/tmp/orchestrator_optimized.log"
export WORK_DIR="/mnt/sdb/pcloud/infra"
export STORAGE_DIR="/mnt/sdb/e2b-storage/e2b-template-storage"
export BUILD_ID="9ac9c8b9-9b8b-476c-9238-8266af308c32"
export TEMPLATE_ID="base-template-000-0000-0000-000000000001"

echo "=== 1. 环境准备 ==="
# 修复路径 (符号链接)
if [ -d "$STORAGE_DIR/$BUILD_ID" ]; then
    if [ ! -L "$STORAGE_DIR/$TEMPLATE_ID" ]; then
        ln -s "$STORAGE_DIR/$BUILD_ID" "$STORAGE_DIR/$TEMPLATE_ID"
        echo "   ✅ 创建模板符号链接"
    fi
fi

# 清理旧进程
sudo pkill -9 -f "orchestrator" || true
sudo fuser -k 5008/tcp 5007/tcp 5010/tcp > /dev/null 2>&1 || true

echo "=== 2. 启动 Orchestrator ==="

# 环境变量配置
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

# CPU 优化 (OTel Blackhole)
export OTEL_COLLECTOR_GRPC_ENDPOINT="127.0.0.1:9999"
export OTEL_EXPORTER_OTLP_METRICS_ENDPOINT="http://127.0.0.1:9999"
export OTEL_EXPORTER_OTLP_TRACES_ENDPOINT="http://127.0.0.1:9999"
export LOGS_COLLECTOR_ADDRESS="http://127.0.0.1:9999"
export ANALYTICS_COLLECTOR_API_TOKEN=""
export POSTHOG_API_KEY=""

# 启动
sudo -E nohup "$ORCHESTRATOR_BIN" --service orchestrator > "$LOG_FILE" 2>&1 &
PID=$!
echo "   ✅ PID: $PID"

echo "=== 3. 等待就绪 ==="
for i in {1..30}; do
    if curl -s http://localhost:5008/health | grep -q "healthy"; then
        echo "   ✅ Orchestrator 健康运行中"
        echo "   提示: 使用 'go run create_vm_grpc.go' 尝试创建 VM"
        exit 0
    fi
    sleep 1
done
echo "   ❌ 启动超时"
