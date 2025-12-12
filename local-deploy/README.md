# E2B 本地部署指南

欢迎使用 E2B 本地部署！本文档将指导您在本地 Linux 机器上部署完整的 E2B 基础设施，无需任何云服务依赖。

## 目录

- [快速开始](#快速开始)
- [架构概述](#架构概述)
- [系统要求](#系统要求)
- [安装步骤](#安装步骤)
- [使用指南](#使用指南)
- [故障排除](#故障排除)
- [常见问题](#常见问题)
- [高级配置](#高级配置)

## 快速开始

如果您的系统已满足基本要求，可以使用一键部署：

```bash
cd /home/primihub/pcloud/infra/local-deploy
bash scripts/00-init-all.sh
bash scripts/start-all.sh
```

然后访问 http://localhost:80 查看部署状态。

## 架构概述

E2B 本地部署采用混合架构，分为四个层次：

```
┌─────────────────────────────────────────┐
│  Nginx (端口 80)                        │
│  反向代理 & 入口点                       │
└─────────────────────────────────────────┘
                  ↓
┌─────────────────────────────────────────┐
│  Nomad (端口 4646)                      │
│  作业调度层                             │
│  ├─ API (Docker)                        │
│  ├─ Client-Proxy (Docker)               │
│  ├─ Orchestrator (raw_exec)             │
│  └─ Template-Manager (raw_exec)         │
└─────────────────────────────────────────┘
                  ↓
┌─────────────────────────────────────────┐
│  Consul (端口 8500)                     │
│  服务发现 & 健康检查                     │
└─────────────────────────────────────────┘
                  ↓
┌─────────────────────────────────────────┐
│  Docker Compose                         │
│  基础设施层                             │
│  ├─ PostgreSQL (5432)                   │
│  ├─ Redis (6379)                        │
│  ├─ ClickHouse (9000)                   │
│  └─ Grafana Stack (Loki, Tempo, Mimir)  │
└─────────────────────────────────────────┘
                  ↓
┌─────────────────────────────────────────┐
│  Firecracker MicroVMs                   │
│  沙箱执行环境                           │
└─────────────────────────────────────────┘
```

### 关键组件

- **API**: REST API 服务，处理用户请求
- **Orchestrator**: 管理 Firecracker microVMs
- **Template Manager**: 构建和管理沙箱模板
- **Client Proxy**: 处理沙箱连接和 WebSocket 通信
- **PostgreSQL**: 主数据库
- **Redis**: 缓存和会话存储
- **ClickHouse**: 分析数据库
- **Grafana**: 可观测性平台

## 系统要求

### 硬件要求

| 资源 | 最低配置 | 推荐配置 |
|-----|---------|---------|
| CPU | 4 核心 | 8+ 核心 |
| 内存 | 8 GB | 16+ GB |
| 磁盘 | 50 GB | 100+ GB SSD |
| 网络 | 有线连接 | 千兆网卡 |

### 软件要求

- **操作系统**: Linux (Ubuntu 20.04/22.04 推荐)
- **内核**: >= 4.14 (支持 KVM)
- **CPU**: 必须支持硬件虚拟化 (Intel VT-x 或 AMD-V)
- **权限**: sudo 权限

### 端口要求

以下端口需要可用：

| 端口 | 服务 | 协议 |
|-----|------|------|
| 80 | Nginx | HTTP |
| 3000 | API | HTTP |
| 3002 | Client Proxy | HTTP/WS |
| 4646-4648 | Nomad | HTTP/RPC |
| 5007-5009 | Orchestrator | gRPC/HTTP |
| 5432 | PostgreSQL | TCP |
| 6379 | Redis | TCP |
| 8500 | Consul | HTTP |
| 9000 | ClickHouse | TCP |
| 53000 | Grafana | HTTP |

## 安装步骤

### 1. 准备工作

确保系统满足要求：

```bash
cd /home/primihub/pcloud/infra/local-deploy
bash scripts/01-check-requirements.sh
```

### 2. 安装依赖

安装 Docker、Go、Make 等必需软件：

```bash
sudo bash scripts/02-install-deps.sh
```

**重要**: 安装后需要重新登录以使组权限生效！

### 3. 配置内核

加载 KVM 和 NBD 模块，配置 Hugepages：

```bash
sudo bash scripts/03-setup-kernel.sh
```

### 4. 配置权限

为 Firecracker 配置权限（选择 A 使用 capabilities 或 B 使用 sudo）：

```bash
sudo bash scripts/04-setup-sudo.sh
```

推荐选择 **选项 A (Capabilities)**，更安全。

### 5. 创建存储目录

创建所有必需的存储目录：

```bash
sudo bash scripts/05-setup-storage.sh
```

### 6. 构建二进制文件

构建 Orchestrator 和 Envd：

```bash
bash scripts/06-build-binaries.sh
```

这一步可能需要 10-20 分钟。

### 7. 构建 Docker 镜像

构建 API、Client-Proxy、DB-Migrator 镜像：

```bash
bash scripts/07-build-images.sh
```

这一步可能需要 10-20 分钟。

### 8. 安装 Nomad & Consul

安装 HashiCorp 工具：

```bash
sudo bash scripts/08-install-nomad-consul.sh
```

### 9. 初始化数据库

启动基础设施并运行数据库迁移：

```bash
bash scripts/09-init-database.sh
```

## 使用指南

### 启动服务

#### 一键启动所有服务

```bash
bash scripts/start-all.sh
```

这将依次启动：
1. 基础设施 (Docker Compose)
2. Consul
3. Nomad
4. Nomad Jobs (API, Orchestrator, etc.)

#### 分步启动

```bash
# 1. 启动基础设施
bash scripts/start-infra.sh

# 2. 启动 Consul
bash scripts/start-consul.sh

# 3. 启动 Nomad
bash scripts/start-nomad.sh

# 4. 部署 Jobs
bash scripts/deploy-all-jobs.sh
```

### 验证部署

运行验证脚本检查所有服务状态：

```bash
bash scripts/verify-deployment.sh
```

### 访问服务

部署成功后，可以通过以下地址访问各个服务：

- **主页 (Nginx)**: http://localhost:80
- **API**: http://localhost:3000
  - 健康检查: http://localhost:3000/health
- **Grafana**: http://localhost:53000
- **Nomad UI**: http://localhost:4646/ui
- **Consul UI**: http://localhost:8500/ui

### 停止服务

```bash
bash scripts/stop-all.sh
```

### 清理数据

清理缓存和临时文件：

```bash
bash scripts/cleanup.sh
```

**注意**: 此操作会删除缓存，但保留模板存储和数据库。

## 故障排除

### 常见问题

#### 1. Firecracker 权限错误

**错误**: `Permission denied` 访问 `/dev/kvm`

**解决方案**:
```bash
# 检查 KVM 设备
ls -l /dev/kvm

# 添加到 kvm 组
sudo usermod -aG kvm $USER

# 重新登录
exit
# (重新登录后)

# 或使用 capabilities
sudo setcap cap_net_admin,cap_sys_admin,cap_net_raw+ep \
  /home/primihub/pcloud/infra/packages/orchestrator/bin/orchestrator
```

#### 2. 端口被占用

**错误**: `Address already in use`

**解决方案**:
```bash
# 查找占用端口的进程
sudo lsof -i :3000

# 停止进程
sudo kill -9 <PID>
```

#### 3. Nomad Job 启动失败

**错误**: Job allocation 失败

**解决方案**:
```bash
# 查看 Job 状态
nomad job status <job-name>

# 查看 allocation 日志
nomad alloc logs <alloc-id>

# 重新部署
nomad job stop <job-name>
nomad job run local-deploy/jobs/<job-name>.hcl
```

#### 4. Docker 服务无法启动

**错误**: `Cannot connect to Docker daemon`

**解决方案**:
```bash
# 启动 Docker
sudo systemctl start docker

# 检查状态
sudo systemctl status docker

# 添加到 docker 组
sudo usermod -aG docker $USER
```

#### 5. 数据库连接失败

**错误**: `Connection refused` to PostgreSQL

**解决方案**:
```bash
# 检查 Docker 服务
cd /home/primihub/pcloud/infra/packages/local-dev
docker compose ps

# 查看日志
docker compose logs postgres

# 重启服务
docker compose restart postgres
```

### 日志查看

#### Nomad/Consul 日志

```bash
tail -f /tmp/e2b-logs/nomad.log
tail -f /tmp/e2b-logs/consul.log
```

#### Nomad Job 日志

```bash
# 列出所有 allocations
nomad alloc status

# 查看特定 allocation 日志
nomad alloc logs -f <alloc-id>

# 查看特定 task 日志
nomad alloc logs -f -task <task-name> <alloc-id>
```

#### Docker 服务日志

```bash
cd /home/primihub/pcloud/infra/packages/local-dev
docker compose logs -f postgres
docker compose logs -f redis
docker compose logs -f clickhouse
```

### 完全重置

如果遇到无法解决的问题，可以完全重置：

```bash
# 1. 停止所有服务
bash scripts/stop-all.sh

# 2. 清理所有数据
bash scripts/cleanup.sh
# 选择完全重置

# 3. 重新初始化
bash scripts/09-init-database.sh

# 4. 重新启动
bash scripts/start-all.sh
```

## 常见问题

### Q: 部署需要多长时间？

A: 首次部署（包括下载和构建）约需 30-60 分钟。后续启动仅需 2-5 分钟。

### Q: 需要互联网连接吗？

A: 仅在初始化时需要（下载依赖、构建镜像）。运行时不需要互联网。

### Q: 可以在虚拟机中部署吗？

A: 可以，但需要嵌套虚拟化支持。VMware/KVM 支持，VirtualBox 可能有问题。

### Q: 如何添加更多存储空间？

A: 修改 `.env.local` 中的路径配置，将存储目录移到更大的分区。

### Q: 支持多节点部署吗？

A: 当前配置为单节点。多节点需要修改 Nomad/Consul 配置。

### Q: 如何升级版本？

A: 重新运行 `06-build-binaries.sh` 和 `07-build-images.sh`，然后重新部署 Jobs。

### Q: 数据保存在哪里？

A:
- 模板: `/tmp/e2b-template-storage`
- 缓存: `/tmp/e2b-*-cache`
- 数据库: Docker volumes
- 快捷访问: `~/e2b-storage/`

## 高级配置

### 环境变量

编辑 `/home/primihub/pcloud/infra/local-deploy/.env.local` 可以修改：

- 数据库连接字符串
- 存储路径
- 认证密钥
- 功能开关

修改后需要重新部署 Jobs。

### 资源限制

编辑 Nomad Job 文件 (`.hcl`) 可以调整资源分配：

```hcl
resources {
  cpu    = 2000  # CPU (MHz)
  memory = 4096  # 内存 (MB)
}
```

### 网络配置

Nginx 配置文件: `local-deploy/nginx/nginx.conf`

可以修改路由、超时、缓冲等设置。

### 持久化配置

当前数据保存在 `/tmp` 下，重启后可能丢失。要持久化：

1. 编辑 `.env.local`
2. 修改路径为非 `/tmp` 目录
3. 重新创建存储目录
4. 重新部署

## 性能优化

### 1. 使用 SSD

将存储目录移到 SSD：

```bash
# 创建目录
sudo mkdir -p /opt/e2b-storage

# 修改 .env.local
sed -i 's|/tmp/e2b-|/opt/e2b-storage/|g' .env.local

# 重新创建目录
bash scripts/05-setup-storage.sh
```

### 2. 增加 Hugepages

编辑 `/etc/sysctl.d/99-e2b-local.conf`:

```
vm.nr_hugepages = 4096
```

应用：`sudo sysctl -p /etc/sysctl.d/99-e2b-local.conf`

### 3. 调整资源分配

根据负载调整 Job 资源限制，避免过度分配。

## 开发者指南

### 修改代码后重新部署

```bash
# 1. 重新构建
bash scripts/06-build-binaries.sh
bash scripts/07-build-images.sh

# 2. 重启 Jobs
nomad job stop orchestrator
nomad job run local-deploy/jobs/orchestrator.hcl
```

### 添加新的 Nomad Job

1. 在 `local-deploy/jobs/` 创建 `.hcl` 文件
2. 验证：`nomad job validate your-job.hcl`
3. 运行：`nomad job run your-job.hcl`

### 调试技巧

```bash
# 查看所有进程
ps aux | grep -E 'nomad|consul|orchestrator|firecracker'

# 查看网络连接
sudo netstat -tlnp | grep -E '3000|5008|4646'

# 查看资源使用
nomad node status -verbose
docker stats
```

## 参考资料

### 目录结构

```
local-deploy/
├── .env.local                 # 环境变量配置
├── nomad-dev.hcl              # Nomad 配置
├── README.md                  # 本文档
├── jobs/                      # Nomad Job 定义
│   ├── api.hcl
│   ├── orchestrator.hcl
│   ├── template-manager.hcl
│   └── client-proxy.hcl
├── nginx/                     # Nginx 配置
│   └── nginx.conf
└── scripts/                   # 部署脚本
    ├── 00-init-all.sh         # 总初始化
    ├── 01-check-requirements.sh
    ├── 02-install-deps.sh
    ├── 03-setup-kernel.sh
    ├── 04-setup-sudo.sh
    ├── 05-setup-storage.sh
    ├── 06-build-binaries.sh
    ├── 07-build-images.sh
    ├── 08-install-nomad-consul.sh
    ├── 09-init-database.sh
    ├── start-all.sh
    ├── start-infra.sh
    ├── start-consul.sh
    ├── start-nomad.sh
    ├── deploy-all-jobs.sh
    ├── stop-all.sh
    ├── cleanup.sh
    └── verify-deployment.sh
```

### 常用命令

```bash
# Nomad
nomad job status                  # 查看所有 Jobs
nomad node status                 # 查看节点
nomad alloc logs -f <id>          # 查看日志

# Consul
consul members                    # 查看成员
consul catalog services           # 查看服务

# Docker
docker compose ps                 # 查看服务状态
docker compose logs -f            # 查看日志

# 系统
lsmod | grep kvm                  # 查看 KVM 模块
free -h                           # 查看内存
df -h                             # 查看磁盘
```

## 贡献

发现问题或有改进建议？请提交 Issue 或 Pull Request。

## 许可证

遵循 E2B 项目主许可证。

---

**文档版本**: 1.0.0
**最后更新**: 2025-12-11
**维护者**: E2B Team
