# E2B完整部署指南

## 概述
E2B (e2b.dev) 是一个开源的AI代码解释基础设施，使用Firecracker微虚拟机技术提供安全隔离的执行环境。

## 系统要求

### 硬件要求
```bash
# 检查当前系统资源
free -h        # 内存
nproc          # CPU核心数
df -h          # 磁盘空间
lsmod | grep kvm  # KVM支持
```

### 软件要求
```bash
# 必需软件包
sudo apt-get update
sudo apt-get install -y \
  docker.io \
  docker-compose \
  qemu-kvm \
  libvirt-daemon-system \
  libvirt-clients \
  bridge-utils \
  virt-manager \
  make \
  golang \
  git \
  curl \
  wget
```

## 完整部署步骤

### 1. 准备环境
```bash
# 启用KVM
sudo modprobe kvm
sudo modprobe kvm_intel  # Intel CPU
# 或 sudo modprobe kvm_amd  # AMD CPU

# 检查KVM
ls -l /dev/kvm
sudo usermod -aG kvm $USER
sudo usermod -aG docker $USER

# 重新登录使组权限生效
newgrp kvm
newgrp docker
```

### 2. 配置内核参数
```bash
# 创建内核配置文件
sudo tee /etc/sysctl.d/99-e2b.conf << EOF
vm.nr_hugepages = 2048
vm.max_map_count = 262144
fs.file-max = 2097152
net.core.somaxconn = 1024
net.ipv4.tcp_max_syn_backlog = 1024
EOF

# 应用配置
sudo sysctl -p /etc/sysctl.d/99-e2b.conf
```

### 3. 部署E2B基础设施

#### 选项A: 使用Docker Compose（推荐）
```bash
cd /root/pcloud

# 创建docker-compose.yml
cat > docker-compose-e2b.yml << 'EOF'
version: '3.8'

services:
  # PostgreSQL数据库
  postgres:
    image: postgres:15-alpine
    environment:
      POSTGRES_USER: e2b
      POSTGRES_PASSWORD: e2b_password
      POSTGRES_DB: e2b
    ports:
      - "5432:5432"
    volumes:
      - e2b_postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U e2b"]
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
    image: ghcr.io/e2b-dev/api:latest
    ports:
      - "3000:3000"
    environment:
      DATABASE_URL: postgresql://e2b:e2b_password@postgres:5432/e2b
      REDIS_URL: redis://redis:6379/0
      NODE_ENV: production
      LOG_LEVEL: info
      E2B_API_KEY: e2b_$(openssl rand -hex 16)
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /dev/kvm:/dev/kvm
    cap_add:
      - NET_ADMIN
      - SYS_ADMIN
    devices:
      - /dev/kvm:/dev/kvm
      - /dev/net/tun:/dev/net/tun
    restart: unless-stopped

  # E2B Client Proxy
  e2b-client-proxy:
    image: ghcr.io/e2b-dev/client-proxy:latest
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

# 启动服务
docker-compose -f docker-compose-e2b.yml up -d
```

#### 选项B: 使用Kubernetes
```bash
# 创建Kubernetes部署文件
cat > e2b-k8s.yaml << 'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: e2b
---
apiVersion: v1
kind: Secret
metadata:
  name: e2b-secrets
  namespace: e2b
type: Opaque
data:
  database-url: cG9zdGdyZXNxbDovL2UyYjplMmJfcGFzc3dvcmRAcG9zdGdyZXM6NTQzMi9lMmI=
  redis-url: cmVkaXM6Ly9yZWRpczo2Mzc5LzA=
  api-key: ZTJiXyQob3BlbnNzbCByYW5kIC1oZXggMTYp
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: e2b-api
  namespace: e2b
spec:
  replicas: 2
  selector:
    matchLabels:
      app: e2b-api
  template:
    metadata:
      labels:
        app: e2b-api
    spec:
      containers:
      - name: e2b-api
        image: ghcr.io/e2b-dev/api:latest
        env:
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: e2b-secrets
              key: database-url
        - name: REDIS_URL
          valueFrom:
            secretKeyRef:
              name: e2b-secrets
              key: redis-url
        - name: E2B_API_KEY
          valueFrom:
            secretKeyRef:
              name: e2b-secrets
              key: api-key
        ports:
        - containerPort: 3000
        securityContext:
          privileged: true
          capabilities:
            add: ["NET_ADMIN", "SYS_ADMIN"]
        volumeMounts:
        - name: kvm
          mountPath: /dev/kvm
        - name: tun
          mountPath: /dev/net/tun
      volumes:
      - name: kvm
        hostPath:
          path: /dev/kvm
      - name: tun
        hostPath:
          path: /dev/net/tun
---
apiVersion: v1
kind: Service
metadata:
  name: e2b-api
  namespace: e2b
spec:
  selector:
    app: e2b-api
  ports:
  - port: 3000
    targetPort: 3000
  type: LoadBalancer
EOF

# 部署到Kubernetes
kubectl apply -f e2b-k8s.yaml
```

### 4. 验证部署
```bash
# 检查服务状态
docker-compose -f docker-compose-e2b.yml ps

# 测试API
curl http://localhost:3000/health

# 检查日志
docker-compose -f docker-compose-e2b.yml logs -f
```

