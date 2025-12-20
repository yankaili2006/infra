# Firecracker Virtio MMIO -22 (EINVAL) 错误诊断报告

日期: 2025-12-19
系统: E2B Infrastructure with Firecracker v1.12.1
内核版本: Linux 5.10.223

## 问题总结

在使用 Firecracker v1.12.1 创建 VM 时遇到 `-22 (EINVAL)` 错误，导致 Virtio 块设备和网络设备无法正常工作。

## 根本原因分析

### 1. Firecracker Virtio MMIO 工作机制

Firecracker 使用 **Virtio MMIO (Memory-Mapped I/O)** 而非 PCI 总线来实现设备虚拟化：

```
+------------------+
| Guest 内核       |
|                  |
| virtio_mmio      |  ← 需要 CONFIG_VIRTIO_MMIO_CMDLINE_DEVICES=y
| 驱动             |
+--------+---------+
         |
         | MMIO 寄存器访问
         |
+--------v---------+
| Firecracker VMM  |
|                  |
| virtio-blk       |
| virtio-net       |
+------------------+
```

### 2. 关键发现

#### 发现 A: Firecracker 自动注入设备参数

**位置**: Firecracker VMM 内部实现
**行为**: Firecracker 会自动在用户提供的内核命令行**末尾**添加 `virtio_mmio.device=` 参数

**示例**:
```bash
# 用户配置的 boot_args:
console=ttyS0 reboot=k panic=1 pci=off ip=...

# Firecracker 实际传递给内核的完整命令行:
console=ttyS0 reboot=k panic=1 pci=off ip=... virtio_mmio.device=4K@0xd0000000:5 virtio_mmio.device=4K@0xd0001000:6
```

**参数格式**: `virtio_mmio.device=<size>@<baseaddr>:<irq>`
- `4K`: 设备 MMIO 寄存器空间大小
- `0xd0000000`: MMIO 基地址
- `5`: 中断号 (IRQ)

#### 发现 B: E2B 代码依赖 Firecracker 自动注入

**文件**: `infra/packages/orchestrator/internal/sandbox/fc/process.go:244-266`

```go
args := KernelArgs{
    "console":      "ttyS0",
    "pci":          "off",      // ← 禁用 PCI，强制使用 MMIO
    "ip":           ipv4,
    "panic":        "1",
    "reboot":       "k",
    // ... 其他参数
    // 注意: 没有显式添加 virtio_mmio.device 参数
}
```

**结论**: E2B 完全依赖 Firecracker 自动注入设备参数。

#### 发现 C: 内核必须支持命令行设备探测

根据 Firecracker 官方文档和源代码分析：

> Firecracker's current approach only works on kernels with **CONFIG_VIRTIO_MMIO_CMDLINE_DEVICES** enabled, as Firecracker throws a stanza on the end of the kernel command-line to signal the parameters of the virtio-mmio bus.

