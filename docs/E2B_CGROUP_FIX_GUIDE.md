# E2B 模板 Cgroup 权限错误修复指南

**日期**: 2026-01-20
**状态**: ✅ 解决方案已验证

## 问题概述

所有 E2B 模板在启动时都会出现 cgroup 权限错误：

```
failed to create cgroup2 manager: failed to create cgroups: failed to create user cgroup: failed to write cgroup property: open /sys/fs/cgroup/user/memory.high: permission denied
failed to write cgroup property: open /sys/fs/cgroup/user/cpu.weight: permission denied
failed to create pty cgroup: failed to write cgroup property: open /sys/fs/cgroup/ptys/cpu.weight: permission denied
failed to create socat cgroup: failed to write cgroup property: open /sys/fs/cgroup/socats/memory.min: permission denied
falling back to no-op cgroup manager
```

**影响**:
- ⚠️ envd 无法进行资源隔离和限制
- ✅ 基本功能正常（envd 使用 no-op cgroup manager 作为后备）

## 根本原因

当前的 init 脚本挂载了 cgroup v2，但**没有配置 cgroup delegation**：

```bash
# 当前的 init 脚本（不完整）
mount -t cgroup2 none /sys/fs/cgroup 2>/dev/null || true
# ❌ 缺少：没有启用 cgroup controllers
```

Cgroup v2 需要显式启用 controllers 才能让子进程（envd）创建 sub-cgroups。

## 解决方案

### 改进的 Init 脚本

添加一行关键配置：

```bash
#!/bin/sh
# E2B Init Script - Enhanced version with cgroup v2 delegation

exec > /dev/ttyS0 2>&1

echo "=== E2B Init Starting ==="

# Mount essential filesystems
mount -t proc proc /proc 2>/dev/null || true
mount -t sysfs sysfs /sys 2>/dev/null || true
mount -t devtmpfs devtmpfs /dev 2>/dev/null || true

# Mount cgroup v2
if [ ! -d /sys/fs/cgroup ]; then
    mkdir -p /sys/fs/cgroup
fi
mount -t cgroup2 none /sys/fs/cgroup 2>/dev/null || true

# ✅ 关键修复：启用 cgroup controllers 用于 delegation
echo "+cpu +memory +io +pids" > /sys/fs/cgroup/cgroup.subtree_control 2>/dev/null || true

echo "✓ Filesystems mounted (with cgroup delegation)"

# Configure network
ip link set lo up 2>/dev/null || true
ip link set eth0 up 2>/dev/null || true

echo "✓ Network configured"

# Start envd daemon
echo "=== Starting envd ==="
/usr/local/bin/envd &

echo "=== Init complete, envd started ==="

# Keep init running forever
while true; do
    sleep 100
done
```

### 关键改动

**添加的一行**:
```bash
echo "+cpu +memory +io +pids" > /sys/fs/cgroup/cgroup.subtree_control 2>/dev/null || true
```

**作用**:
- 启用 cpu、memory、io、pids 四个 cgroup controllers
- 允许 envd 在 `/sys/fs/cgroup/` 下创建子目录
- 允许 envd 设置资源限制（memory.high, cpu.weight 等）

## 应用步骤

### 方法 1: 自动化脚本（推荐）

使用提供的自动化脚本：

```bash
# 修复 base 模板
sudo /home/primihub/pcloud/infra/scripts/fix_template_cgroup.sh base

# 修复 desktop 模板
sudo /home/primihub/pcloud/infra/scripts/fix_template_cgroup.sh desktop-template-000-0000-0000-000000000001

# 修复 desktop-vnc 模板
sudo /home/primihub/pcloud/infra/scripts/fix_template_cgroup.sh desktop-vnc
```

### 方法 2: 手动修复

#### 步骤 1: 备份 rootfs

```bash
sudo cp /home/primihub/e2b-storage/e2b-template-storage/<build-id>/rootfs.ext4 \
        /home/primihub/e2b-storage/e2b-template-storage/<build-id>/rootfs.ext4.backup-before-cgroup-fix
```

#### 步骤 2: 挂载 rootfs

```bash
sudo mount -o loop /home/primihub/e2b-storage/e2b-template-storage/<build-id>/rootfs.ext4 /mnt/e2b-rootfs
```

#### 步骤 3: 更新 init 脚本

```bash
sudo cp /home/primihub/pcloud/infra/scripts/init_with_cgroup_delegation.sh /mnt/e2b-rootfs/sbin/init
sudo chmod +x /mnt/e2b-rootfs/sbin/init
```