### 5. 创建Firecracker VM模板
```bash
# 安装E2B CLI
npm install -g @e2b/cli

# 登录到E2B
e2b login --api-key $(docker-compose -f docker-compose-e2b.yml exec e2b-api printenv E2B_API_KEY)

# 创建基础模板
cat > Dockerfile.base << 'EOF'
FROM ubuntu:22.04

RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    nodejs \
    npm \
    curl \
    wget \
    git \
    vim \
    && rm -rf /var/lib/apt/lists/*

# 设置工作目录
WORKDIR /workspace

# 设置默认命令
CMD ["/bin/bash"]
EOF

# 构建模板
e2b templates build -f Dockerfile.base -t base
```

### 6. 使用Python SDK创建VM
```python
import os
from e2b import Sandbox

# 设置环境变量
os.environ["E2B_API_KEY"] = "your_api_key_here"
os.environ["E2B_API_URL"] = "http://localhost:3000"

# 创建Firecracker VM
sandbox = Sandbox.create(
    template="base",
    timeout=3600,  # 1小时超时
    metadata={
        "name": "production-vm",
        "purpose": "code-execution"
    }
)

print(f"VM ID: {sandbox.sandbox_id}")
print(f"Hostname: {sandbox.hostname}")

# 执行代码
result = sandbox.run_code("""
import platform
print(f"Python version: {platform.python_version()}")
print(f"System: {platform.system()} {platform.release()}")
""")

print(f"Output: {result}")

# 上传文件
sandbox.upload_file("local_script.py", "/workspace/script.py")

# 下载文件
sandbox.download_file("/workspace/output.txt", "local_output.txt")

# 保持运行
sandbox.keep_alive(300)  # 保持5分钟活跃

# 关闭VM
sandbox.close()
```

### 7. 监控和管理

#### 监控面板
```bash
# 安装监控工具
docker run -d \
  --name=grafana \
  -p 3001:3000 \
  grafana/grafana

# 访问监控: http://localhost:3001
```

#### 健康检查脚本
```bash
cat > check_e2b_health.sh << 'EOF'
#!/bin/bash

# 检查服务
services=("postgres" "redis" "e2b-api" "e2b-client-proxy")
for service in "${services[@]}"; do
    if docker-compose -f docker-compose-e2b.yml ps $service | grep -q "Up"; then
        echo "✓ $service is running"
    else
        echo "✗ $service is not running"
    fi
done

# 检查API
if curl -s http://localhost:3000/health | grep -q "healthy"; then
    echo "✓ API is healthy"
else
    echo "✗ API is not healthy"
fi

# 检查Firecracker
if ps aux | grep -q "[f]irecracker"; then
    echo "✓ Firecracker processes running"
else
    echo "✗ No Firecracker processes"
fi
EOF

chmod +x check_e2b_health.sh
./check_e2b_health.sh
```

## 性能优化

### 1. 内存优化
```bash
# 调整Hugepages
sudo sysctl -w vm.nr_hugepages=4096

# 调整Swappiness
sudo sysctl -w vm.swappiness=10
```

### 2. 网络优化
```bash
# 调整网络参数
sudo sysctl -w net.core.rmem_max=134217728
sudo sysctl -w net.core.wmem_max=134217728
sudo sysctl -w net.ipv4.tcp_rmem="4096 87380 134217728"
sudo sysctl -w net.ipv4.tcp_wmem="4096 65536 134217728"
```

### 3. 存储优化
```bash
# 使用SSD/NVMe存储
sudo mkdir -p /opt/e2b-storage
sudo chmod 777 /opt/e2b-storage

# 在docker-compose中添加卷映射
volumes:
  - /opt/e2b-storage/templates:/templates
  - /opt/e2b-storage/cache:/cache
```

## 故障排除

### 常见问题

#### 1. KVM权限错误
```bash
# 解决方案
sudo chmod 666 /dev/kvm
sudo usermod -aG kvm $USER
# 重新登录
```

#### 2. 内存不足
```bash
# 增加交换空间
sudo fallocate -l 8G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
```

#### 3. 端口冲突
```bash
# 检查占用端口的进程
sudo lsof -i :3000
# 修改docker-compose中的端口映射
```

#### 4. 模板构建失败
```bash
# 清理缓存
docker system prune -a
# 重新构建
e2b templates build --no-cache -f Dockerfile.base -t base
```

## 扩展部署

### 多节点集群
```bash
# 使用Nomad进行集群管理
# 安装Nomad
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
sudo apt-get update && sudo apt-get install nomad

# 配置Nomad集群
# 参考: https://www.nomadproject.io/docs/installation
```

### 负载均衡
```bash
# 使用Nginx作为负载均衡器
docker run -d \
  --name=nginx-lb \
  -p 80:80 \
  -v $(pwd)/nginx.conf:/etc/nginx/nginx.conf \
  nginx:alpine
```

## 安全建议

1. **API密钥管理**: 使用密钥管理服务（如Vault）
2. **网络隔离**: 使用私有网络和防火墙规则
3. **资源限制**: 为每个VM设置CPU/内存限制
4. **日志审计**: 启用详细日志记录和监控
5. **定期更新**: 保持E2B组件和依赖项更新

## 生产部署检查清单

- [ ] 系统资源满足要求（16GB+内存，8+核心CPU）
- [ ] KVM已启用并配置正确权限
- [ ] 防火墙规则已配置
- [ ] 监控和告警已设置
- [ ] 备份策略已实施
- [ ] 安全审计已完成
- [ ] 性能测试已通过
- [ ] 灾难恢复计划已制定

## 支持资源

- **官方文档**: https://e2b.dev/docs
- **GitHub仓库**: https://github.com/e2b-dev/e2b
- **社区支持**: Discord社区
- **问题反馈**: GitHub Issues

---

**最后更新**: 2025-12-17  
**版本**: 1.0  
**状态**: 生产就绪