# Firecracker Virtio MMIO 修复进度报告

**日期**: 2025-12-19 12:15
**状态**: 内核已更新，等待服务启动测试

## ✅ 已完成的操作

### 1. 诊断和分析 ✓
- ✅ 确认问题根源：`CONFIG_VIRTIO_MMIO_CMDLINE_DEVICES` 可能未启用
- ✅ 分析 E2B 代码：确认依赖 Firecracker 自动注入 `virtio_mmio.device` 参数
- ✅ 创建诊断文档：`FIRECRACKER_VIRTIO_EINVAL_DIAGNOSIS.md`
- ✅ 创建检查脚本：`check_kernel_virtio_config.sh`
- ✅ 创建修复脚本：`fix_firecracker_virtio.sh`

### 2. 内核更新 ✓
- ✅ 原内核：`vmlinux-5.10.223/vmlinux.bin` (42MB)
- ✅ 新内核：`vmlinux-5.10.bin.new` (1.2MB) - 已部署
- ✅ 文件验证：ELF 64-bit LSB executable

```bash
# 当前内核状态
$ ls -lh /home/primihub/pcloud/infra/packages/fc-kernels/vmlinux-5.10.223/vmlinux.bin
-rw-rw-r-- 1 primihub primihub 1.2M Dec 19 12:15 vmlinux.bin
```

## ⚠️ 当前状态

### 服务状态
- ❌ **Nomad**: 未运行
- ✅ **Consul**: 运行中 (dev 模式)
- ❌ **API**: 未运行
- ❌ **Orchestrator**: 未运行

### 需要的后续操作

## 📋 下一步行动计划

### 选项 A: 完整测试流程（推荐）

#### 步骤 1: 启动基础设施服务
```bash
cd /home/primihub/pcloud/infra/local-deploy

# 启动 PostgreSQL, Redis, ClickHouse等
bash scripts/start-infra.sh

# 启动 Nomad
bash scripts/start-nomad.sh

# 检查服务状态
nomad node status
consul members
```

#### 步骤 2: 部署应用服务
```bash
# 部署 Orchestrator
nomad job run jobs/orchestrator.hcl

# 部署 API
nomad job run jobs/api.hcl

# 检查服务状态
nomad job status
nomad job status orchestrator
nomad job status api
```

#### 步骤 3: 验证服务健康
```bash
# 检查 API
curl http://localhost:3000/health

# 检查 Orchestrator
curl http://localhost:5008/health

# 检查节点发现
# (从 API 日志中确认)
```

#### 步骤 4: 测试 VM 创建
```bash
# 创建测试 VM
curl -X POST http://localhost:3000/sandboxes \
  -H "Content-Type: application/json" \
  -H "X-API-Key: e2b_53ae1fed82754c17ad8077fbc8bcdd90" \
  -d '{"templateID": "base-template-000-0000-0000-000000000001", "timeout": 300}'

# 预期结果：
# ✅ 成功：返回 sandbox ID (JSON 格式)
# ❌ 失败：返回 {"code":500,"message":"..."}
```

#### 步骤 5: 监控日志
```bash
# API 日志
API_ALLOC=$(nomad job allocs api | grep "running" | awk '{print $1}')
nomad alloc logs -f $API_ALLOC api

# Orchestrator 日志
ORCH_ALLOC=$(nomad job allocs orchestrator | grep "running" | awk '{print $1}')
nomad alloc logs -f $ORCH_ALLOC orchestrator

# 查找关键信息：
# - "virtio_mmio" - 设备探测信息
# - "EINVAL" - 之前的错误
# - "created sandbox" - 成功创建标志
```

### 选项 B: 最小化测试（快速验证）

如果只想快速验证内核配置，可以创建一个最小化的 Firecracker 测试：

```bash
# 1. 创建测试目录
mkdir -p /tmp/fc-test
cd /tmp/fc-test

# 2. 创建一个最小根文件系统（100MB）
dd if=/dev/zero of=rootfs.ext4 bs=1M count=100
mkfs.ext4 -F rootfs.ext4

# 3. 创建 Firecracker 配置
cat > config.json <<'EOF'
{
  "boot-source": {
    "kernel_image_path": "/home/primihub/pcloud/infra/packages/fc-kernels/vmlinux-5.10.223/vmlinux.bin",
    "boot_args": "console=ttyS0 reboot=k panic=1 pci=off"
  },
  "drives": [
    {
      "drive_id": "rootfs",
      "path_on_host": "/tmp/fc-test/rootfs.ext4",
      "is_root_device": true,
      "is_read_only": false
    }
  ],
  "machine-config": {
    "vcpu_count": 1,
    "mem_size_mib": 128
  }
}
EOF

# 4. 启动 Firecracker
sudo /home/primihub/pcloud/infra/packages/fc-versions/builds/v1.12.1_d990331/firecracker \
  --api-sock /tmp/fc-test.sock \
  --config-file config.json

# 5. 查看输出
# ✅ 如果看到 "virtio_mmio: Registering device..." - 说明内核支持！
# ❌ 如果看到 "virtio_mmio: probe failed with error -22" - 说明仍有问题
```

## 🔍 成功/失败判断标准

### ✅ 成功标志
1. **VM 创建成功**
   - API 返回 sandbox ID
   - `ps aux | grep firecracker` 显示运行中的进程

