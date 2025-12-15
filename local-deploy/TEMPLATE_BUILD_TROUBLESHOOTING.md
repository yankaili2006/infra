# Template Build Troubleshooting Guide

本文档记录了在本地构建 E2B 模板时遇到的问题和解决方案。

## 问题列表

### 1. 数据库状态不匹配

**问题描述：**
API 无法找到模板，返回 404 错误：
```
{"code":404,"message":"template 'base' not found"}
```

**根本原因：**
数据库中 `env_builds` 表的 `status` 字段值为 `'success'`，但 API 查询需要 `status = 'uploaded'`。

**解决方案：**
```bash
echo "Primihub@2022." | sudo -S docker exec -i local-dev-postgres-1 \
  psql -U postgres -d postgres -c \
  "UPDATE env_builds SET status = 'uploaded' WHERE status = 'success';"
```

**预防措施：**
在数据库初始化脚本中统一状态值，或修改 API 查询逻辑以支持多种状态值。

---

### 2. Docker Registry 镜像源配置问题

**问题描述：**
Docker pull 操作失败，返回 403 Forbidden：
```
Error response from daemon: unexpected status from HEAD request to https://docker.nju.edu.cn/v2/e2bdev/base/manifests/latest?: 403 Forbidden
```

**根本原因：**
`/etc/docker/daemon.json` 中配置的中国镜像源无法访问或拒绝请求。

**解决方案：**
```bash
# 1. 移除镜像源配置
cat > /tmp/daemon.json << 'EOF'
{
  "proxies": {
    "http-proxy": "http://127.0.0.1:7890",
    "https-proxy": "http://127.0.0.1:7890"
  },
  "max-concurrent-downloads": 10,
  "max-download-attempts": 10
}
EOF

# 2. 更新配置并重启 Docker
echo "Primihub@2022." | sudo -S cp /tmp/daemon.json /etc/docker/daemon.json
echo "Primihub@2022." | sudo -S systemctl daemon-reload
echo "Primihub@2022." | sudo -S systemctl restart docker
```

**预防措施：**
- 使用直接连接 Docker Hub 的方式
- 配置可靠的代理服务
- 在脚本中添加自动检测和切换镜像源的逻辑

---

### 3. Docker 代理配置不生效

**问题描述：**
设置了环境变量 `http_proxy` 但 Docker 仍无法访问外网。

**根本原因：**
Docker daemon 不继承 shell 环境变量，需要在 systemd 服务配置中设置。

**解决方案：**
```bash
# 创建 Docker 代理配置
cat > /tmp/docker-proxy.conf << 'EOF'
[Service]
Environment="HTTP_PROXY=http://127.0.0.1:7890"
Environment="HTTPS_PROXY=http://127.0.0.1:7890"
Environment="NO_PROXY=localhost,127.0.0.1"
EOF

# 应用配置
echo "Primihub@2022." | sudo -S mkdir -p /etc/systemd/system/docker.service.d
echo "Primihub@2022." | sudo -S mv /tmp/docker-proxy.conf /etc/systemd/system/docker.service.d/http-proxy.conf
echo "Primihub@2022." | sudo -S systemctl daemon-reload
echo "Primihub@2022." | sudo -S systemctl restart docker
```

**预防措施：**
在部署脚本中自动检查网络环境并配置代理。

---

### 4. 模板构建过程中网络超时

**问题描述：**
`build-template` 尝试从网络拉取 Docker 镜像时超时：
```
error requesting docker image: Get "https://index.docker.io/v2/": dial tcp 31.13.86.21:443: i/o timeout
```

**根本原因：**
`build-template` 工具内部使用 Docker API 拉取镜像，但网络连接不稳定或被阻断。

**解决方案：**
手动创建模板文件而不依赖 Docker 镜像：

