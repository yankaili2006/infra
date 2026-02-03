# E2B Firecracker VM envd 进程启动问题排查记录

**问题发现时间**: 2026-01-17
**影响范围**: E2B 沙箱无法正常提供服务
**严重程度**: 高 - 阻塞沙箱功能

## 问题描述

E2B Firecracker VM 启动后，envd 进程无法正常启动，导致：
- 无法通过 HTTP 访问沙箱内的 envd 服务（端口 49983）
- 沙箱创建后无法执行代码
- 网络连通性测试失败

## 问题表现

```bash
# 症状 1: envd 健康检查失败
$ sudo ip netns exec ns-X curl -s -m 2 http://169.254.0.21:49983/health
# 超时，无响应

# 症状 2: VM 内部 envd 进程未运行
$ nomad alloc logs <alloc-id> | grep envd
# 没有 envd 相关日志

# 症状 3: 端口未监听
$ sudo ip netns exec ns-X netstat -tlnp | grep 49983
# 无输出
```

## 排查过程

### 1. 检查 rootfs 中的 envd 配置

```bash
# 挂载 rootfs 检查
BUILD_ID="9ac9c8b9-9b8b-476c-9238-8266af308c32"
sudo mount -o loop /mnt/sdb/e2b-storage/e2b-template-storage/$BUILD_ID/rootfs.ext4 /mnt/e2b-rootfs

# 检查 /sbin/init
cat /mnt/e2b-rootfs/sbin/init
# 发现：init 脚本正确调用 /usr/local/bin/envd

# 检查 envd wrapper
cat /mnt/e2b-rootfs/usr/local/bin/envd
# 发现：wrapper 脚本存在问题
```

**发现的问题**：
- envd wrapper 脚本使用了 `--debug` 参数，但 envd.real 不支持
- wrapper 脚本使用了 `exec`，导致无法捕获错误输出
- 缺少必要的环境变量设置

### 2. 修复 envd wrapper 脚本

```bash
# 更新 wrapper 脚本
sudo bash -c '
BUILD_ID="9ac9c8b9-9b8b-476c-9238-8266af308c32"
ROOTFS="/mnt/sdb/e2b-storage/e2b-template-storage/$BUILD_ID/rootfs.ext4"

mount -o loop $ROOTFS /mnt/e2b-rootfs 2>/dev/null

cat > /mnt/e2b-rootfs/usr/local/bin/envd <<'"'"'WRAPPER_EOF'"'"'
#!/bin/sh
# Fixed envd Wrapper

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
exec > /dev/ttyS0 2>&1

echo "--- [GUEST] envd wrapper started ---"

# Start envd on default port 49983
exec /usr/local/bin/envd.real
WRAPPER_EOF

chmod +x /mnt/e2b-rootfs/usr/local/bin/envd
sync
umount /mnt/e2b-rootfs 2>/dev/null
'
```

### 3. 清理缓存

```bash
# 清理所有 E2B 缓存，强制使用新的 rootfs
sudo bash -c '
BUILD_ID="9ac9c8b9-9b8b-476c-9238-8266af308c32"
rm -rf /mnt/sdb/e2b-storage/e2b-chunk-cache/$BUILD_ID
rm -rf /mnt/sdb/e2b-storage/e2b-template-cache/$BUILD_ID
rm -rf /mnt/sdb/e2b-storage/e2b-sandbox-cache/*
echo "✓ 缓存已清理"
'
```

### 4. 验证修复

```bash
# 重启 orchestrator 服务
nomad job restart orchestrator

# 创建新沙箱测试
curl -X POST http://localhost:3000/sandboxes \
  -H "Content-Type: application/json" \
  -H "X-API-Key: e2b_53ae1fed82754c17ad8077fbc8bcdd90" \
  -d '{"templateID": "9ac9c8b9-9b8b-476c-9238-8266af308c32"}'

# 检查 envd 健康状态
SANDBOX_ID="<返回的沙箱ID>"
sudo ip netns exec ns-X curl -s http://169.254.0.21:49983/health
# 预期输出: {"status":"ok"}
```

## 根本原因

1. **envd wrapper 脚本配置错误**
   - 使用了不支持的 `--debug` 参数
   - 缺少正确的 PATH 环境变量
   - 输出重定向配置不当

2. **缓存机制导致旧配置持续生效**
   - 修改 rootfs 后，缓存未清理
   - orchestrator 继续使用缓存的旧 rootfs

## 解决方案

### 短期修复（已实施）

1. 修复 envd wrapper 脚本
2. 清理所有相关缓存
3. 重启 orchestrator 服务

### 长期改进

1. **自动化 rootfs 构建**
   ```bash
   # 使用 build-template 工具
   /home/primihub/pcloud/infra/packages/orchestrator/bin/build-template \
     --dockerfile /path/to/Dockerfile \
     --output /mnt/sdb/e2b-storage/e2b-template-storage/
   ```

2. **添加健康检查**
   - 在沙箱创建后自动验证 envd 可访问性
   - 失败时自动清理并重试

3. **改进日志记录**
   - 在 wrapper 脚本中添加详细日志
   - 将日志输出到 /dev/ttyS0（串口）以便调试

4. **缓存失效机制**
   - rootfs 更新时自动清理相关缓存
   - 添加版本标识避免使用过期缓存

## 相关文件

- **rootfs 位置**: `/mnt/sdb/e2b-storage/e2b-template-storage/<BUILD_ID>/rootfs.ext4`
- **envd wrapper**: `/usr/local/bin/envd` (rootfs 内)
- **envd binary**: `/usr/local/bin/envd.real` (rootfs 内)
- **init 脚本**: `/sbin/init` (rootfs 内)
- **orchestrator 配置**: `/home/primihub/pcloud/infra/local-deploy/jobs/orchestrator.hcl`

## 验证清单

- [ ] envd wrapper 脚本语法正确
- [ ] envd.real binary 存在且可执行
- [ ] 缓存已清理
- [ ] orchestrator 服务已重启
- [ ] 新沙箱可以成功创建
- [ ] envd 健康检查返回 200 OK
- [ ] 代码执行功能正常

## 参考命令

```bash
# 检查 rootfs 内容
sudo bash -c '
mount -o loop /mnt/sdb/e2b-storage/e2b-template-storage/<BUILD_ID>/rootfs.ext4 /mnt/e2b-rootfs
cat /mnt/e2b-rootfs/usr/local/bin/envd
ls -lh /mnt/e2b-rootfs/usr/local/bin/envd*
umount /mnt/e2b-rootfs
'

# 清理缓存
sudo rm -rf /mnt/sdb/e2b-storage/e2b-*-cache/*

# 查看沙箱日志
nomad alloc logs <alloc-id> orchestrator

# 测试网络连通性
sudo ip netns exec ns-X curl -v http://169.254.0.21:49983/health
```

## 经验教训

1. **修改 rootfs 后必须清理缓存** - 否则更改不会生效
2. **wrapper 脚本要保持简单** - 避免复杂的逻辑和参数
3. **日志输出很重要** - 使用 /dev/ttyS0 可以在 VM 外部看到日志
4. **验证 binary 兼容性** - 确保 envd.real 在 rootfs 环境中可以运行

## 后续工作

- [ ] 编写自动化测试脚本验证 envd 启动
- [ ] 添加 CI/CD 流程自动构建和测试 rootfs
- [ ] 文档化 rootfs 构建和更新流程
- [ ] 实现缓存自动失效机制
