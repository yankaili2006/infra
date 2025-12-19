#!/bin/bash
set -e

# ==========================================
# E2B VM Strace Debugger
# ==========================================

export ORCHESTRATOR_BIN="/mnt/sdb/pcloud/infra/packages/orchestrator/bin/orchestrator"
export LOG_FILE="/tmp/orchestrator_strace.log"
export STRACE_OUT="/tmp/strace.out"

echo "=== 1. Cleanup ==="
sudo pkill -9 -f "orchestrator" || true
sudo fuser -k 5008/tcp || true

echo "=== 2. Starting Orchestrator with Strace ==="

# Environment
export ENVIRONMENT='dev'
export NODE_ID="ebf61fd6-cd3f-6909-2922-4bd50a6beeff" 
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

# OTel Blackhole (Crucial for performance/stability during strace)
export OTEL_COLLECTOR_GRPC_ENDPOINT="127.0.0.1:9999"
export OTEL_EXPORTER_OTLP_METRICS_ENDPOINT="http://127.0.0.1:9999"
export OTEL_EXPORTER_OTLP_TRACES_ENDPOINT="http://127.0.0.1:9999"
export LOGS_COLLECTOR_ADDRESS="http://127.0.0.1:9999"
export ANALYTICS_COLLECTOR_API_TOKEN=""
export POSTHOG_API_KEY=""

# Start with Strace
# -f: follow forks
# -e trace=file: only trace file operations (open, stat, access, etc.)
# -s 200: max string length to print
sudo -E nohup strace -f -e trace=file -s 200 -o "$STRACE_OUT" "$ORCHESTRATOR_BIN" --service orchestrator > "$LOG_FILE" 2>&1 &
PID=$!

echo "   Started PID $PID. Tracing to $STRACE_OUT"

echo "=== 3. Waiting for Health ==="
for i in {1..30}; do
    if curl -s http://localhost:5008/health | grep -q "healthy"; then
        echo "   ✅ Orchestrator is HEALTHY!"
        break
    fi
    sleep 1
done

echo "=== 4. Triggering Error (Create VM) ==="
cd "/mnt/sdb/pcloud/infra" && go run create_vm_grpc.go || true

echo "=== 5. Analyzing Strace Output ==="
echo "Searching for access/stat failures in $STRACE_OUT..."
# We look for ENOENT (No such file or directory) on paths containing 'e2b-storage'
# We filter out common noise like logs or cache if possible
grep "e2b-storage" "$STRACE_OUT" | grep "ENOENT" | head -n 20

echo "=== Done ==="
