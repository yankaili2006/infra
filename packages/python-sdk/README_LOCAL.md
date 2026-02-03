# E2B Python SDK - 本地部署使用指南

本目录包含 E2B Python SDK，已配置为使用本地 pCloud E2B 基础设施。

## 📋 目录结构

```
python-sdk/
├── e2b/                    # E2B SDK 核心代码
├── e2b_connect/            # Connect RPC 客户端
├── .env.local              # 本地环境配置 ⭐
├── example_local.py        # 异步 API 完整示例 ⭐
├── example_sync.py         # 同步 API 简单示例 ⭐
├── example.py              # 官方原始示例
├── pyproject.toml          # 项目配置
└── README_LOCAL.md         # 本文档
```

## 🚀 快速开始

### 1. 确保本地 E2B 服务运行

```bash
# 检查服务状态
curl http://localhost:3000/health

# 如果未运行，启动服务
cd /home/primihub/pcloud/infra/local-deploy
./scripts/start-all.sh
```

### 2. 安装依赖

```bash
cd /home/primihub/pcloud/infra/packages/python-sdk

# 方法 1: 使用 pip（推荐用于快速测试）
pip install python-dotenv httpx

# 方法 2: 使用 poetry（完整开发环境）
poetry install
```

### 3. 运行示例

**同步 API 示例**（推荐新手）：

```bash
python3 example_sync.py
```

**异步 API 示例**（更多功能）：

```bash
python3 example_local.py
```

## 📖 使用说明

### 环境配置

`.env.local` 文件包含本地服务配置：

```env
# API 地址 - 指向本地 API
E2B_API_URL=http://localhost:3000

# API Key - 本地测试密钥
E2B_API_KEY=e2b_53ae1fed82754c17ad8077fbc8bcdd90

# Debug 模式
E2B_DEBUG=true

# 域名（本地）
E2B_DOMAIN=localhost
```

### 基本用法

#### 同步 API

```python
from e2b import Sandbox
import dotenv

dotenv.load_dotenv('.env.local')

# 创建沙箱
with Sandbox.create(
    template="base-template-000-0000-0000-000000000001",
    timeout=300
) as sandbox:
    # 执行命令
    result = sandbox.process.start_and_wait("echo 'Hello E2B!'")
    print(result.stdout)

    # 文件操作
    sandbox.filesystem.write("/tmp/test.txt", "Hello!")
    content = sandbox.filesystem.read("/tmp/test.txt")
    print(content)
```

#### 异步 API

```python
import asyncio
from e2b import AsyncSandbox
import dotenv

dotenv.load_dotenv('.env.local')

async def main():
    # 创建沙箱
    sandbox = await AsyncSandbox.create(
        template="base-template-000-0000-0000-000000000001",
        timeout=300
    )

    # 执行命令
    result = await sandbox.process.start_and_wait("ls -la /")
    print(result.stdout)

    # 关闭沙箱
    await sandbox.close()

asyncio.run(main())
```

## 🎯 可用模板

本地 E2B 提供以下模板：

| Template ID | 描述 |
|-------------|------|
| `base-template-000-0000-0000-000000000001` | 基础 Ubuntu 沙箱 |
| `desktop-template-000-0000-0000-000000000001` | 桌面环境沙箱（包含 VNC） |

## 🔧 API 功能

### 进程管理

```python
# 执行命令并等待
result = sandbox.process.start_and_wait("python3 script.py")

# 后台运行
process = sandbox.process.start("python3 server.py")

# 终止进程
process.kill()
```

### 文件系统

```python
# 写入文件
sandbox.filesystem.write("/path/to/file", "content")

# 读取文件
content = sandbox.filesystem.read("/path/to/file")

# 列出目录
files = sandbox.filesystem.list("/path")

# 创建目录
sandbox.filesystem.make_dir("/new/dir")
```

### 代码执行（Code Interpreter）

如果使用 `e2b-code-interpreter` 包：

```python
from e2b_code_interpreter import Sandbox

with Sandbox.create() as sandbox:
    execution = sandbox.run_code("x = 2 + 2; print(x)")
    print(execution.text)  # 输出: 4
```

## 📊 示例输出

运行 `example_local.py` 的预期输出：

```
============================================================
E2B Local Infrastructure Example
============================================================
API URL: http://localhost:3000
Debug Mode: true
API Key: e2b_53ae1fed82754c...
============================================================
Creating sandbox...
✓ Sandbox created: abc123xyz
  Template: base-template-000-0000-0000-000000000001

Executing command: echo 'Hello from E2B Local!'
  stdout: Hello from E2B Local!
  stderr:
  exit_code: 0

Executing Python code...
  stdout:
Python version: 3.10.12
Hello from Python in E2B sandbox!

Testing filesystem operations...
  ✓ Written to /tmp/test.txt
  ✓ Read from /tmp/test.txt: Hello from E2B Local Infrastructure!
  ✓ Files in /tmp: ['test.txt', ...]

Closing sandbox...
✓ Sandbox closed

============================================================
✓ All tests passed!
============================================================
```

## 🛠️ 故障排除

### 问题 1: 无法连接到 API

**错误信息**:
```
Connection refused to http://localhost:3000
```

**解决方案**:
```bash
# 检查 API 服务是否运行
curl http://localhost:3000/health

# 启动 E2B 服务
cd /home/primihub/pcloud/infra/local-deploy
nomad job run jobs/api.hcl
```

### 问题 2: 模板未找到

**错误信息**:
```
Template 'base' not found
```

**解决方案**:
使用完整的模板 ID：
```python
sandbox = Sandbox.create(
    template="base-template-000-0000-0000-000000000001"  # 完整 ID
)
```

### 问题 3: 依赖缺失

**错误信息**:
```
ModuleNotFoundError: No module named 'dotenv'
```

**解决方案**:
```bash
pip install python-dotenv httpx
```

## 📚 相关文档

- **E2B 官方文档**: https://e2b.dev/docs
- **本地部署文档**: `/home/primihub/pcloud/infra/local-deploy/README.md`
- **API 文档**: `/home/primihub/pcloud/infra/packages/api/`
- **CLAUDE.md**: `/home/primihub/pcloud/infra/CLAUDE.md` （包含 VM 创建故障排除）

## 🔗 相关项目

- **Surf**: `/home/primihub/github/surf` - 集成 E2B Desktop 的 Next.js 应用
- **E2B 上游**: `~/github/E2B` - E2B 官方仓库

## 💡 开发提示

### 调试模式

设置环境变量启用详细日志：

```bash
export E2B_DEBUG=true
python3 example_local.py
```

### 超时配置

默认超时 60 秒，可以调整：

```python
sandbox = Sandbox.create(
    template="base-template-000-0000-0000-000000000001",
    timeout=600  # 10 分钟
)
```

### 代理配置

如果需要通过代理访问：

```python
from e2b import Sandbox

sandbox = Sandbox.create(
    template="...",
    proxy="http://proxy.example.com:8080"
)
```

## ✅ 验证安装

运行验证脚本：

```bash
# 检查依赖
python3 -c "import e2b; print(e2b.__version__)"

# 测试连接
python3 example_sync.py
```

预期看到成功消息表示配置正确。

## 🎉 下一步

1. **运行示例**: 从 `example_sync.py` 开始
2. **查看文档**: 阅读 E2B 官方文档了解更多 API
3. **构建应用**: 基于示例创建自己的 AI 代理应用
4. **参考 Surf**: 查看 `/home/primihub/github/surf` 了解实际集成案例

---

**创建时间**: 2026-01-14
**维护者**: pCloud Team
**状态**: ✅ 可用