**参考来源**:
- [Firecracker Issue #2519](https://github.com/firecracker-microvm/firecracker/issues/2519)
- [Firecracker Issue #2709](https://github.com/firecracker-microvm/firecracker/issues/2709)

### 3. -22 (EINVAL) 错误的技术细节

**错误发生位置**: `drivers/virtio/virtio_mmio.c:virtio_mmio_probe()`

**可能原因**:

#### 原因 1: CONFIG_VIRTIO_MMIO_CMDLINE_DEVICES 未启用 (★最可能★)

当内核编译时未启用此选项，内核启动时会：
```c
// drivers/virtio/virtio_mmio.c
#ifdef CONFIG_VIRTIO_MMIO_CMDLINE_DEVICES
static int __init vm_cmdline_set(char *device) {
    // 解析 virtio_mmio.device= 参数
}
#else
// 该功能被完全禁用！
#endif
```

**结果**: 内核完全忽略 `virtio_mmio.device=` 参数，导致：
- 没有注册任何 MMIO 设备
- virtio_mmio_probe() 从未被调用，或者
- 调用时没有有效的设备信息，返回 -EINVAL

#### 原因 2: Magic Value 不匹配

```c
// drivers/virtio/virtio_mmio.c:virtio_mmio_probe()
magic = readl(vm_dev->base + VIRTIO_MMIO_MAGIC_VALUE);
if (magic != ('v' | 'i' << 8 | 'r' << 16 | 't' << 24)) {
    dev_warn(&pdev->dev, "Wrong magic value 0x%08lx!\n", magic);
    return -EINVAL;  // ← 返回 -22
}
```

**原因**: MMIO 地址映射错误，或者该地址根本没有设备。

#### 原因 3: 版本协议不匹配

```c
// 检查 Virtio 版本
version = readl(vm_dev->base + VIRTIO_MMIO_VERSION);
if (version < 1 || version > 2) {
    dev_err(&pdev->dev, "Version %ld not supported!\n", version);
    return -EINVAL;
}
```

Firecracker v1.12.1 使用 Virtio MMIO v2 (Modern)，如果内核尝试使用 v1 协议会失败。

## 诊断结果

### 宿主机内核 (6.8.0-88-generic)

✅ **配置正确** - 所有必要的 Virtio 配置都已启用：

```
CONFIG_VIRTIO_MMIO=y
CONFIG_VIRTIO_MMIO_CMDLINE_DEVICES=y  ← ✓ 已启用
CONFIG_VIRTIO_BLK=y
CONFIG_VIRTIO_NET=y
CONFIG_PCI=y
```

### Guest 内核 (vmlinux-5.10.223/vmlinux.bin)

⚠️ **配置未知** - 无法从内核镜像中提取配置

```bash
$ strings vmlinux.bin | grep "IKCFG"
(无输出)
```

**原因**: 内核编译时未启用 `CONFIG_IKCONFIG` 或 `CONFIG_IKCONFIG_PROC`，导致配置信息未嵌入到内核镜像中。

### 极高概率的问题

基于以上分析，**极高概率是 Guest 内核缺少 `CONFIG_VIRTIO_MMIO_CMDLINE_DEVICES=y`**。

## 解决方案

### 方案 A: 使用 Firecracker 官方内核 (推荐)

Firecracker 官方提供了经过测试的内核镜像，确保所有必要配置都已启用。

```bash
# 1. 下载官方 5.10 内核
cd /tmp
wget https://github.com/firecracker-microvm/firecracker/releases/download/v1.12.1/vmlinux-5.10.bin

# 2. 验证下载
file vmlinux-5.10.bin
# 应该显示: ELF 64-bit LSB executable, x86-64

# 3. 备份当前内核
sudo mv /home/primihub/pcloud/infra/packages/fc-kernels/vmlinux-5.10.223/vmlinux.bin \
        /home/primihub/pcloud/infra/packages/fc-kernels/vmlinux-5.10.223/vmlinux.bin.backup

# 4. 部署新内核
sudo cp vmlinux-5.10.bin \
        /home/primihub/pcloud/infra/packages/fc-kernels/vmlinux-5.10.223/vmlinux.bin

# 5. 设置权限
sudo chown primihub:primihub \
        /home/primihub/pcloud/infra/packages/fc-kernels/vmlinux-5.10.223/vmlinux.bin

# 6. 重启 Orchestrator 服务
nomad job restart orchestrator

# 7. 测试 VM 创建
curl -X POST http://localhost:3000/sandboxes \
  -H "Content-Type: application/json" \
  -H "X-API-Key: e2b_53ae1fed82754c17ad8077fbc8bcdd90" \
  -d '{"templateID": "base-template-000-0000-0000-000000000001", "timeout": 300}'
```

### 方案 B: 重新编译内核

如果需要自定义内核，必须确保以下配置：

#### 1. 下载官方配置模板

```bash
wget https://raw.githubusercontent.com/firecracker-microvm/firecracker/main/resources/guest_configs/microvm-kernel-x86_64-5.10.config \
     -O /tmp/firecracker-5.10.config
```

#### 2. 关键配置检查清单

**必须启用 (=y)**:
```
CONFIG_VIRTIO=y
CONFIG_VIRTIO_MMIO=y
CONFIG_VIRTIO_MMIO_CMDLINE_DEVICES=y    # ★★★ 最关键 ★★★
CONFIG_VIRTIO_BLK=y
CONFIG_VIRTIO_NET=y
CONFIG_VIRTIO_RING=y

# 可选但推荐
CONFIG_VIRTIO_BALLOON=y
CONFIG_VIRTIO_CONSOLE=y

# 如果想要调试，启用配置导出
CONFIG_IKCONFIG=y
CONFIG_IKCONFIG_PROC=y
```

**必须禁用或设为模块**:
```
# 如果使用 pci=off，可以禁用 PCI 支持（可选）
# CONFIG_VIRTIO_PCI is not set
```

#### 3. 编译内核

```bash
# 获取 Linux 5.10.223 源代码
wget https://cdn.kernel.org/pub/linux/kernel/v5.x/linux-5.10.223.tar.xz
tar xf linux-5.10.223.tar.xz
cd linux-5.10.223

# 使用 Firecracker 配置
cp /tmp/firecracker-5.10.config .config

# 配置检查和调整
make menuconfig
# 导航到 Device Drivers -> Virtio drivers
# 确认 "Platform bus driver for memory mapped virtio devices" = Y
# 确认 "Memory mapped virtio devices parameter parsing" = Y

# 编译
make -j$(nproc) vmlinux

# 复制到目标位置
sudo cp vmlinux /home/primihub/pcloud/infra/packages/fc-kernels/vmlinux-5.10.223/vmlinux.bin
```

### 方案 C: 临时切换到其他内核

如果系统中其他版本的内核已正确配置：

```bash
# 检查 vmlinux-5.10.bin.new
file /home/primihub/pcloud/infra/packages/fc-kernels/vmlinux-5.10.bin.new

# 如果是有效的内核镜像，尝试使用它
sudo cp /home/primihub/pcloud/infra/packages/fc-kernels/vmlinux-5.10.bin.new \
        /home/primihub/pcloud/infra/packages/fc-kernels/vmlinux-5.10.223/vmlinux.bin

# 重启服务并测试
nomad job restart orchestrator
```

## 验证步骤

### 1. 重启服务后检查日志

```bash
# 获取 Orchestrator allocation ID
ORCH_ALLOC=$(nomad job allocs orchestrator | grep "running" | awk '{print $1}')

# 实时监控日志
nomad alloc logs -f $ORCH_ALLOC orchestrator
```

### 2. 创建测试 VM

```bash
curl -X POST http://localhost:3000/sandboxes \
  -H "Content-Type: application/json" \
  -H "X-API-Key: e2b_53ae1fed82754c17ad8077fbc8bcdd90" \
  -d '{"templateID": "base-template-000-0000-0000-000000000001", "timeout": 300}'
```

### 3. 检查 Firecracker 进程

```bash
# 应该看到运行中的 Firecracker 进程
ps aux | grep firecracker

# 检查 VM 日志（如果有错误）
# Orchestrator 日志中会包含 Firecracker stdout/stderr
```

### 4. 成功标志

✅ **成功指标**:
- API 返回 sandbox ID (非 500 错误)
- `ps aux | grep firecracker` 显示运行中的进程
- Orchestrator 日志中没有 "EINVAL" 或 "failed to probe virtio device"
- 可以通过 Envd 连接到 VM

❌ **失败指标**:
- API 返回 `{"code":500,"message":"Failed to place sandbox"}`
- 日志中出现 `-22` 或 `EINVAL`
- 日志中出现 `virtio_mmio: probe of ... failed`
- 没有 Firecracker 进程运行

## 深入调试

如果问题仍然存在，可以通过以下方式获取更详细的内核日志：

### 1. 启用详细内核日志

修改 `infra/packages/orchestrator/internal/sandbox/fc/process.go:244-266`:

```go
args := KernelArgs{
    "console":      "ttyS0",
    "loglevel":     "8",           // 最大详细度
    "earlyprintk":  "serial",      // 早期启动日志
    "debug":        "",            // 启用调试
    // ... 其他参数
}
```

### 2. 查看 Firecracker 标准输出

Orchestrator 会捕获 Firecracker 的 stdout/stderr，可以在 Nomad 日志中看到内核启动日志。

### 3. 检查内核命令行

在 VM 内部（如果能启动）:
```bash
cat /proc/cmdline
# 应该看到 virtio_mmio.device= 参数
```

## 预防措施

### 1. 内核构建流程标准化

创建标准化的内核构建脚本，确保所有必要配置都被启用：

```bash
#!/bin/bash
# build-firecracker-kernel.sh

KERNEL_VERSION="5.10.223"
CONFIG_URL="https://raw.githubusercontent.com/firecracker-microvm/firecracker/main/resources/guest_configs/microvm-kernel-x86_64-5.10.config"

# 下载和编译
wget "https://cdn.kernel.org/pub/linux/kernel/v5.x/linux-${KERNEL_VERSION}.tar.xz"
tar xf "linux-${KERNEL_VERSION}.tar.xz"
cd "linux-${KERNEL_VERSION}"

wget "$CONFIG_URL" -O .config

# 验证关键配置
if ! grep -q "CONFIG_VIRTIO_MMIO_CMDLINE_DEVICES=y" .config; then
    echo "ERROR: CONFIG_VIRTIO_MMIO_CMDLINE_DEVICES not enabled!"
    exit 1
fi

make -j$(nproc) vmlinux
```

### 2. 自动化测试

添加内核配置验证测试：

```bash
# test-kernel-config.sh
KERNEL_PATH="$1"

# 测试 1: 文件存在且是 ELF
file "$KERNEL_PATH" | grep -q "ELF" || exit 1

# 测试 2: 尝试提取配置并验证
if extract-ikconfig "$KERNEL_PATH" 2>/dev/null | grep -q "CONFIG_VIRTIO_MMIO_CMDLINE_DEVICES=y"; then
    echo "✓ Kernel config verified"
    exit 0
else
    echo "⚠ Cannot verify kernel config - proceed with caution"
    exit 2
fi
```

## 总结

| 问题 | 原因 | 解决方案 |
|------|------|----------|
| -22 (EINVAL) 错误 | Guest 内核缺少 `CONFIG_VIRTIO_MMIO_CMDLINE_DEVICES=y` | 使用 Firecracker 官方内核或重新编译 |
| 设备探测失败 | 内核忽略 `virtio_mmio.device=` 参数 | 启用内核配置选项 |
| 无法提取内核配置 | 编译时未启用 `CONFIG_IKCONFIG` | 在未来构建中启用此选项以便调试 |

## 参考资料

- [Firecracker Kernel Policy](https://github.com/firecracker-microvm/firecracker/blob/main/docs/kernel-policy.md)
- [Firecracker Issue #2519 - Device Tree Support](https://github.com/firecracker-microvm/firecracker/issues/2519)
- [Firecracker Issue #2709 - Kernel Cmdline Bug](https://github.com/firecracker-microvm/firecracker/issues/2709)
- [Linux Virtio MMIO Documentation](https://www.kernel.org/doc/html/latest/driver-api/virtio/virtio.html)
