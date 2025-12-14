#!/bin/bash
# 直接使用 Docker 运行 E2B API (绕过 Nomad 的镜像拉取问题)

set -e

echo "=== 启动 E2B API 服务 ==="

# 停止并删除旧容器
docker stop e2b-api 2>/dev/null || true
docker rm e2b-api 2>/dev/null || true

# 运行 DB Migrator (一次性任务)
echo "运行数据库迁移..."
docker run --rm \
  --pull=never \
  --network host \
  -e POSTGRES_CONNECTION_STRING="postgres://postgres:postgres@127.0.0.1:5432/postgres?sslmode=disable" \
  e2b-db-migrator:local

echo "数据库迁移完成"

# 启动 API 服务
echo "启动 API 服务..."
docker run -d \
  --pull=never \
  --name e2b-api \
  --network host \
  --restart unless-stopped \
  -e NODE_ID="local-dev" \
  -e ENVIRONMENT="local" \
  -e POSTGRES_CONNECTION_STRING="postgres://postgres:postgres@127.0.0.1:5432/postgres?sslmode=disable" \
  -e CLICKHOUSE_CONNECTION_STRING="clickhouse://clickhouse:clickhouse@127.0.0.1:9000/clickhouse" \
  -e REDIS_URL="127.0.0.1:6379" \
  -e REDIS_CLUSTER_URL="" \
  -e REDIS_TLS_CA_BASE64="" \
  -e OTEL_COLLECTOR_GRPC_ENDPOINT="127.0.0.1:4317" \
  -e LOGS_COLLECTOR_ADDRESS="http://127.0.0.1:30006" \
  -e OTEL_TRACING_PRINT="false" \
  -e NOMAD_TOKEN="" \
  -e NOMAD_ADDR="http://127.0.0.1:4646" \
  -e CONSUL_HTTP_ADDR="127.0.0.1:8500" \
  -e PORT="3000" \
  -e ORCHESTRATOR_PORT="5008" \
  -e LOCAL_CLUSTER_ENDPOINT="127.0.0.1:3001" \
  -e LOCAL_CLUSTER_TOKEN="--edge-secret--" \
  -e POSTHOG_API_KEY="" \
  -e ANALYTICS_COLLECTOR_HOST="" \
  -e ANALYTICS_COLLECTOR_API_TOKEN="" \
  -e LAUNCH_DARKLY_API_KEY="" \
  -e ADMIN_TOKEN="local-admin-token" \
  -e ACCESS_TOKEN_SEED_KEY="--access-token-seed-key--" \
  -e SANDBOX_ACCESS_TOKEN_HASH_SEED="--sandbox-access-token-hash-seed--" \
  -e SUPABASE_JWT_SECRETS="test-jwt-secret" \
  -e TEMPLATE_BUCKET_NAME="skip" \
  -e DEFAULT_KERNEL_VERSION="vmlinux-6.1.158" \
  -e DEFAULT_FIRECRACKER_VERSION="v1.12.1_d990331" \
  e2b-api:local \
  --port 3000

echo ""
echo "✓ API 服务已启动"
echo ""
echo "服务信息:"
echo "  容器名称: e2b-api"
echo "  监听端口: 3000"
echo "  状态: $(docker inspect -f '{{.State.Status}}' e2b-api 2>/dev/null || echo '未知')"
echo ""
echo "查看日志:"
echo "  docker logs -f e2b-api"
echo ""
echo "测试 API:"
echo "  curl -X POST http://localhost:3000/sandboxes \\"
echo "    -H 'Content-Type: application/json' \\"
echo "    -H 'X-API-Key: e2b_53ae1fed82754c17ad8077fbc8bcdd90' \\"
echo "    -d '{\"templateID\": \"base\"}'"
echo ""
