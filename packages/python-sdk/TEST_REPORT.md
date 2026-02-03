# E2B Python 代码测试报告

**测试时间**: 2026-01-14 09:00-09:03
**目标**: 在 E2B 虚拟机中执行 Python 代码

## ✅ 成功完成的部分

### 1. E2B 服务启动 ✅

- **Consul**: 运行在 localhost:8500
  ```bash
  curl http://localhost:8500/v1/status/leader
  # 输出: "127.0.0.1:8300"
  ```

- **Nomad**: 运行并管理作业
  ```bash
  nomad node status
  # 输出: primihub节点 ready
  ```

- **E2B API**: 健康检查通过
  ```bash
  curl http://localhost:3000/health
  # 输出: Health check successful
  ```

- **Orchestrator**: 正在运行

### 2. 虚拟机创建 ✅

成功创建了 4 个 Firecracker 虚拟机：

| 沙箱 ID | 状态 | CPU | 内存 | 模板 |
|---------|------|-----|------|------|
| iy77qn7529eejtj9787x4 | running | 2核 | 512MB | base |
| itucrv9f3m1l9gfh50mif | running | 2核 | 512MB | base |
| iudig3quagmmybxz2ltcf | running | 2核 | 512MB | base |
| i0bmexgqukx2uwj4iz8u5 | running | 2核 | 512MB | base |

**Firecracker 进程验证**:
```bash
$ ps aux | grep firecracker
root  3689537  /home/primihub/pcloud/infra/packages/fc-versions/builds/v1.12.1_d990331/firecracker
root  3691721  /home/primihub/pcloud/infra/packages/fc-versions/builds/v1.12.1_d990331/firecracker
root  3692198  /home/primihub/pcloud/infra/packages/fc-versions/builds/v1.12.1_d990331/firecracker
root  3693130  /home/primihub/pcloud/infra/packages/fc-versions/builds/v1.12.1_d990331/firecracker
```

### 3. Python SDK 集成 ✅

- SDK 已安装在 `/home/primihub/pcloud/infra/packages/python-sdk/`
- 环境配置已加载 (`.env.local`)
- API 连接成功
- 沙箱创建 API 工作正常

## ⚠️ 遇到的问题

### 问题: envd 服务连接失败

**症状**:
```python
sandbox = Sandbox.create(template='base')  # ✅ 成功
result = sandbox.commands.run('echo Hello')  # ❌ 连接失败

# 错误信息
httpcore.ConnectError: [Errno 111] Connection refused
```

**原因分析**:

1. **VM 创建成功** - Firecracker 进程在运行
2. **API 通信正常** - 可以列出和创建沙箱
3. **envd 无法访问** - 无法连接到 VM 内的 envd 守护进程（端口 49983）

**可能的根本原因**:

根据 `/home/primihub/pcloud/infra/CLAUDE.md` 文档：
- envd 初始化失败（init 脚本问题）
- 网络配置问题（路由、iptables）
- 沙箱内部服务未启动

## 📝 测试执行记录

### 测试 1: REST API 创建 VM

```python
import requests

response = requests.post(
    "http://localhost:3000/sandboxes",
    headers={"X-API-Key": "e2b_53ae1fed82754c17ad8077fbc8bcdd90"},
    json={"templateID": "base", "timeout": 300}
)

# 结果:
# Status: 201 Created
# Sandbox ID: i0bmexgqukx2uwj4iz8u5
# ✅ 创建成功
```

### 测试 2: Python SDK 创建 VM

```python
from e2b import Sandbox
import dotenv

dotenv.load_dotenv('.env.local')

sandbox = Sandbox.create(template='base', timeout=300)
print(sandbox.sandbox_id)

# 结果:
# Sandbox ID: itucrv9f3m1l9gfh50mif
# ✅ 创建成功
```

### 测试 3: 执行命令（失败）

```python
result = sandbox.commands.run('echo "Hello from VM!"')

# 结果:
# ❌ httpcore.ConnectError: [Errno 111] Connection refused
```

## 🔧 已尝试的排查步骤

1. ✅ 检查 API 健康状态 - 正常
2. ✅ 检查 Nomad 作业状态 - orchestrator 和 api 都在运行
3. ✅ 确认 Firecracker 进程存在 - 4 个进程正在运行
4. ✅ 确认沙箱状态为 "running" - 通过 API 确认
5. ❌ 检查 envd 守护进程日志 - 无法获取
6. ❌ 测试网络连通性 - envd 端口不可访问

## 📚 相关文档参考

从 `/home/primihub/pcloud/infra/CLAUDE.md` 中的相关章节：

### VM Creation Troubleshooting Guide

这是已知问题，有详细的故障排除文档：

**相关章节**:
- "E2B VM Init System Deep Troubleshooting Guide"
- "Issue 6: Persistent ENOENT with Static Binary"
- "Envd Network Connection Issue"

**已知的 envd 网络问题**:
```
Post "http://10.11.13.172:49983/init": dial tcp ... connect: no route to host
```

这表明：
- ✅ Kernel 启动成功
- ✅ Init 进程启动
- ✅ VM 网络部分配置
- ⚠️ Guest-to-host 路由需要配置

## 💡 建议的解决方案

根据文档，需要：

1. **检查 init 脚本**:
   - 验证 `/sbin/init` 正确启动
   - 确认 envd 守护进程启动
   - 检查网络配置

2. **网络配置**:
   - 配置 iptables 规则
   - 配置网络桥接
   - 配置 VM 网络接口

3. **使用已有的诊断工具**:
   ```bash
   # 位于 /home/primihub/pcloud/scripts/
   python3 diagnose_vm_creation.py
   ```

## ✅ 验证项清单

### 已完成 ✅

- [x] E2B Consul 服务运行
- [x] E2B Nomad 服务运行
- [x] E2B API 服务运行
- [x] E2B Orchestrator 服务运行
- [x] Python SDK 安装和配置
- [x] 沙箱创建功能
- [x] Firecracker VM 启动

### 待完成 ⚠️

- [ ] envd 守护进程启动验证
- [ ] VM 网络配置验证
- [ ] 命令执行功能
- [ ] 文件系统操作功能
- [ ] Python 代码执行功能

## 🎯 结论

**当前状态**: **部分成功**

✅ **成功的部分**:
- E2B 基础设施完全启动
- VM 创建功能正常
- Python SDK 集成完成
- API 通信正常

⚠️ **需要解决的问题**:
- envd 守护进程连接失败
- 无法在 VM 中执行命令
- 网络配置可能有问题

**下一步**:
1. 参考 `CLAUDE.md` 中的 VM 故障排除指南
2. 检查 envd 初始化日志
3. 配置网络桥接
4. 或使用已修复的模板（如果有）

---

**创建时间**: 2026-01-14 09:03
**测试脚本**:
- `/home/primihub/pcloud/infra/e2b-tools/examples/execute_in_vm.py`
- `/home/primihub/pcloud/infra/packages/python-sdk/test_vm_python.py`
- `/home/primihub/pcloud/infra/packages/python-sdk/example_sync.py`