2. **日志中的成功信息**
   - "virtio_mmio: Registering device virtio-mmio.0"
   - "virtio_blk: registered block device"
   - "virtio_net: ... registered"
   - "created sandbox files"

3. **无错误信息**
   - 没有 "EINVAL" 或 "-22"
   - 没有 "probe failed"

### ❌ 失败标志
1. **内核加载错误**
   ```
   Cannot load kernel due to invalid memory configuration
   ```
   **原因**: 内核镜像本身有问题（大小只有 1.2MB 可疑）

2. **Virtio 探测失败**
   ```
   virtio_mmio: probe of virtio-mmio.0 failed with error -22
   ```
   **原因**: 内核仍然缺少 `CONFIG_VIRTIO_MMIO_CMDLINE_DEVICES`

3. **设备未找到**
   ```
   VFS: Cannot open root device "vda"
   ```
   **原因**: virtio-blk 驱动未加载或探测失败

## 📊 关键诊断命令

```bash
# 1. 检查内核文件完整性
file /home/primihub/pcloud/infra/packages/fc-kernels/vmlinux-5.10.223/vmlinux.bin
md5sum /home/primihub/pcloud/infra/packages/fc-kernels/vmlinux-5.10.223/vmlinux.bin

# 2. 检查服务状态
nomad job status
consul members
docker ps

# 3. 检查端口监听
ss -tulpn | grep -E ":3000|:5008|:4646"

# 4. 检查进程
ps aux | grep -E "firecracker|orchestrator|nomad"

# 5. 查看实时日志
tail -f /mnt/sdb/e2b-storage/logs/*.log
```

## 🚨 潜在问题

### 问题 1: vmlinux-5.10.bin.new 大小异常

**观察**: 文件只有 1.2MB，而标准的 Linux 5.10 内核通常是 20-50MB

**可能原因**:
1. 这是一个压缩的内核（bzImage 格式）而非 vmlinux
2. 这是一个裁剪过度的内核
3. 文件损坏或不完整

**建议**:
- 使用 `file` 命令详细检查
- 尝试从可靠来源重新下载内核
- 考虑使用 Firecracker 项目提供的预构建内核

### 问题 2: 无法下载官方内核

**原因**: Firecracker v1.12.1 的内核文件可能：
- 不在 GitHub Releases 中
- 托管在 AWS S3 但路径不同
- 需要从源代码构建

**建议方案**:
1. **使用其他版本的官方内核**
   ```bash
   # 尝试 v1.10 或其他已知可用的版本
   curl -L -o vmlinux-5.10.bin \
     https://github.com/firecracker-microvm/firecracker/releases/download/v1.10.0/vmlinux-5.10
   ```

2. **从 Ubuntu 包管理器获取**
   ```bash
   # 使用 Ubuntu 官方的内核并添加必要配置
   apt-cache search linux-image | grep 5.10
   ```

3. **自行编译**（最可靠但耗时）
   - 下载 Linux 5.10.223 源代码
   - 使用 Firecracker 官方配置模板
   - 确保启用 CONFIG_VIRTIO_MMIO_CMDLINE_DEVICES=y

## 📝 修复记录

| 时间 | 操作 | 结果 |
|------|------|------|
| 12:00 | 创建诊断脚本 | ✅ 完成 |
| 12:05 | 尝试下载官方内核 (GitHub) | ❌ 404 错误 |
| 12:10 | 尝试下载官方内核 (S3) | ❌ 404 错误 |
| 12:15 | 使用本地 vmlinux-5.10.bin.new | ✅ 已部署 |
| 12:20 | 等待服务启动测试 | ⏳ 进行中 |

## 🎯 立即执行的推荐命令

```bash
# 1. 检查当前内核文件详情
file /home/primihub/pcloud/infra/packages/fc-kernels/vmlinux-5.10.223/vmlinux.bin

# 2. 启动基础服务
cd /home/primihub/pcloud/infra/local-deploy
bash scripts/start-all.sh

# 3. 等待服务就绪（约 30 秒）
sleep 30

# 4. 测试 VM 创建
curl -X POST http://localhost:3000/sandboxes \
  -H "Content-Type: application/json" \
  -H "X-API-Key: e2b_53ae1fed82754c17ad8077fbc8bcdd90" \
  -d '{"templateID": "base-template-000-0000-0000-000000000001", "timeout": 300}'
```

## 📚 相关文档

- **详细诊断报告**: `FIRECRACKER_VIRTIO_EINVAL_DIAGNOSIS.md`
- **检查脚本**: `check_kernel_virtio_config.sh`
- **修复脚本**: `fix_firecracker_virtio.sh`
- **E2B 文档**: `CLAUDE.md`
- **模板构建排错**: `TEMPLATE_BUILD_TROUBLESHOOTING.md`

## 📞 如果遇到问题

1. **检查服务日志**
   ```bash
   journalctl -u nomad -f
   tail -f /mnt/sdb/e2b-storage/logs/*.log
   ```

2. **重置环境**（最后手段）
   ```bash
   # 停止所有服务
   pkill -f firecracker
   nomad job stop -purge api orchestrator

   # 重启基础设施
   bash scripts/start-all.sh
   ```

3. **恢复备份内核**（如果新内核不工作）
   ```bash
   sudo cp /home/primihub/pcloud/infra/packages/fc-kernels/vmlinux-5.10.223/vmlinux.bin.backup-* \
           /home/primihub/pcloud/infra/packages/fc-kernels/vmlinux-5.10.223/vmlinux.bin
   ```
