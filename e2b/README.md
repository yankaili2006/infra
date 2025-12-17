# E2B Firecracker VM 集成

## 概述

E2B (e2b.dev) 是一个开源的AI代码解释基础设施，使用Firecracker微虚拟机技术提供安全隔离的执行环境。本项目集成了E2B，用于在pCloud项目中安全运行MCP服务。

## 目录结构

```
infra/e2b/
├── README.md                    # 本文档
├── DIRECTORY_STRUCTURE.md       # 目录结构说明
├── config/                      # 配置文件
│   ├── .env.e2b                 # E2B环境变量配置
│   ├── .env.e2b.example         # 环境变量配置示例
│   ├── docker-compose.e2b.yml   # Docker Compose配置
│   └── init.sql                 # 数据库初始化脚本
├── docs/                        # 文档
│   ├── e2b_complete_deployment_guide.md    # 完整部署指南
│   └── upgrade_for_e2b_deployment.md       # 升级指南
├── scripts/                     # 脚本文件
│   ├── check_e2b_requirements.sh           # 资源检查脚本
│   ├── manage_e2b.sh                       # E2B服务管理脚本
│   ├── quick_start.sh                      # 快速启动脚本
│   └── start_e2b_service.sh                # 服务启动脚本
└── examples/                    # 示例代码
    ├── create_e2b_vm.py                    # Python VM创建示例
    ├── create_e2b_vm_fixed.py              # 修复版Python示例
    ├── test_e2b_simple.py                  # 简单测试脚本
    └── test_e2b.py                         # 完整测试脚本
```

详细目录结构说明请参考: [DIRECTORY_STRUCTURE.md](DIRECTORY_STRUCTURE.md)

## 快速开始

### 选项A: 使用快速启动脚本 (推荐)
```bash
cd /root/pcloud/infra/e2b
bash scripts/quick_start.sh
```

### 选项B: 分步部署

#### 1. 初始化配置
```bash
cd /root/pcloud/infra/e2b

# 复制配置文件
cp config/.env.e2b.example config/.env.e2b

# 编辑配置 (修改密码和API密钥)
vim config/.env.e2b
```

#### 2. 检查系统要求
```bash
bash scripts/check_e2b_requirements.sh
```

#### 3. 启动E2B服务
```bash
# 使用管理脚本启动
bash scripts/manage_e2b.sh start

# 或使用简化脚本
bash scripts/start_e2b_service.sh
```

#### 4. 创建虚拟机
```bash
# 使用Python示例
cd examples
source ../../e2b-venv/bin/activate
python create_e2b_vm_fixed.py

# 或使用Docker容器
bash ../../create_simple_vm.sh
```

## 系统要求

### 最低配置
- **内存**: 8GB
- **CPU**: 4核心
- **存储**: 50GB SSD
- **KVM**: 已启用

### 推荐配置
- **内存**: 16GB+
- **CPU**: 8核心+
- **存储**: 100GB+ NVMe SSD
- **网络**: 千兆以太网

## 部署选项

### 选项A: 完整部署 (推荐)
适用于生产环境，需要16GB+内存：
```bash
# 参考完整部署指南
cat docs/e2b_complete_deployment_guide.md
```

### 选项B: 轻量级部署
适用于开发和测试环境：
```bash
# 使用Docker容器作为轻量级VM
bash ../../create_simple_vm.sh
```

### 选项C: 简化部署
使用现有脚本快速启动：
```bash
bash scripts/start_e2b_service.sh
```

## 配置说明

### 环境变量
编辑 `config/.env.e2b` 文件配置E2B：

```bash
# E2B API配置
E2B_API_URL=http://localhost:3000
E2B_API_KEY=e2b_53ae1fed82754c17ad8077fbc8bcdd90

# 数据库配置
POSTGRES_HOST=localhost
POSTGRES_PORT=5432
POSTGRES_DB=e2b
POSTGRES_USER=postgres
POSTGRES_PASSWORD=postgres

# Redis配置
REDIS_HOST=localhost
REDIS_PORT=6379
```

### Docker Compose配置
完整的E2B服务栈包括：
- **PostgreSQL**: 数据库服务
- **Redis**: 缓存服务
- **E2B API**: 主API服务
- **E2B Client Proxy**: 客户端代理

## 使用示例

### Python SDK示例
```python
from e2b import Sandbox
import os

# 设置环境变量
os.environ["E2B_API_KEY"] = "your_api_key"
os.environ["E2B_API_URL"] = "http://localhost:3000"

# 创建Firecracker VM
sandbox = Sandbox.create(
    template="base",
    timeout=300,
    metadata={"name": "test-vm"}
)

# 执行代码
result = sandbox.run_code("echo 'Hello from E2B VM!'")

# 关闭VM
sandbox.close()
```

### Shell脚本示例
```bash
# 创建简单VM
bash ../../create_simple_vm.sh

# 检查VM状态
docker ps -f name=simple-vm

# 进入VM
docker exec -it simple-vm-$(date +%s) bash
```

## 监控和管理

### 使用管理脚本
```bash
cd /root/pcloud/infra/e2b

# 查看服务状态
bash scripts/manage_e2b.sh status

# 查看日志
bash scripts/manage_e2b.sh logs

# 健康检查
bash scripts/manage_e2b.sh health

# 备份数据
bash scripts/manage_e2b.sh backup

# 清理缓存
bash scripts/manage_e2b.sh cleanup
```

### 手动管理命令
```bash
# 检查所有服务
docker-compose -f config/docker-compose.e2b.yml ps

# 检查API健康
curl http://localhost:${E2B_API_PORT:-3000}/health

# 查看日志
docker-compose -f config/docker-compose.e2b.yml logs -f

# 查看系统资源
bash scripts/check_e2b_requirements.sh

# 监控Firecracker进程
ps aux | grep firecracker

# 查看Docker资源使用
docker stats
```

## 故障排除

### 常见问题

#### 1. KVM权限错误
```bash
# 解决方案
sudo chmod 666 /dev/kvm
sudo usermod -aG kvm $USER
# 重新登录使权限生效
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
sudo lsof -i :5432
sudo lsof -i :6379
```

#### 4. Docker镜像拉取失败
```bash
# 使用国内镜像源
# 编辑 /etc/docker/daemon.json
{
  "registry-mirrors": [
    "https://docker.mirrors.ustc.edu.cn",
    "https://hub-mirror.c.163.com"
  ]
}
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
# 调整TCP参数
sudo sysctl -w net.core.rmem_max=134217728
sudo sysctl -w net.core.wmem_max=134217728
```

### 3. 存储优化
```bash
# 使用SSD存储
sudo mkdir -p /opt/e2b-storage
sudo chmod 777 /opt/e2b-storage
```

## 安全建议

1. **API密钥管理**: 定期轮换API密钥
2. **网络隔离**: 使用私有网络和防火墙
3. **资源限制**: 为每个VM设置CPU/内存限制
4. **日志审计**: 启用详细日志记录
5. **定期更新**: 保持E2B组件更新

## 相关文档

- [完整部署指南](docs/e2b_complete_deployment_guide.md)
- [资源升级指南](docs/upgrade_for_e2b_deployment.md)
- [E2B官方文档](https://e2b.dev/docs)
- [Firecracker文档](https://github.com/firecracker-microvm/firecracker)

## 支持

- **问题反馈**: 查看故障排除章节
- **文档更新**: 提交PR到相关文档
- **紧急问题**: 检查服务日志

---

**版本**: 1.0  
**最后更新**: 2025-12-17  
**状态**: 生产就绪