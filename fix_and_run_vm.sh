#!/bin/bash
set -e

# ==========================================
# E2B VM 启动脚本 (最终修复版)
# 修复: 高 CPU 占用 (OTel循环) + 模板找不到问题
# ==========================================

export ORCHESTRATOR_BIN="/mnt/sdb/pcloud/infra/packages/orchestrator/bin/orchestrator"
export NODE_ID="ebf61fd6-cd3f-6909-2922-4bd50a6beeff"
export LOG_FILE="/tmp/orchestrator_final.log"
export WORK_DIR="/mnt/sdb/pcloud/infra"
export STORAGE_DIR="/mnt/sdb/e2b-storage/e2b-template-storage"
export BUILD_ID="9ac9c8b9-9b8b-476c-9238-8266af308c32"
export TEMPLATE_ID="base-template-000-0000-0000-000000000001"

echo "=== E2B Final Fix Launcher ==="

# 1. 修复模板路径 (Symlink Trick)
# Orchestrator 有时可能直接通过 Template ID 查找，或者 Build ID 查找失败
echo "1. Fixing template paths..."
if [ -e "$STORAGE_DIR/$BUILD_ID" ]; then
    echo "   - Build directory found."
    # 创建符号链接：Template ID -> Build Directory
    if [ ! -L "$STORAGE_DIR/$TEMPLATE_ID" ]; then
        ln -s "$STORAGE_DIR/$BUILD_ID" "$STORAGE_DIR/$TEMPLATE_ID"
        echo "   - Created symlink for Template ID."
    else
        echo "   - Symlink already exists."
    fi
else
    echo "❌ Error: Build directory $STORAGE_DIR/$BUILD_ID not found!"
    exit 1
fi

# 2. 清理环境
echo "2. Cleaning up processes..."
sudo pkill -9 -f "orchestrator" || true
sudo fuser -k 5008/tcp 5007/tcp 5010/tcp > /dev/null 2>&1 || true

# 3. 启动 Orchestrator (CPU 优化配置)
echo "3. Starting Orchestrator..."

# 环境变量设置
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

# --- CPU 修复: 将 OTel 指向不存在的端口以触发正常的 Backoff，而不是空地址错误循环 ---
export OTEL_COLLECTOR_GRPC_ENDPOINT="127.0.0.1:9999"
export OTEL_EXPORTER_OTLP_METRICS_ENDPOINT="http://127.0.0.1:9999"
export OTEL_EXPORTER_OTLP_TRACES_ENDPOINT="http://127.0.0.1:9999"
export LOGS_COLLECTOR_ADDRESS="http://127.0.0.1:9999"
# -------------------------------------------------------------------------

sudo -E nohup "$ORCHESTRATOR_BIN" --service orchestrator > "$LOG_FILE" 2>&1 &
ORCHESTRATOR_PID=$!
echo "   - PID: $ORCHESTRATOR_PID"

# 4. 健康检查
echo "4. Waiting for health..."
for i in {1..30}; do
    if curl -s http://localhost:5008/health | grep -q "healthy"; then
        echo "   ✅ Orchestrator is HEALTHY!"
        break
    fi
    sleep 1
done

# 5. 创建 VM
echo "5. Creating VM via gRPC..."
cd "$WORK_DIR" && go run create_vm_grpc.go

# 6. 验证
echo "6. Verifying..."
if ps aux | grep -v grep | grep -q firecracker; then
    echo "   🎉 SUCCESS: Firecracker is running!"
    ps aux | grep -v grep | grep firecracker
else
    echo "   ⚠️ Warning: No firecracker process found. Checking logs..."
    tail -n 20 "$LOG_FILE"
fi
