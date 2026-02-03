# E2B Rootfs NBD Provider 设计文档

## 概述

本文档描述E2B orchestrator中rootfs管理机制，特别是NBD (Network Block Device) provider的设计和实现，以及在实现过程中发现的关键问题。

## 背景

### 问题起源

在E2B系统中，多个VM需要从同一个模板快速启动。最初的实现使用SimpleReadonlyProvider直接将模板文件暴露给多个VM，导致以下问题：

1. **文件损坏**：多个VM同时写入同一个文件，导致文件系统损坏
2. **数据竞争**：没有写时复制(COW)机制，VM之间相互干扰
3. **隔离性差**：VM无法拥有独立的可写层

### 解决方案

引入NBD Provider，为每个VM创建独立的copy-on-write overlay层，确保：
- 每个VM有独立的可写层
- 模板文件保持只读
- VM之间完全隔离

## 架构设计

### 组件关系

```
┌─────────────────────────────────────────────────────────────┐
│                     Sandbox Creation Flow                    │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  ResumeSandbox (internal/sandbox/sandbox.go:368)            │
│  - 从模板恢复或冷启动VM                                      │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  NBD Provider Creation (sandbox.go:415-419)                 │
│  rootfsProvider := rootfs.NewNBDProvider(...)               │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  NBD Provider Start (sandbox.go:426-431)                    │
│  go func() { rootfsProvider.Start(execCtx) }()              │
│  - 异步启动NBD设备                                           │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  Get Device Path (sandbox.go:434)                           │
│  rootfsPath, err := rootfsProvider.Path()                   │
│  - 阻塞等待NBD设备就绪                                       │
│  - 应返回 /dev/nbd0 等设备路径                               │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  Firecracker Process Creation (sandbox.go:520-537)          │
│  fcHandle := fc.NewProcess(..., rootfsPath, ...)            │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  Firecracker Configuration (fc/process.go:219-302)          │
│  - Create(): 配置VM并启动                                    │
│  - 问题位置：使用错误的rootfs路径                            │
└─────────────────────────────────────────────────────────────┘
```

## NBD Provider 实现

### 核心组件

#### 1. NBDProvider (internal/sandbox/rootfs/nbd.go)

```go
type NBDProvider struct {
    overlay *block.Overlay      // COW overlay层
    mnt     *nbd.DirectPathMount // NBD挂载管理
    ready   *utils.SetOnce[string] // 设备路径就绪信号
    blockSize int64
    finishedOperations chan struct{}
    devicePool *nbd.DevicePool
}
```

**关键方法**：

- `Start(ctx)`: 启动NBD设备，返回设备路径
  - 调用 `mnt.Open(ctx)` 获取设备索引
  - 调用 `ready.SetValue(nbd.GetDevicePath(deviceIndex))` 设置设备路径
  - 设备路径格式：`/dev/nbd0`, `/dev/nbd1`, 等

- `Path()`: 获取NBD设备路径
  - 调用 `ready.Wait()` 阻塞等待Start()完成
  - 返回设备路径如 `/dev/nbd0`

#### 2. DirectPathMount (internal/sandbox/nbd/path_direct.go)

负责NBD设备的底层管理：

```go
type DirectPathMount struct {
    Backend     block.Device
    deviceIndex uint32
    devicePool  *DevicePool
    dispatchers []*Dispatch
    socksClient []*os.File
    socksServer []io.Closer
}
```

**Open()流程**：
1. 从设备池获取可用的NBD设备索引
2. 创建socket pairs用于NBD通信
3. 启动dispatch handlers处理NBD命令
4. 调用 `nbdnl.Connect()` 连接NBD设备
5. 等待设备连接完成
6. 返回设备索引

#### 3. GetDevicePath (internal/sandbox/nbd/pool.go:336)

```go
func GetDevicePath(slot DeviceSlot) DevicePath {
    return fmt.Sprintf("/dev/nbd%d", slot)
}
```

将设备索引转换为设备路径。

## 发现的Bug

### Bug描述

在Firecracker配置阶段，代码使用了错误的rootfs路径，导致VM无法正常启动。

### Bug位置

**文件**: `internal/sandbox/fc/process.go`

**问题代码** (第290-296行):

```go
// Rootfs
err = utils.SymlinkForce(p.providerRootfsPath, p.files.SandboxCacheRootfsLinkPath(p.config))
if err != nil {
    return fmt.Errorf("error symlinking rootfs: %w", err)
}

err = p.client.setRootfsDrive(ctx, p.rootfsPath, options.IoEngine)  // ❌ BUG: 使用了错误的路径
```

### 根本原因

在 `Process` 结构体中有两个rootfs路径字段：

