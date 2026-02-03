# E2B Ubuntu Desktop Template - 故障排除指南

**日期**: 2026-01-22
**模板**: ubuntu-desktop (Xubuntu)
**Build ID**: 0f617f41-7b55-4df6-99aa-d5a38a85cda4

本文档记录了在E2B环境中部署Xubuntu桌面环境时遇到的问题及解决方案。

---

## 目录

1. [APT代理配置冲突](#1-apt代理配置冲突)
2. [Rootfs磁盘空间不足](#2-rootfs磁盘空间不足)
3. [Init脚本Text file busy错误](#3-init脚本text-file-busy错误)
4. [noVNC访问配置](#4-novnc访问配置)

---

## 1. APT代理配置冲突

### 问题描述

在chroot环境中运行`apt-get update`时，出现连接失败错误：

```
E: Failed to fetch http://archive.ubuntu.com/ubuntu/dists/jammy/InRelease
   Could not connect to 192.168.99.1:7890 (192.168.99.1). - connect (111: Connection refused)
```

### 原因分析

Rootfs中存在多个冲突的APT代理配置文件：
- `/etc/apt/apt.conf.d/` 目录下有多个配置文件
- 部分配置指向 `DIRECT`（直连）
- 部分配置指向 `http://192.168.99.1:7890`（不可达的代理）
- APT在解析时产生冲突，导致连接失败

### 解决方案

**步骤1**: 挂载rootfs并检查代理配置

```bash
sudo mount -o loop /path/to/rootfs.ext4 /mnt/e2b-ubuntu-desktop-rootfs
ls -la /mnt/e2b-ubuntu-desktop-rootfs/etc/apt/apt.conf.d/
```

**步骤2**: 移除所有代理配置文件

```bash
sudo rm -f /mnt/e2b-ubuntu-desktop-rootfs/etc/apt/apt.conf.d/*proxy*
sudo rm -f /mnt/e2b-ubuntu-desktop-rootfs/etc/apt/apt.conf.d/99-*
```

**步骤3**: 验证配置已清理

```bash
ls /mnt/e2b-ubuntu-desktop-rootfs/etc/apt/apt.conf.d/
```

### 预防措施

- 在创建模板时，避免在rootfs中配置代理
- 如需代理，应在宿主机层面配置，而非rootfs内部
- 定期检查`/etc/apt/apt.conf.d/`目录，确保无冲突配置

---

## 2. Rootfs磁盘空间不足

### 问题描述

安装Xubuntu桌面环境时，出现磁盘空间不足错误：

```
E: You don't have enough free space in /var/cache/apt/archives/
```

检查发现：
- Rootfs大小: 974M
- 已使用: 100%
- 可用空间: 1.6M
- 需要空间: 330MB（用于XFCE安装）

### 原因分析

原始rootfs.ext4文件只有1GB大小，安装完基础系统后剩余空间不足以安装完整的桌面环境。

### 解决方案

**步骤1**: 卸载rootfs（如果已挂载）

```bash
sudo umount /mnt/e2b-ubuntu-desktop-rootfs
```

**步骤2**: 扩展rootfs文件大小（从1GB扩展到3GB）

```bash
# 添加2GB空间
dd if=/dev/zero bs=1M count=2048 >> /path/to/rootfs.ext4
```

**步骤3**: 检查并修复文件系统

```bash
sudo e2fsck -y -f /path/to/rootfs.ext4
```

输出示例：
```
Pass 1: Checking inodes, blocks, and sizes
Pass 2: Checking directory structure
Pass 3: Checking directory connectivity
Pass 4: Checking reference counts
Pass 5: Checking group summary information
rootfs.ext4: 45123/65536 files (0.1% non-contiguous), 234567/262144 blocks
```

**步骤4**: 调整文件系统大小以使用全部空间

```bash
sudo resize2fs /path/to/rootfs.ext4
```

输出示例：
```
Resizing the filesystem on rootfs.ext4 to 786432 (4k) blocks.
The filesystem on rootfs.ext4 is now 786432 (4k) blocks long.
```

**步骤5**: 验证扩展结果

```bash
# 挂载并检查空间
sudo mount -o loop /path/to/rootfs.ext4 /mnt/e2b-ubuntu-desktop-rootfs
df -h /mnt/e2b-ubuntu-desktop-rootfs
```

预期输出：
```
Filesystem      Size  Used Avail Use% Mounted on
/dev/loop0      3.0G  974M  2.0G  33% /mnt/e2b-ubuntu-desktop-rootfs
```

### 最佳实践

- **初始大小建议**:
  - 基础系统: 2GB
  - 带桌面环境: 3-5GB
  - 开发环境: 5-10GB

- **扩展时机**: 在安装大型软件包前预先扩展，避免安装中断

- **监控空间**: 定期检查rootfs使用情况
  ```bash
  df -h /mnt/e2b-ubuntu-desktop-rootfs
  ```

---
