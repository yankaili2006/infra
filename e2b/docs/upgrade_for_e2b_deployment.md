#!/bin/bash
# E2B完整部署快速启动脚本
# 需要: 16GB+内存, 8+核心CPU, 100GB+存储

set -e

echo "=========================================="
echo "E2B完整部署快速启动"
echo "=========================================="

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 检查系统资源
check_resources() {
    echo "1. 检查系统资源..."
    
    # 检查内存
    total_mem=$(free -g | awk '/^Mem:/{print $2}')
    if [ "$total_mem" -lt 16 ]; then
        echo -e "${RED}✗ 内存不足: ${total_mem}GB (需要16GB+)${NC}"
        return 1
    else
        echo -e "${GREEN}✓ 内存: ${total_mem}GB${NC}"
    fi
    
    # 检查CPU核心
    cpu_cores=$(nproc)
    if [ "$cpu_cores" -lt 4 ]; then
        echo -e "${YELLOW}⚠ CPU核心: ${cpu_cores} (推荐8+)${NC}"
    else
        echo -e "${GREEN}✓ CPU核心: ${cpu_cores}${NC}"
    fi
    
    # 检查存储
    free_space=$(df -h / | awk 'NR==2{print $4}')
    echo -e "${GREEN}✓ 可用存储: ${free_space}${NC}"
    
    # 检查KVM
    if [ -e /dev/kvm ]; then
        echo -e "${GREEN}✓ KVM已启用${NC}"
    else
        echo -e "${RED}✗ KVM未启用${NC}"
        return 1
    fi
    
    return 0
}

# 安装依赖
install_dependencies() {
    echo "2. 安装依赖..."
    
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
        wget \
        jq \
        python3 \
        python3-pip \
        nodejs \
        npm
    
    # 配置Docker
    sudo usermod -aG docker $USER
    sudo systemctl enable docker
    sudo systemctl start docker
}

# 配置内核
configure_kernel() {
    echo "3. 配置内核参数..."
    
    # 创建内核配置文件
    sudo tee /etc/sysctl.d/99-e2b-optimized.conf << 'EOF'
# 内存优化
vm.nr_hugepages = 4096
vm.swappiness = 10
vm.dirty_ratio = 10
vm.dirty_background_ratio = 5

# 网络优化
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 87380 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535

# 文件系统
fs.file-max = 2097152
fs.nr_open = 2097152
EOF
    
    sudo sysctl -p /etc/sysctl.d/99-e2b-optimized.conf
    
    # 启用KVM
    sudo modprobe kvm
    sudo modprobe kvm_intel 2>/dev/null || sudo modprobe kvm_amd
    sudo chmod 666 /dev/kvm
    sudo usermod -aG kvm $USER
}

# 创建存储目录
create_storage() {
    echo "4. 创建存储目录..."
    
    sudo mkdir -p /opt/e2b-storage/{templates,cache,data,logs}
    sudo chmod -R 777 /opt/e2b-storage
    
    # 创建符号链接
    ln -sf /opt/e2b-storage ~/e2b-storage
}

