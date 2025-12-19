#!/bin/bash
set -e

export ORCHESTRATOR_BIN="/mnt/sdb/pcloud/infra/packages/orchestrator/bin/orchestrator"
export NODE_ID="ebf61fd6-cd3f-6909-2922-4bd50a6beeff"
export LOG_FILE="/tmp/orchestrator_strace.log"
export WORK_DIR="/mnt/sdb/pcloud/infra"

echo "=== Debug Launcher with Strace ==="

# Cleanup
sudo pkill -9 -f "orchestrator" || true
sudo fuser -k 5008/tcp 5007/tcp 5010/tcp > /dev/null 2>&1 || true

# Env Vars
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
export OTEL_COLLECTOR_GRPC_ENDPOINT="127.0.0.1:9999"
export OTEL_EXPORTER_OTLP_METRICS_ENDPOINT="http://127.0.0.1:9999"
export OTEL_EXPORTER_OTLP_TRACES_ENDPOINT="http://127.0.0.1:9999"
export LOGS_COLLECTOR_ADDRESS="http://127.0.0.1:9999"

# Start with Strace
# We filter for 'stat' family calls and 'open' family calls, and only look at paths containing 'e2b-storage'
echo "Starting Orchestrator with Strace..."
sudo -E nohup strace -f -e trace=file -s 200 "$ORCHESTRATOR_BIN" --service orchestrator > "$LOG_FILE" 2>&1 &
PID=$!

echo "Waiting for health..."
for i in {1..30}; do
    if curl -s http://localhost:5008/health | grep -q "healthy"; then
        echo "✅ Orchestrator is HEALTHY!"
        break
    fi
    sleep 1
done

echo "Creating VM..."
cd "$WORK_DIR" && go run create_vm_grpc.go

echo "Analyzing Log for missing files..."
grep "e2b-storage" "$LOG_FILE" | grep "ENOENT" | tail -n 20