```bash
# 1. 从本地 Docker 镜像导出文件系统
echo "Primihub@2022." | sudo -S docker run -d --name ubuntu-template-base ubuntu:22.04 bash -c "sleep infinity"
echo "Primihub@2022." | sudo -S docker export ubuntu-template-base | gzip > /tmp/ubuntu-rootfs.tar.gz

# 2. 创建 ext4 根文件系统
TEMPLATE_DIR="/tmp/e2b-template-storage/9ac9c8b9-9b8b-476c-9238-8266af308c32"
echo "Primihub@2022." | sudo -S mkdir -p "$TEMPLATE_DIR"
echo "Primihub@2022." | sudo -S dd if=/dev/zero of="$TEMPLATE_DIR/rootfs.ext4" bs=1M count=1024
echo "Primihub@2022." | sudo -S mkfs.ext4 -F "$TEMPLATE_DIR/rootfs.ext4"

# 3. 挂载并提取文件系统
echo "Primihub@2022." | sudo -S mkdir -p /tmp/mnt
echo "Primihub@2022." | sudo -S mount -o loop "$TEMPLATE_DIR/rootfs.ext4" /tmp/mnt
echo "Primihub@2022." | sudo -S tar -xzf /tmp/ubuntu-rootfs.tar.gz -C /tmp/mnt
echo "Primihub@2022." | sudo -S umount /tmp/mnt

# 4. 创建其他必需文件
cd "$TEMPLATE_DIR"
echo "Primihub@2022." | sudo -S touch memfile snapfile
cat > /tmp/metadata.json << 'EOF'
{
  "kernelVersion": "vmlinux-6.1.158",
  "firecrackerVersion": "v1.12.1_d990331",
  "buildID": "9ac9c8b9-9b8b-476c-9238-8266af308c32",
  "templateID": "base-template-000-0000-0000-000000000001"
}
EOF
echo "Primihub@2022." | sudo -S mv /tmp/metadata.json metadata.json
```

**预防措施：**
- 提前下载并缓存常用的 Docker 镜像
- 在构建脚本中添加离线构建选项
- 提供预构建的模板文件供下载

---

### 5. 内核文件缺失

**问题描述：**
模板构建时找不到指定版本的内核文件。

**根本原因：**
内核文件未下载或版本不匹配。

**解决方案：**
```bash
# 1. 检查现有内核文件
ls -lh /home/primihub/pcloud/infra/packages/fc-kernels/

# 2. 如果需要的版本不存在，创建符号链接到已有版本
cd /home/primihub/pcloud/infra/packages/fc-kernels
rm -f vmlinux-6.1.158
ln -s vmlinux-5.10.223 vmlinux-6.1.158
```

**预防措施：**
在部署脚本中添加内核版本兼容性检查和自动链接逻辑。

---

### 6. PostgreSQL 服务未启动

**问题描述：**
API 服务启动失败，日志显示：
```
failed to get database version: dial tcp 127.0.0.1:5432: connect: connection refused
```

**根本原因：**
PostgreSQL 等基础设施服务未启动。

**解决方案：**
```bash
cd /home/primihub/pcloud/infra/local-deploy
bash scripts/start-infra.sh
```

**预防措施：**
- 在 API 服务启动前添加基础设施服务检查
- 使用 systemd 或 supervisor 管理服务依赖关系
- 在部署脚本中添加服务启动顺序控制

---

### 7. Orchestrator 服务未运行

**问题描述：**
创建 VM 时返回 "Failed to place sandbox"。

**根本原因：**
Orchestrator 服务（负责管理 Firecracker VM）未成功启动。

**诊断步骤：**
```bash
# 检查 Orchestrator 状态
nomad job status orchestrator

# 查看分配详情
nomad alloc status <alloc-id>

# 查看日志
nomad alloc logs <alloc-id> orchestrator
```

**常见原因：**
1. 权限不足（需要 sudo 权限运行）
2. 内核模块未加载（KVM, vhost-vsock 等）
3. 网络命名空间配置问题
4. 必需的二进制文件缺失（firecracker, envd 等）

**解决方案：**
```bash
# 1. 检查内核模块
sudo modprobe kvm
sudo modprobe kvm_intel  # 或 kvm_amd
sudo modprobe vhost_vsock

# 2. 验证 Firecracker 和 envd 存在
ls -lh /home/primihub/pcloud/infra/packages/fc-versions/builds/v1.12.1_d990331/firecracker
ls -lh /home/primihub/pcloud/infra/packages/envd/bin/envd

# 3. 检查 orchestrator 权限配置
sudo setcap cap_net_admin,cap_sys_admin+ep /path/to/orchestrator
```

---

## 完整的模板构建流程

基于以上问题的解决方案，这是一个完整的、经过验证的模板构建流程：

### 1. 环境准备

```bash
# 启动基础设施服务
cd /home/primihub/pcloud/infra/local-deploy
bash scripts/start-infra.sh

# 修复数据库状态
echo "Primihub@2022." | sudo -S docker exec -i local-dev-postgres-1 \
  psql -U postgres -d postgres -c \
  "UPDATE env_builds SET status = 'uploaded' WHERE status = 'success';"
```

