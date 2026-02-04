# Orchestrator Sudo Environment Fix

## 问题描述

Orchestrator 服务启动失败，错误信息：
```
sudo: sorry, you are not allowed to preserve the environment
```

## 根本原因

orchestrator.hcl 文件中使用了 `sudo -E` 命令来保留环境变量，但 sudoers 配置不允许 `SETENV` 权限。实际上 `-E` 参数是不必要的，因为环境变量已经在 Nomad job 的 `env` 块中设置。

## 解决方案

移除 orchestrator.hcl 中 sudo 命令的 `-E` 参数。

### 修改前
```hcl
config {
  command = "sudo"
  args    = ["-E", "/mnt/data1/pcloud/infra/local-deploy/scripts/start-orchestrator.sh"]
}
```

### 修改后
```hcl
config {
  command = "sudo"
  args    = ["/mnt/data1/pcloud/infra/local-deploy/scripts/start-orchestrator.sh"]
}
```

## 使用自动修复脚本

### 快速修复
```bash
cd /mnt/data1/pcloud/infra/local-deploy/scripts
./fix-orchestrator-sudo.sh
```

### 脚本功能
1. ✓ 检查 orchestrator 当前状态
2. ✓ 自动备份 HCL 文件
3. ✓ 移除 `-E` 参数
4. ✓ 重启 orchestrator 服务
5. ✓ 验证服务状态
6. ✓ 检查日志确认无错误

### 脚本输出示例
```
=== Orchestrator Sudo Fix Script ===
Date: Tue Feb  4 16:30:00 CST 2026

Step 1: Checking orchestrator status...
⚠ Orchestrator is not running or has issues

Step 2: Creating backup of orchestrator.hcl...
✓ Backup created: /mnt/data1/pcloud/infra/local-deploy/jobs/orchestrator.hcl.backup.20260204_163000

Step 3: Checking for -E flag in HCL file...
✓ Found -E flag in HCL file

Step 4: Removing -E flag from sudo command...
✓ Removed -E flag from HCL file

Step 5: Verifying the change...
New args line:
    args    = ["/mnt/data1/pcloud/infra/local-deploy/scripts/start-orchestrator.sh"]

Step 6: Restarting orchestrator service...
✓ Orchestrator job restarted

Step 7: Waiting for orchestrator to start (15 seconds)...

Step 8: Checking orchestrator status...
✓ Orchestrator is running

Step 9: Checking logs for errors...
Allocation ID: 06b36305
✓ No sudo errors found in logs

=== Fix completed successfully! ===
```

## 手动修复步骤

如果需要手动修复：

### 1. 备份文件
```bash
cp /mnt/data1/pcloud/infra/local-deploy/jobs/orchestrator.hcl \
   /mnt/data1/pcloud/infra/local-deploy/jobs/orchestrator.hcl.backup
```

### 2. 编辑 HCL 文件
```bash
vim /mnt/data1/pcloud/infra/local-deploy/jobs/orchestrator.hcl
```

找到第 47 行，将：
```hcl
args    = ["-E", "/mnt/data1/pcloud/infra/local-deploy/scripts/start-orchestrator.sh"]
```

修改为：
```hcl
args    = ["/mnt/data1/pcloud/infra/local-deploy/scripts/start-orchestrator.sh"]
```

### 3. 重启服务
```bash
nomad job stop orchestrator
sleep 3
nomad job run /mnt/data1/pcloud/infra/local-deploy/jobs/orchestrator.hcl
```

### 4. 验证状态
```bash
# 检查服务状态
nomad job status orchestrator

# 查看日志
ALLOC_ID=$(nomad job allocs orchestrator | grep running | head -1 | awk '{print $1}')
nomad alloc logs $ALLOC_ID orchestrator 2>&1 | tail -20
```

## 验证修复成功

### 1. 检查 Orchestrator 日志
应该看到正常的启动日志，没有 sudo 错误：
```
INFO  VNC port forwarding established
INFO  Native Go TCP proxy network bridge established successfully
INFO  Socat bridge setup successful
```

### 2. 测试 Fragments 预览功能
```bash
curl -X POST http://localhost:3001/api/sandbox \
  -H "Content-Type: application/json" \
  -d '{"fragment":{"template":"code-interpreter-v1","code":"print(\"Hello World\")\nprint(\"2 + 2 =\", 2 + 2)"}}'
```

预期输出：
```json
{
  "sbxId": "...",
  "template": "code-interpreter-v1",
  "stdout": ["Hello World\n2 + 2 = 4\n"],
  "stderr": [],
  "cellResults": []
}
```

## 相关文件

- **HCL 配置**: `/mnt/data1/pcloud/infra/local-deploy/jobs/orchestrator.hcl`
- **启动脚本**: `/mnt/data1/pcloud/infra/local-deploy/scripts/start-orchestrator.sh`
- **修复脚本**: `/mnt/data1/pcloud/infra/local-deploy/scripts/fix-orchestrator-sudo.sh`
- **Sudoers 配置**: `/etc/sudoers.d/e2b-orchestrator`

## 故障排查

### 问题：脚本运行后仍然失败

**检查 sudoers 配置**：
```bash
sudo cat /etc/sudoers.d/e2b-orchestrator
```

应该包含：
```
Defaults!/mnt/data1/pcloud/infra/local-deploy/scripts/start-orchestrator.sh !env_reset
primihub ALL=(ALL) NOPASSWD: /mnt/data1/pcloud/infra/local-deploy/scripts/start-orchestrator.sh
```

### 问题：Orchestrator 启动但无法创建 sandbox

**检查 API 服务**：
```bash
curl http://localhost:3000/health
nomad job status api
```

**检查网络配置**：
```bash
# 查看网络命名空间
sudo ip netns list

# 查看 Firecracker 进程
ps aux | grep firecracker
```

## 技术细节

### 为什么 -E 参数不需要？

1. **环境变量已在 Nomad 中设置**：orchestrator.hcl 的 `env` 块已经定义了所有必需的环境变量
2. **start-orchestrator.sh 会重新设置**：启动脚本会从配置文件加载环境变量
3. **-E 需要 SETENV 权限**：使用 `-E` 需要在 sudoers 中配置 `SETENV`，增加了复杂性

### Sudoers 配置说明

```
Defaults!/path/to/script !env_reset
```
- `Defaults!` 指定特定命令的默认行为
- `!env_reset` 禁用环境变量重置（保留当前环境）

```
primihub ALL=(ALL) NOPASSWD: /path/to/script
```
- `primihub` 用户可以无密码执行指定脚本
- `ALL=(ALL)` 可以以任何用户身份执行
- `NOPASSWD:` 不需要输入密码

## 更新日志

- **2026-02-04**: 初始版本，修复 sudo -E 环境保留问题
- **2026-02-04**: 创建自动修复脚本和文档

## 参考资料

- [CLAUDE.md - Orchestrator Sudo Issues](/mnt/data1/pcloud/infra/CLAUDE.md)
- [Nomad Job Specification](https://developer.hashicorp.com/nomad/docs/job-specification)
- [Sudoers Manual](https://www.sudo.ws/docs/man/sudoers.man/)