# 部署E2B服务
deploy_e2b() {
    echo "5. 部署E2B服务..."
    
    cd /root/pcloud
    
    # 生成API密钥
    API_KEY="e2b_$(openssl rand -hex 16)"
    
    # 创建docker-compose配置
    cat > docker-compose-e2b-full.yml << EOF
version: '3.8'

services:
  # PostgreSQL数据库
  postgres:
    image: postgres:15-alpine
    environment:
      POSTGRES_USER: e2b
      POSTGRES_PASSWORD: e2b_password_$(openssl rand -hex 8)
      POSTGRES_DB: e2b
    ports:
      - "5432:5432"
    volumes:
      - /opt/e2b-storage/data/postgres:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U e2b"]
      interval: 10s
      timeout: 5s
      retries: 5
    deploy:
      resources:
        limits:
          memory: 2G
          cpus: '1'

  # Redis缓存
  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    volumes:
      - /opt/e2b-storage/data/redis:/data
    command: redis-server --appendonly yes --maxmemory 1gb --maxmemory-policy allkeys-lru
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5
    deploy:
      resources:
        limits:
          memory: 1G
          cpus: '0.5'

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
      E2B_API_KEY: ${API_KEY}
      TEMPLATE_STORAGE_PATH: /templates
      SANDBOX_CACHE_PATH: /cache
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /dev/kvm:/dev/kvm
      - /opt/e2b-storage/templates:/templates
      - /opt/e2b-storage/cache:/cache
      - /opt/e2b-storage/logs:/logs
    cap_add:
      - NET_ADMIN
      - SYS_ADMIN
    devices:
      - /dev/kvm:/dev/kvm
      - /dev/net/tun:/dev/net/tun
    restart: unless-stopped
    deploy:
      resources:
        limits:
          memory: 4G
          cpus: '2'
        reservations:
          memory: 2G
          cpus: '1'

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
    deploy:
      resources:
        limits:
          memory: 1G
          cpus: '0.5'

  # 监控面板 (可选)
  grafana:
    image: grafana/grafana:latest
    ports:
      - "3001:3000"
    environment:
      GF_SECURITY_ADMIN_PASSWORD: admin
    volumes:
      - /opt/e2b-storage/data/grafana:/var/lib/grafana
    restart: unless-stopped

volumes:
  e2b_data:
    driver: local
EOF
    
    # 启动服务
    docker-compose -f docker-compose-e2b-full.yml up -d
    
    # 保存API密钥
    echo "API_KEY=${API_KEY}" > /opt/e2b-storage/api-key.env
    echo "API_URL=http://localhost:3000" >> /opt/e2b-storage/api-key.env
    
    echo -e "${GREEN}✓ API密钥已保存到: /opt/e2b-storage/api-key.env${NC}"
}

# 安装E2B CLI和SDK
install_tools() {
    echo "6. 安装E2B工具..."
    
    # 安装E2B CLI
    npm install -g @e2b/cli
    
    # 创建Python虚拟环境
    python3 -m venv /opt/e2b-storage/venv
    source /opt/e2b-storage/venv/bin/activate
    pip install e2b requests
    
    # 创建示例脚本
    cat > /opt/e2b-storage/examples/create_vm.py << 'EOF'
#!/usr/bin/env python3
import os
from e2b import Sandbox

# 加载API配置
with open('/opt/e2b-storage/api-key.env', 'r') as f:
    for line in f:
        if '=' in line:
            key, value = line.strip().split('=', 1)
            os.environ[key] = value

def main():
    print("创建E2B Firecracker VM...")
    
    try:
        # 创建沙箱
        sandbox = Sandbox.create(
            template="base",
            timeout=3600,
            metadata={
                "name": "production-vm",
                "created_by": "quick_start_script"
            }
        )
        
        print(f"✓ VM创建成功!")
        print(f"  ID: {sandbox.sandbox_id}")
        print(f"  主机名: {sandbox.hostname}")
        
        # 测试执行代码
        result = sandbox.run_code("""
echo "Hello from E2B Firecracker VM!"
echo "System info:"
uname -a
echo "Memory:"
free -h
""")
        
        print(f"输出:\n{result}")
        
        # 保持运行
        print("\nVM正在运行...")
        input("按Enter关闭VM...")
        
        sandbox.close()
        print("✓ VM已关闭")
        
    except Exception as e:
        print(f"✗ 错误: {e}")
        print("\n请确保:")
        print("1. E2B服务正在运行")
        print("2. 有可用的模板 (运行: e2b templates list)")

if __name__ == "__main__":
    main()
EOF
    
    chmod +x /opt/e2b-storage/examples/create_vm.py
}

