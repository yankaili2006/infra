#!/bin/bash
# API Wrapper Script - 使用环境变量替代硬编码路径

# 设置PCLOUD_HOME环境变量（如果未设置）
export PCLOUD_HOME="${PCLOUD_HOME:-/mnt/data1/pcloud}"

# 导出所有需要的环境变量
export POSTGRES_CONNECTION_STRING="postgres://postgres:postgres@127.0.0.1:5432/e2b?sslmode=disable&connect_timeout=30"
export CLICKHOUSE_CONNECTION_STRING="clickhouse://clickhouse:clickhouse@127.0.0.1:9000/clickhouse"
export REDIS_URL="127.0.0.1:6379"
export REDIS_CLUSTER_URL=""
export REDIS_TLS_CA_BASE64=""
export OTEL_COLLECTOR_GRPC_ENDPOINT="127.0.0.1:4317"
export LOGS_COLLECTOR_ADDRESS="http://127.0.0.1:30006"
export OTEL_TRACING_PRINT="false"
export NOMAD_TOKEN=""
export ORCHESTRATOR_PORT="5008"
export ORCHESTRATOR_URL="localhost:5008"
export LOCAL_CLUSTER_ENDPOINT=""
export LOCAL_CLUSTER_TOKEN=""
export POSTHOG_API_KEY=""
export ANALYTICS_COLLECTOR_HOST=""
export ANALYTICS_COLLECTOR_API_TOKEN=""
export LAUNCH_DARKLY_API_KEY=""
export ADMIN_TOKEN="local-admin-token"
export SANDBOX_ACCESS_TOKEN_HASH_SEED="local-sandbox-seed-key-for-development"
export SUPABASE_JWT_SECRETS="test-jwt-secret"
export TEMPLATE_BUCKET_NAME="skip"
export STORAGE_PROVIDER="Local"
export ARTIFACTS_REGISTRY_PROVIDER="Local"
export LOCAL_TEMPLATE_STORAGE_BASE_PATH="${PCLOUD_HOME}/e2b-storage/e2b-template-storage"
export BUILD_CACHE_BUCKET_NAME="${PCLOUD_HOME}/e2b-storage/e2b-build-cache"
export TEMPLATE_CACHE_DIR="${PCLOUD_HOME}/e2b-storage/e2b-template-cache"
export DEFAULT_KERNEL_VERSION="vmlinux-6.1.158"
export DEFAULT_FIRECRACKER_VERSION="v1.12.1_d990331"
export NODE_ID="${NODE_ID}"
export ENVIRONMENT="local"

# 启动API
exec "${PCLOUD_HOME}/infra/packages/api/bin/api" --port 3000