```go
type Process struct {
    providerRootfsPath string  // NBD设备路径，如 /dev/nbd0
    rootfsPath         string  // Start script中的路径（模板缓存路径）
    // ...
}
```

**NewProcess初始化** (process.go:125-138):

```go
return &Process{
    providerRootfsPath: rootfsProviderPath,  // ✅ 正确：NBD设备路径 /dev/nbd0
    rootfsPath:         startScript.RootfsPath, // ❌ 错误：模板缓存文件路径
    // ...
}
```

**问题**：
- `providerRootfsPath` 包含正确的NBD设备路径（如 `/dev/nbd0`）
- `rootfsPath` 包含start script builder返回的路径（模板缓存文件路径）
- 代码在配置Firecracker时使用了 `p.rootfsPath` 而不是 `p.providerRootfsPath`

### 症状

从日志可以看到：

1. NBD设备成功创建：
   ```
   -> got device index
   -> connected to NBD
   -> created NBD rootfs provider with copy-on-write overlay
   ```

2. 但Firecracker收到的是直接文件路径：
   ```
   The API server received a Put request on "/drives/rootfs" with body
   {"path_on_host":"/mnt/data1/fc-envs/v1/base/builds/9ac9c8b9-9b8b-476c-9238-8266af308c32/rootfs.ext4"}
   ```

3. VM启动但envd无法响应，最终超时失败

## 修复方案

### 方案1：直接使用NBD设备路径（推荐）

修改 `internal/sandbox/fc/process.go` 第296行：

```go
// 修改前
err = p.client.setRootfsDrive(ctx, p.rootfsPath, options.IoEngine)

// 修改后
err = p.client.setRootfsDrive(ctx, p.providerRootfsPath, options.IoEngine)
```

**优点**：
- 简单直接
- 符合NBD provider的设计意图
- 确保Firecracker使用NBD设备

**注意事项**：
- 需要确保符号链接逻辑仍然正确
- 可能需要调整start script builder的逻辑

### 方案2：统一路径管理

重构Process结构体，只保留一个rootfs路径字段：

```go
type Process struct {
    rootfsPath string  // 统一使用provider提供的路径
    // 移除 providerRootfsPath
}
```

修改NewProcess：

```go
return &Process{
    rootfsPath: rootfsProviderPath,  // 直接使用provider路径
    // ...
}
```

**优点**：
- 消除歧义
- 代码更清晰
- 减少出错可能

**缺点**：
- 需要更大范围的代码修改
- 可能影响start script builder

## 测试计划

### 单元测试

1. 测试NBD provider的Path()方法返回正确的设备路径
2. 测试DirectPathMount.Open()返回有效的设备索引
3. 测试GetDevicePath()正确格式化设备路径

### 集成测试

1. 创建VM并验证rootfs路径
2. 检查Firecracker API调用中的路径参数
3. 验证VM可以正常启动和运行
4. 测试多个VM并发创建时的隔离性

### 验证步骤

1. 修改代码后重新编译orchestrator
2. 重启orchestrator服务
3. 创建测试VM
4. 检查日志确认：
   - NBD设备成功创建
   - Firecracker收到正确的NBD设备路径（如 `/dev/nbd0`）
   - VM成功启动
   - envd正常响应

## 相关文件

### 核心文件

- `internal/sandbox/sandbox.go`: Sandbox创建和管理
- `internal/sandbox/rootfs/nbd.go`: NBD provider实现
- `internal/sandbox/nbd/path_direct.go`: NBD设备挂载
- `internal/sandbox/fc/process.go`: Firecracker进程管理
- `internal/sandbox/fc/script_builder.go`: Start script生成

### 配置文件

- `internal/server/sandboxes.go`: gRPC API handler

## 后续优化

1. **性能优化**
   - 预分配NBD设备池
   - 优化COW overlay的块大小
   - 减少设备连接等待时间

2. **可靠性提升**
   - 添加NBD设备健康检查
   - 实现设备故障自动恢复
   - 改进错误处理和日志

3. **监控和诊断**
   - 添加NBD设备使用率监控
   - 记录设备分配和释放事件
   - 提供设备状态查询接口

## 参考资料

- [NBD Protocol Specification](https://github.com/NetworkBlockDevice/nbd)
- [Firecracker Documentation](https://github.com/firecracker-microvm/firecracker)
- [Linux NBD Driver](https://www.kernel.org/doc/html/latest/admin-guide/blockdev/nbd.html)

## 变更历史

| 日期 | 版本 | 作者 | 说明 |
|------|------|------|------|
| 2026-02-03 | 1.0 | Claude | 初始版本，记录NBD provider设计和bug分析 |