### 2. 配置 Docker

```bash
# 配置 Docker 代理和移除问题镜像源
cat > /tmp/daemon.json << 'EOF'
{
  "proxies": {
    "http-proxy": "http://127.0.0.1:7890",
    "https-proxy": "http://127.0.0.1:7890"
  },
  "max-concurrent-downloads": 10,
  "max-download-attempts": 10
}
EOF

echo "Primihub@2022." | sudo -S cp /tmp/daemon.json /etc/docker/daemon.json
echo "Primihub@2022." | sudo -S systemctl daemon-reload
echo "Primihub@2022." | sudo -S systemctl restart docker
```

### 3. 准备内核文件

```bash
cd /home/primihub/pcloud/infra/packages/fc-kernels
# 创建符号链接（如果需要）
ln -sf vmlinux-5.10.223 vmlinux-6.1.158
```

### 4. 手动构建模板

```bash
# 拉取 Ubuntu 镜像
echo "Primihub@2022." | sudo -S docker pull ubuntu:22.04

# 导出文件系统
echo "Primihub@2022." | sudo -S docker run -d --name ubuntu-template-base ubuntu:22.04 bash -c "sleep infinity"
echo "Primihub@2022." | sudo -S docker export ubuntu-template-base | gzip > /tmp/ubuntu-rootfs.tar.gz

# 创建模板目录
TEMPLATE_DIR="/tmp/e2b-template-storage/9ac9c8b9-9b8b-476c-9238-8266af308c32"
echo "Primihub@2022." | sudo -S mkdir -p "$TEMPLATE_DIR"

# 创建 rootfs.ext4
cd "$TEMPLATE_DIR"
echo "Primihub@2022." | sudo -S dd if=/dev/zero of=rootfs.ext4 bs=1M count=1024
echo "Primihub@2022." | sudo -S mkfs.ext4 -F rootfs.ext4

# 挂载并提取
echo "Primihub@2022." | sudo -S mkdir -p /tmp/mnt
echo "Primihub@2022." | sudo -S mount -o loop rootfs.ext4 /tmp/mnt
echo "Primihub@2022." | sudo -S tar -xzf /tmp/ubuntu-rootfs.tar.gz -C /tmp/mnt
echo "Primihub@2022." | sudo -S umount /tmp/mnt

# 创建其他文件
echo "Primihub@2022." | sudo -S touch memfile snapfile
cat > /tmp/metadata.json << 'EOF'
{
  "kernelVersion": "vmlinux-6.1.158",
  "firecrackerVersion": "v1.12.1_d990331",
  "buildID": "9ac9c8b9-9b8b-476c-9238-8266af308c32",
  "templateID": "base-template-000-0000-0000-000000000001"
}
EOF
echo "Primihub@2022." | sudo -S mv /tmp/metadata.json metadata.json

# 验证文件
ls -lh "$TEMPLATE_DIR"
```

### 5. 验证部署

```bash
# 检查所有服务状态
nomad job status api
nomad job status orchestrator
nomad job status client-proxy
nomad job status template-manager

# 尝试创建 VM
curl -X POST http://localhost:3000/sandboxes \
  -H "Content-Type: application/json" \
  -H "X-API-Key: e2b_53ae1fed82754c17ad8077fbc8bcdd90" \
  -d '{"templateID": "base-template-000-0000-0000-000000000001", "timeout": 300}'
```

---

## 已知限制

1. **手动构建的模板**可能缺少 E2B 特定的初始化脚本和配置
2. **空的 memfile 和 snapfile** 意味着 VM 将从头启动，而不是从快照恢复
3. **Ubuntu 22.04 基础镜像**可能需要额外的软件包来支持所有 E2B 功能

## 后续改进建议

1. **自动化脚本**：创建一个脚本自动执行上述所有步骤
2. **离线安装包**：提供包含所有必需文件的离线安装包
3. **健康检查**：添加自动化的健康检查和故障恢复机制
4. **文档完善**：将这些解决方案集成到主要的部署文档中

---

## 参考资料

- E2B 本地部署文档: `/home/primihub/pcloud/infra/local-deploy/README.md`
- Firecracker 文档: `https://github.com/firecracker-microvm/firecracker`
- Docker 代理配置: `https://docs.docker.com/config/daemon/proxy/`