# 创建管理脚本
create_management_scripts() {
    echo "7. 创建管理脚本..."
    
    # 健康检查脚本
    cat > /opt/e2b-storage/scripts/check_health.sh << 'EOF'
#!/bin/bash
echo "=== E2B服务健康检查 ==="
echo ""

# 检查Docker服务
echo "1. Docker服务:"
if systemctl is-active --quiet docker; then
    echo "   ✓ 运行中"
else
    echo "   ✗ 未运行"
fi

# 检查容器
echo "2. 容器状态:"
cd /root/pcloud
docker-compose -f docker-compose-e2b-full.yml ps

# 检查API
echo "3. API健康:"
if curl -s http://localhost:3000/health | grep -q "healthy"; then
    echo "   ✓ API健康"
else
    echo "   ✗ API异常"
fi

# 检查KVM
echo "4. KVM状态:"
if [ -e /dev/kvm ]; then
    echo "   ✓ KVM可用"
else
    echo "   ✗ KVM不可用"
fi

# 检查资源使用
echo "5. 资源使用:"
echo "   内存: $(free -h | awk '/^Mem:/{print $3"/"$2}")"
echo "   CPU: $(top -bn1 | grep "Cpu(s)" | awk '{print $2}')%"
echo "   存储: $(df -h /opt/e2b-storage | awk 'NR==2{print $3"/"$2}")"
EOF
    
    chmod +x /opt/e2b-storage/scripts/check_health.sh
    
    # 备份脚本
    cat > /opt/e2b-storage/scripts/backup.sh << 'EOF'
#!/bin/bash
BACKUP_DIR="/opt/e2b-storage/backups/$(date +%Y%m%d_%H%M%S)"
mkdir -p $BACKUP_DIR

echo "备份E2B数据到: $BACKUP_DIR"

# 备份数据库
docker-compose -f /root/pcloud/docker-compose-e2b-full.yml exec postgres pg_dump -U e2b e2b > $BACKUP_DIR/database.sql

# 备份配置
cp /root/pcloud/docker-compose-e2b-full.yml $BACKUP_DIR/
cp /opt/e2b-storage/api-key.env $BACKUP_DIR/

# 备份模板
tar -czf $BACKUP_DIR/templates.tar.gz /opt/e2b-storage/templates

echo "备份完成: $BACKUP_DIR"
ls -lh $BACKUP_DIR
EOF
    
    chmod +x /opt/e2b-storage/scripts/backup.sh
}

# 显示完成信息
show_completion() {
    echo ""
    echo "=========================================="
    echo -e "${GREEN}E2B完整部署完成！${NC}"
    echo "=========================================="
    echo ""
    echo "服务访问地址:"
    echo "  - E2B API:      http://localhost:3000"
    echo "  - API健康检查:  http://localhost:3000/health"
    echo "  - Client Proxy: http://localhost:3002"
    echo "  - Grafana:      http://localhost:3001 (admin/admin)"
    echo ""
    echo "管理命令:"
    echo "  # 查看服务状态"
    echo "  docker-compose -f /root/pcloud/docker-compose-e2b-full.yml ps"
    echo ""
    echo "  # 查看日志"
    echo "  docker-compose -f /root/pcloud/docker-compose-e2b-full.yml logs -f"
    echo ""
    echo "  # 健康检查"
    echo "  /opt/e2b-storage/scripts/check_health.sh"
    echo ""
    echo "  # 创建VM示例"
    echo "  source /opt/e2b-storage/venv/bin/activate"
    echo "  python /opt/e2b-storage/examples/create_vm.py"
    echo ""
    echo "API密钥已保存到: /opt/e2b-storage/api-key.env"
    echo ""
    echo "下一步:"
    echo "  1. 等待服务完全启动 (约1-2分钟)"
    echo "  2. 创建基础模板: e2b templates build -t base"
    echo "  3. 测试创建VM"
    echo ""
    echo "如需帮助，查看文档:"
    echo "  https://e2b.dev/docs"
    echo "  /opt/e2b-storage/ 目录下的示例脚本"
}

# 主函数
main() {
    echo "开始E2B完整部署..."
    echo ""
    
    # 检查资源
    if ! check_resources; then
        echo -e "${RED}系统资源不满足E2B完整部署要求${NC}"
        echo "请参考升级建议文档"
        exit 1
    fi
    
    # 执行部署步骤
    install_dependencies
    configure_kernel
    create_storage
    deploy_e2b
    install_tools
    create_management_scripts
    show_completion
    
    echo ""
    echo -e "${GREEN}部署完成！现在可以开始使用E2B Firecracker VM了。${NC}"
}

# 执行主函数
main "$@"