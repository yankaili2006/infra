# E2B 虚拟机创建故障排查文档

## 问题概述
在本地部署环境中创建 E2B 沙箱虚拟机时遇到权限问题。

## 遇到的问题

### 问题1: 网络命名空间权限错误
**错误信息**:
```
[ERROR] [network slot pool]: failed to create network
error: cannot create new namespace: open /run/netns/ns-2: permission denied
```

**原因**:
Orchestrator需要特殊权限来创建Linux网络命名空间，但以普通用户权限运行时无法访问 `/run/netns/` 目录。

**尝试的解决方案1** (失败):
```bash
# 添加 Linux capabilities
sudo setcap cap_net_admin,cap_sys_admin+ep /home/primihub/pcloud/infra/packages/orchestrator/bin/orchestrator

# 修改目录权限
sudo chown primihub:primihub /run/netns
```
结果：仍然失败，因为 iptables 操作也需要 root 权限。

### 问题2: iptables 权限错误
**错误信息**:
```
[ERROR] [network slot pool]: failed to create network
error creating postrouting rule to vpeer: running [/usr/sbin/iptables -t nat -A POSTROUTING...]
iptables v1.8.10 (nf_tables): Could not fetch rule set generation id: Permission denied (you must be root)
```

**原因**:
Orchestrator需要修改 iptables 规则来设置网络 NAT，这需要 root 权限。

### 问题3: sudo 环境变量传递问题
**错误信息**:
```
panic: Required environment variable "NODE_ID" is not set
```

**原因**:
当通过 sudo 运行时，默认情况下环境变量不会传递给被执行的程序。

## 最终解决方案

### 步骤1: 配置 sudoers
创建 sudoers 配置文件，允许 orchestrator 以 root 权限运行并保留环境变量：

```bash
cat > /tmp/orchestrator_sudoers << 'EOF'
# Allow primihub to run orchestrator without password and preserve environment
Defaults!/home/primihub/pcloud/infra/packages/orchestrator/bin/orchestrator !env_reset
primihub ALL=(ALL) NOPASSWD:SETENV: /home/primihub/pcloud/infra/packages/orchestrator/bin/orchestrator
EOF

sudo cp /tmp/orchestrator_sudoers /etc/sudoers.d/orchestrator
sudo chmod 0440 /etc/sudoers.d/orchestrator
```

### 步骤2: 修改 Nomad Job 配置
更新 `/home/primihub/pcloud/infra/local-deploy/jobs/orchestrator.hcl`:

```hcl
task "orchestrator" {
  driver = "raw_exec"

  config {
    command = "sudo"
    args    = ["-E", "/home/primihub/pcloud/infra/packages/orchestrator/bin/orchestrator"]
  }

  env {
    NODE_ID     = "${node.unique.name}"
    ENVIRONMENT = "local"
    # ... 其他环境变量
  }
}
```

关键变更：
- 使用 `sudo` 作为 command
- 添加 `-E` 参数保留环境变量
- 将 orchestrator 路径作为参数传递

### 步骤3: 重启 Orchestrator
```bash
nomad job stop orchestrator
nomad job run /home/primihub/pcloud/infra/local-deploy/jobs/orchestrator.hcl
```

### 步骤4: 验证状态
```bash
# 检查 orchestrator 状态
nomad job status orchestrator

# 检查健康状态
curl http://localhost:5008/health

# 查看日志
nomad alloc logs <allocation-id> orchestrator
```

## 验证虚拟机创建

创建沙箱虚拟机：
```bash
curl -X POST http://localhost:3000/sandboxes \
  -H "Content-Type: application/json" \
  -H "X-API-Key: e2b_53ae1fed82754c17ad8077fbc8bcdd90" \
  -d '{
    "templateID": "base",
    "timeout": 300
  }'
```

## 已知限制

### NBD Pool 问题
即使 orchestrator 正常运行，可能会看到以下警告：
```
[ERROR] [nbd pool]: failed to create network: no free slots
```

这是 NBD（Network Block Device）池资源限制的问题，不影响基本功能。

## 架构说明

### E2B 组件架构
```
Client → API (port 3000)
         ↓
      Orchestrator (port 5008, requires root)
         ↓
      Firecracker microVMs
         ↓
      Envd (in-VM daemon, port 49983)
```

### 权限要求
- **API**: 普通用户权限
- **Orchestrator**: Root 权限（网络命名空间、iptables、Firecracker）
- **Firecracker**: Root 权限（KVM访问、网络设备）

## 调试技巧

### 查看详细日志
```bash
# Orchestrator 日志
nomad alloc logs <alloc-id> orchestrator

# stderr 日志
nomad alloc fs <alloc-id> alloc/logs/orchestrator.stderr.0

# API 日志
docker logs e2b-api

# 实时跟踪
nomad alloc logs -f <alloc-id> orchestrator
```

### 检查网络状态
```bash
# 查看网络命名空间
sudo ip netns list

# 查看 iptables 规则
sudo iptables -t nat -L -n -v

# 检查 Firecracker 进程
ps aux | grep firecracker
```

### 检查 Nomad 资源
```bash
# 查看所有 jobs
nomad job status

# 查看节点状态
nomad node status

# 查看 allocations
nomad alloc status <alloc-id>
```

## 相关文档

- E2B 架构: `/home/primihub/pcloud/infra/CLAUDE.md`
- Orchestrator 配置: `/home/primihub/pcloud/infra/local-deploy/jobs/orchestrator.hcl`
- 本地部署指南: `/home/primihub/pcloud/infra/local-deploy/README.md`

## 创建日期
2025-12-14

## 更新记录
- 2025-12-14: 初始版本，记录权限问题和解决方案
