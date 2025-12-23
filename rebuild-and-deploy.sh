#!/bin/bash
# E2B 修复部署脚本 - 重新构建并部署API和Orchestrator

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "======================================================"
echo "  E2B 修复部署脚本"
echo "======================================================"
echo ""
echo "本脚本将重新构建并部署以下服务:"
echo "  1. API服务 (修复500响应问题)"
echo "  2. Orchestrator服务 (添加socat支持)"
echo ""

cd "$PROJECT_ROOT/infra"

echo "[1/4] 重新构建Go二进制文件..."

# Set GOPROXY to avoid network issues
export GOPROXY=https://goproxy.cn,direct
export CGO_ENABLED=1
export GOOS=linux
export GOARCH=amd64

# Sync workspace first
echo "  → 同步Go workspace..."
go work sync || echo "  ⚠ Workspace同步失败（可能没有go.work）"

cd packages

# Build API using docker build
echo "  → 构建API镜像..."
cd ..
docker build \
  --build-arg HTTP_PROXY="" \
  --build-arg HTTPS_PROXY="" \
  --build-arg NO_PROXY="localhost,127.0.0.1" \
  --build-arg GOPROXY="https://goproxy.cn,direct" \
  -t local-e2b-api:latest \
  -f packages/api/Dockerfile \
  packages || {
  echo "  ✗ API镜像构建失败"
  exit 1
}
echo "  ✓ API镜像构建完成"

# Build Orchestrator using docker build
echo "  → 构建Orchestrator镜像..."
docker build \
  --build-arg HTTP_PROXY="" \
  --build-arg HTTPS_PROXY="" \
  --build-arg NO_PROXY="localhost,127.0.0.1" \
  --build-arg GOPROXY="https://goproxy.cn,direct" \
  -t local-e2b-orchestrator:latest \
  -f packages/orchestrator/Dockerfile \
  packages || {
  echo "  ✗ Orchestrator镜像构建失败"
  exit 1
}
echo "  ✓ Orchestrator镜像构建完成"

cd ..

echo ""
echo "[2/4] 镜像已在步骤1中构建完成"
echo ""

echo ""
echo "[3/4] 停止旧服务..."

# Stop and remove old jobs
echo "  → 停止API服务..."
nomad job stop -purge api 2>/dev/null || echo "  API服务未运行"

echo "  → 停止Orchestrator服务..."
nomad job stop -purge orchestrator 2>/dev/null || echo "  Orchestrator服务未运行"

# Wait for jobs to stop
echo "  → 等待服务完全停止..."
sleep 5

echo ""
echo "[4/4] 部署新服务..."

# Deploy API
echo "  → 部署API服务..."
nomad job run local-deploy/nomad-jobs/api.nomad.hcl || {
  echo "  ✗ API服务部署失败"
  exit 1
}
echo "  ✓ API服务已部署"

# Deploy Orchestrator
echo "  → 部署Orchestrator服务..."
nomad job run local-deploy/nomad-jobs/orchestrator.nomad.hcl || {
  echo "  ✗ Orchestrator服务部署失败"
  exit 1
}
echo "  ✓ Orchestrator服务已部署"

echo ""
echo "======================================================"
echo "  等待服务启动..."
echo "======================================================"

# Wait for services to be ready
echo ""
echo "等待API服务启动..."
for i in {1..30}; do
  if curl -s http://localhost:3000/health > /dev/null 2>&1; then
    echo "✓ API服务已就绪"
    break
  fi
  echo -n "."
  sleep 2
done
echo ""

echo ""
echo "等待Orchestrator服务启动..."
for i in {1..30}; do
  if nomad job status orchestrator 2>&1 | grep -q "running"; then
    echo "✓ Orchestrator服务已就绪"
    break
  fi
  echo -n "."
  sleep 2
done
echo ""

echo ""
echo "======================================================"
echo "  部署完成！"
echo "======================================================"
echo ""
echo "修复内容:"
echo "  ✓ API 500响应问题已修复 (移除双重指针)"
echo "  ✓ Orchestrator socat已安装"
echo ""
echo "验证命令:"
echo "  # 测试API健康检查"
echo "  curl http://localhost:3000/health"
echo ""
echo "  # 创建测试沙箱"
echo "  curl -X POST http://localhost:3000/sandboxes \\"
echo "    -H 'X-API-Key: e2b_53ae1fed82754c17ad8077fbc8bcdd90' \\"
echo "    -H 'Content-Type: application/json' \\"
echo "    -d '{\"templateID\":\"base\",\"timeout\":300}'"
echo ""
echo "  # 查看Orchestrator日志"
echo "  nomad alloc logs \$(nomad job allocs orchestrator | grep running | awk '{print \$1}')"
echo ""