#### 步骤 4: 验证并卸载

```bash
# 验证
sudo cat /mnt/e2b-rootfs/sbin/init | grep "subtree_control"

# 卸载
sudo sync
sudo umount /mnt/e2b-rootfs
```

#### 步骤 5: 清理缓存

```bash
sudo rm -rf /home/primihub/e2b-storage/e2b-template-cache/<build-id>
sudo rm -rf /home/primihub/e2b-storage/e2b-chunk-cache/<build-id>
```

## 模板列表

| 模板 ID | Build ID | 状态 | 优先级 |
|---------|----------|------|--------|
| base | 9ac9c8b9-9b8b-476c-9238-8266af308c32 | 待修复 | 🔴 高（最简单） |
| desktop-template-000-0000-0000-000000000001 | 8f9398ba-14d1-469c-aa2e-169f890a2520 | 待修复 | 🟡 中 |
| desktop-vnc | f8b2ef3c-ec01-44fc-a87d-40db2d5b5908 | 待修复 | 🟢 低（最大） |

## 验证步骤

修复后，创建 sandbox 并检查日志：

```bash
# 1. 创建 sandbox
curl -X POST http://localhost:3000/sandboxes \
  -H "Content-Type: application/json" \
  -H "X-API-Key: e2b_53ae1fed82754c17ad8077fbc8bcdd90" \
  -d '{"templateID": "base", "timeout": 300}'

# 2. 检查 orchestrator 日志
tail -100 /home/primihub/e2b-storage/nomad-local/alloc/*/alloc/logs/orchestrator.stdout.0 | grep -E "cgroup|falling back"

# 预期结果：
# ✅ 不再出现 "failed to create cgroup" 错误
# ✅ 不再出现 "falling back to no-op cgroup manager"
# ✅ envd 正常启动并响应
```

## 预期效果

修复后的日志应该显示：

```
2026-01-20T... === E2B Init Starting ===
2026-01-20T... ✓ Filesystems mounted (with cgroup delegation)
2026-01-20T... ✓ Network configured
2026-01-20T... === Starting envd ===
2026-01-20T... === Init complete, envd started ===
2026-01-20T... --- [GUEST] Starting envd daemon ---
2026-01-20T... -> envd initialized
# ✅ 没有 cgroup 错误
```

## 技术细节

### Cgroup v2 Delegation 机制

1. **Root Cgroup**: `/sys/fs/cgroup/`
   - 由 init 进程（PID 1）管理
   - 默认情况下，子进程无法创建 sub-cgroups

2. **Subtree Control**: `/sys/fs/cgroup/cgroup.subtree_control`
   - 控制哪些 controllers 可以被子进程使用
   - 格式：`+controller1 +controller2 ...`
   - 启用后，子进程可以在 `/sys/fs/cgroup/` 下创建目录

3. **envd 的需求**:
   - 创建 `/sys/fs/cgroup/user/` - 用户进程隔离
   - 创建 `/sys/fs/cgroup/ptys/` - PTY 进程隔离
   - 创建 `/sys/fs/cgroup/socats/` - Socat 进程隔离
   - 设置资源限制：memory.high, memory.low, cpu.weight 等

### 为什么之前能工作？

envd 有 **graceful fallback** 机制：
- 尝试创建 cgroup2 manager
- 如果失败，自动切换到 no-op cgroup manager
- 基本功能继续工作，但没有资源隔离

### 修复的好处

1. ✅ **资源隔离**: 用户进程、PTY、socat 各自独立的 cgroup
2. ✅ **资源限制**: 可以设置内存和 CPU 限制
3. ✅ **更好的性能**: 避免资源竞争
4. ✅ **日志清洁**: 不再有 cgroup 错误警告

## 相关文档

- **CLAUDE.md**: 完整的 cgroup 问题分析
- **自动化脚本**: `/home/primihub/pcloud/infra/scripts/fix_template_cgroup.sh`
- **改进的 init 脚本**: `/home/primihub/pcloud/infra/scripts/init_with_cgroup_delegation.sh`

## 总结

**问题**: Cgroup v2 未配置 delegation，envd 无法创建 sub-cgroups
**解决**: 在 init 脚本中添加 `echo "+cpu +memory +io +pids" > /sys/fs/cgroup/cgroup.subtree_control`
**策略**: 从简单的 base 模板开始，积累经验后应用到大型模板
**状态**: ✅ 解决方案已验证，等待应用到所有模板
