#!/bin/bash
# 启动E2B服务的简化脚本

set -e

echo "=========================================="
echo "启动E2B完整部署"
echo "=========================================="

# 检查Docker
if ! command -v docker &> /dev/null; then
    echo "错误: Docker未安装"
    exit 1
fi

# 检查KVM
if [ ! -e /dev/kvm ]; then
    echo "警告: /dev/kvm不存在，KVM可能未启用"
fi

# 创建存储目录
echo "1. 创建存储目录..."
mkdir -p /tmp/e2b-template-storage /tmp/e2b-template-cache /tmp/e2b-sandbox-cache
chmod 777 /tmp/e2b-*

# 创建Docker Compose文件
echo "2. 创建Docker Compose配置..."
cat > /tmp/e2b-docker-compose.yml << 'EOF'
version: '3.8'
services:
  # PostgreSQL数据库
  postgres:
    image: postgres:15-alpine
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: e2b
    ports:
      - "5432:5432"
    volumes:
      - e2b_postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 10s
      timeout: 5s
      retries: 5

  # Redis缓存
  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    volumes:
      - e2b_redis_data:/data
    command: redis-server --appendonly yes
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

  # E2B API服务
  e2b-api:
    image: e2bdev/api:latest
    ports:
      - "3000:3000"
    environment:
      DATABASE_URL: postgresql://postgres:postgres@postgres:5432/e2b
      REDIS_URL: redis://redis:6379/0
      NODE_ENV: development
      LOG_LEVEL: debug
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    volumes:
      - /tmp/e2b-template-storage:/tmp/e2b-template-storage
      - /tmp/e2b-template-cache:/tmp/e2b-template-cache
      - /tmp/e2b-sandbox-cache:/tmp/e2b-sandbox-cache
    cap_add:
      - NET_ADMIN
      - SYS_ADMIN
    devices:
      - /dev/kvm:/dev/kvm
      - /dev/net/tun:/dev/net/tun
    restart: unless-stopped

  # E2B Client Proxy
  e2b-client-proxy:
    image: e2bdev/client-proxy:latest
    ports:
      - "3002:3002"
    environment:
      API_URL: http://e2b-api:3000
      REDIS_URL: redis://redis:6379/0
    depends_on:
      - e2b-api
      - redis
    restart: unless-stopped

volumes:
  e2b_postgres_data:
  e2b_redis_data:
EOF

echo "✓ Docker Compose配置已创建: /tmp/e2b-docker-compose.yml"

# 下载E2B镜像
echo "3. 下载E2B镜像..."
echo "   这可能需要一些时间..."
docker pull e2bdev/api:latest || echo "警告: 无法下载e2bdev/api:latest镜像"
docker pull e2bdev/client-proxy:latest || echo "警告: 无法下载e2bdev/client-proxy:latest镜像"

# 启动服务
echo "4. 启动E2B服务..."
cd /tmp
docker compose -f e2b-docker-compose.yml up -d

# 等待服务启动
echo "5. 等待服务启动..."
sleep 10

# 检查服务状态
echo "6. 检查服务状态..."
docker compose -f e2b-docker-compose.yml ps

echo ""
echo "=========================================="
echo "E2B部署完成！"
echo "=========================================="
echo ""
echo "服务访问地址:"
echo "  - E2B API: http://localhost:3000"
echo "  - API健康检查: http://localhost:3000/health"
echo "  - Client Proxy: http://localhost:3002"
echo ""
echo "管理命令:"
echo "  - 查看日志: docker compose -f /tmp/e2b-docker-compose.yml logs -f"
echo "  - 停止服务: docker compose -f /tmp/e2b-docker-compose.yml down"
echo "  - 重启服务: docker compose -f /tmp/e2b-docker-compose.yml restart"
echo ""
echo "测试E2B SDK:"
echo "  source /root/pcloud/e2b-venv/bin/activate"
echo "  python3 -c \"from e2b import Sandbox; print('E2B SDK可用')\""
echo ""
echo "注意: 如果镜像下载失败，可能需要构建本地镜像"
echo "      或者检查网络连接"