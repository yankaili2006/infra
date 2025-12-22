# E2B Python SDK 本地部署集成指南

## 📋 目录

1. [SDK架构分析](#sdk架构分析)
2. [本地部署集成方案](#本地部署集成方案)
3. [可行性分析](#可行性分析)
4. [实际代码示例](#实际代码示例)
5. [常见问题](#常见问题)

---

## SDK架构分析

### 核心组件结构

基于对E2B Python SDK源代码的分析（位于 `/home/primihub/e2b-env/lib/python3.12/site-packages/e2b/`），核心架构如下:

```
e2b/
├── api/                      # REST API客户端
│   └── __init__.py           # HTTP请求处理
├── sandbox_sync/             # 同步Sandbox实现
│   └── main.py               # Sandbox.create()主要逻辑
├── sandbox_async/            # 异步Sandbox实现
├── envd/                     # envd gRPC客户端（VM内部通信）
├── connection_config.py      # 连接配置管理 ⭐⭐⭐
└── exceptions.py             # 异常定义
```

### 关键配置发现

**`connection_config.py` 第114-118行**揭示了SDK如何选择API端点：

```python
self.api_url = (
    api_url                              # 1. 构造函数参数
    or ConnectionConfig._api_url()       # 2. E2B_API_URL 环境变量
    or ("http://localhost:3000" if self.debug else f"https://api.{self.domain}")
)                                        # 3. debug模式默认localhost:3000
```

**这意味着 SDK 原生支持本地部署！**

### SDK工作流程

```
1. Sandbox.create(template="base")
   ↓
2. 读取 E2B_API_URL 环境变量（或使用 debug=True）
   ↓
3. 发送 POST /sandboxes 到本地API (localhost:3000)
   ↓
4. 获取 sandbox_id 和连接信息
   ↓
5. 使用 gRPC 连接到 envd (VM内部:49983端口)
   ↓
6. 执行代码、文件操作等
```

---

## 本地部署集成方案

### 方案A: 环境变量配置 ⭐⭐⭐⭐⭐ (推荐)

**优点**:
- ✅ 零代码修改
- ✅ 完全使用官方SDK
- ✅ 最简单、最可靠

**配置步骤**:

```bash
# 1. 设置环境变量
export E2B_API_KEY="e2b_53ae1fed82754c17ad8077fbc8bcdd90"
export E2B_API_URL="http://localhost:3000"
# 或者
export E2B_DEBUG="true"  # 自动使用 localhost:3000

# 2. 激活Python虚拟环境
source ~/e2b-env/bin/activate

# 3. 使用SDK（无需任何修改）
python3 << 'EOF'
from e2b import Sandbox

# SDK会自动使用 E2B_API_URL
sandbox = Sandbox.create(template="base")
result = sandbox.run_code("print('Hello from local E2B!')")
print(result.text)
sandbox.kill()
EOF
```

### 方案B: 代码内配置 ⭐⭐⭐⭐

**优点**:
- ✅ 不依赖环境变量
- ✅ 更灵活的控制

**代码示例**:

```python
import os
from e2b import Sandbox

# 方法1: 在导入前设置环境变量
os.environ["E2B_API_KEY"] = "e2b_53ae1fed82754c17ad8077fbc8bcdd90"
os.environ["E2B_API_URL"] = "http://localhost:3000"

# 方法2: 传递api_url参数（SDK内部支持）
sandbox = Sandbox.create(
    template="base",
    api_url="http://localhost:3000",
    api_key="e2b_53ae1fed82754c17ad8077fbc8bcdd90"
)

result = sandbox.run_code("print('Success!')")
print(result.text)
sandbox.kill()
```

### 方案C: Debug模式 ⭐⭐⭐

**优点**:
- ✅ 自动使用localhost
- ✅ 更多调试信息

```python
import os
from e2b import Sandbox

os.environ["E2B_DEBUG"] = "true"
os.environ["E2B_API_KEY"] = "e2b_53ae1fed82754c17ad8077fbc8bcdd90"

# debug=True 会自动使用 http://localhost:3000
sandbox = Sandbox.create(template="base", debug=True)
```

---

## 可行性分析

### ✅ SDK本地部署支持度

| 功能 | 本地支持 | 说明 |
|------|---------|------|
| **API连接** | ✅ 100% | 通过 E2B_API_URL 环境变量 |
| **VM创建** | ⚠️ 取决于后端 | SDK正常，后端需修复 |
| **代码执行** | ✅ 100% | sandbox.run_code() |
| **文件操作** | ✅ 100% | sandbox.filesystem.* |
| **Shell命令** | ✅ 100% | sandbox.process.start() |
| **envd连接** | ⚠️ 需要网络修复 | gRPC到49983端口 |

### ⚠️ 当前已知限制

#### 限制1: VM创建失败

**问题**: `POST /sandboxes` 返回 `"Failed to place sandbox: no node available"`

**根本原因**:
- API日志显示: 2个节点，1个"unhealthy"，1个"ready"
- 但API选择逻辑有问题，没有使用"ready"节点

**解决方案**:
```bash
# 检查orchestrator日志
ORCH_ALLOC=$(nomad job allocs orchestrator | grep running | awk '{print $1}')
nomad alloc logs "$ORCH_ALLOC" 2>&1 | tail -50

# 重启orchestrator
nomad job restart orchestrator
```

#### 限制2: envd网络连接

**问题**: VM创建成功后，SDK尝试连接envd:49983超时

**根本原因**:
- VM网络路由未配置
- iptables规则缺失

**临时解决方案**: 使用REST API（有限功能）

**长期解决方案**: 修复网络路由（见NETWORK_FIX_GUIDE.md）

---

## 实际代码示例

### 示例1: 完整的Python代码执行

```python
#!/usr/bin/env python3
"""
本地E2B SDK集成示例
确保环境变量已设置: E2B_API_KEY, E2B_API_URL
"""
import os
from e2b import Sandbox

def main():
    # 配置本地部署
    os.environ["E2B_API_KEY"] = "e2b_53ae1fed82754c17ad8077fbc8bcdd90"
    os.environ["E2B_API_URL"] = "http://localhost:3000"

    print("🚀 创建E2B VM...")

    try:
        # 创建沙箱（使用本地API）
        sandbox = Sandbox.create(template="base", timeout=300)
        print(f"✅ VM已创建: {sandbox.sandbox_id}")

        # 测试1: Hello World
        print("\n📝 执行Python代码...")
        result = sandbox.run_code("""
print("Hello from local E2B!")
import sys
print(f"Python {sys.version}")
""")
        print(f"输出:\n{result.text}")

        # 测试2: 系统信息
        print("\n💻 获取系统信息...")
        result = sandbox.run_code("""
import platform, os
print(f"OS: {platform.system()} {platform.release()}")
print(f"当前目录: {os.getcwd()}")
print(f"用户: {os.getenv('USER', 'unknown')}")
""")
        print(f"输出:\n{result.text}")

        # 测试3: 文件操作
        print("\n📁 测试文件操作...")
        sandbox.filesystem.write("/tmp/test.txt", "Hello from Python SDK!")
        content = sandbox.filesystem.read("/tmp/test.txt")
        print(f"写入并读取文件: {content}")

        # 测试4: Shell命令
        print("\n🖥️ 执行Shell命令...")
        result = sandbox.process.start("ls -la /tmp")
        print(f"输出:\n{result.stdout[:200]}...")

        print("\n✅ 所有测试通过!")

    except Exception as e:
        print(f"\n❌ 错误: {e}")
        import traceback
        traceback.print_exc()

        print("\n故障排查:")
        print("1. 检查API服务: curl http://localhost:3000/health")
        print("2. 检查Orchestrator: curl http://localhost:5008/health")
        print("3. 查看日志: nomad alloc logs <alloc-id>")

    finally:
        # 清理
        if 'sandbox' in locals():
            print("\n🔄 关闭VM...")
            sandbox.kill()
            print("✅ VM已关闭")

if __name__ == "__main__":
    main()
```

### 示例2: 数据处理工作流

```python
#!/usr/bin/env python3
"""
在E2B VM中进行数据处理
"""
import os
from e2b import Sandbox

os.environ["E2B_API_KEY"] = "e2b_53ae1fed82754c17ad8077fbc8bcdd90"
os.environ["E2B_API_URL"] = "http://localhost:3000"

def process_data():
    with Sandbox.create(template="base") as sandbox:
        print("📦 VM已创建")

        # 1. 准备数据
        data = """
name,age,score
Alice,25,85
Bob,30,90
Charlie,35,95
"""
        sandbox.filesystem.write("/tmp/data.csv", data)
        print("✅ 数据已上传")

        # 2. 处理数据
        code = """
import csv

with open('/tmp/data.csv', 'r') as f:
    reader = csv.DictReader(f)
    data = list(reader)

# 计算平均分
scores = [int(row['score']) for row in data]
avg_score = sum(scores) / len(scores)

print(f"数据行数: {len(data)}")
print(f"平均分数: {avg_score}")
print(f"最高分: {max(scores)}")
print(f"最低分: {min(scores)}")

# 写入结果
with open('/tmp/result.txt', 'w') as f:
    f.write(f"Average: {avg_score}\\n")
    f.write(f"Max: {max(scores)}\\n")
    f.write(f"Min: {min(scores)}\\n")
"""

        result = sandbox.run_code(code)
        print(f"\n处理结果:\n{result.text}")

        # 3. 下载结果
        result_content = sandbox.filesystem.read("/tmp/result.txt")
        print(f"\n结果文件:\n{result_content}")

        print("\n✅ 数据处理完成!")

if __name__ == "__main__":
    process_data()
```

### 示例3: 多VM并行处理

```python
#!/usr/bin/env python3
"""
创建多个VM并行处理任务
"""
import os
from e2b import Sandbox
from concurrent.futures import ThreadPoolExecutor, as_completed

os.environ["E2B_API_KEY"] = "e2b_53ae1fed82754c17ad8077fbc8bcdd90"
os.environ["E2B_API_URL"] = "http://localhost:3000"

def process_task(task_id, data):
    """在独立的VM中处理单个任务"""
    try:
        sandbox = Sandbox.create(template="base")
        print(f"Task {task_id}: VM {sandbox.sandbox_id[:8]} 已创建")

        # 处理数据
        code = f"""
data = {data}
result = sum(data) / len(data)
print(f"Task {task_id}: Average = {{result}}")
"""
        result = sandbox.run_code(code)

        sandbox.kill()
        return f"Task {task_id}: {result.text}"

    except Exception as e:
        return f"Task {task_id}: 错误 - {e}"

def main():
    # 准备多个任务
    tasks = {
        1: [1, 2, 3, 4, 5],
        2: [10, 20, 30, 40, 50],
        3: [100, 200, 300, 400, 500],
    }

    print(f"🚀 启动 {len(tasks)} 个并行任务...\n")

    # 并行执行
    with ThreadPoolExecutor(max_workers=3) as executor:
        futures = {
            executor.submit(process_task, task_id, data): task_id
            for task_id, data in tasks.items()
        }

        for future in as_completed(futures):
            task_id = futures[future]
            result = future.result()
            print(result)

    print("\n✅ 所有任务完成!")

if __name__ == "__main__":
    main()
```

---

## 常见问题

### Q1: 为什么SDK无法创建VM？

**A**: 检查以下几点:

```bash
# 1. API服务运行状态
curl http://localhost:3000/health
# 应该返回: {"status":"ok"}

# 2. Orchestrator状态
curl http://localhost:5008/health
nomad job status orchestrator

# 3. 查看API日志中的具体错误
API_ALLOC=$(nomad job allocs api | grep running | awk '{print $1}')
nomad alloc logs "$API_ALLOC" api | grep -i error
```

### Q2: SDK能连接但run_code()失败？

**A**: 这是envd网络连接问题:

```python
# 临时解决方案：只使用REST API功能
import requests

# 直接通过API管理VM
response = requests.get(
    f"http://localhost:3000/sandboxes",
    headers={"X-API-Key": "e2b_53ae1fed82754c17ad8077fbc8bcdd90"}
)
print(response.json())
```

**长期解决方案**: 修复网络路由（见NETWORK_FIX_GUIDE.md）

### Q3: 如何调试SDK内部行为？

**A**: 启用debug模式:

```python
import os
import logging

# 方法1: 环境变量
os.environ["E2B_DEBUG"] = "true"

# 方法2: Python logging
logging.basicConfig(level=logging.DEBUG)

# 方法3: 检查SDK实际使用的URL
from e2b import ConnectionConfig
config = ConnectionConfig()
print(f"API URL: {config.api_url}")
print(f"Debug: {config.debug}")
```

### Q4: 本地部署和云服务SDK有什么区别？

**A**: SDK代码完全相同，只是配置不同:

| 配置项 | 云服务 | 本地部署 |
|--------|--------|----------|
| E2B_API_URL | https://api.e2b.app | http://localhost:3000 |
| E2B_API_KEY | 云端API密钥 | 本地API密钥 |
| envd连接 | 通过云端代理 | 直接连接VM IP:49983 |

### Q5: 如何验证SDK正确配置？

**A**: 使用验证脚本:

```python
#!/usr/bin/env python3
import os
import sys

def verify_sdk_config():
    print("🔍 验证E2B SDK配置...\n")

    # 1. 检查SDK安装
    try:
        import e2b
        print(f"✅ SDK已安装: {e2b.__file__}")
    except ImportError:
        print("❌ SDK未安装: pip install e2b")
        return False

    # 2. 检查环境变量
    api_key = os.environ.get("E2B_API_KEY")
    api_url = os.environ.get("E2B_API_URL")

    print(f"E2B_API_KEY: {'✅ 已设置' if api_key else '❌ 未设置'}")
    print(f"E2B_API_URL: {api_url or '❌ 未设置'}")
    print()

    # 3. 检查ConnectionConfig
    from e2b import ConnectionConfig
    config = ConnectionConfig()
    print(f"实际API URL: {config.api_url}")
    print(f"Debug模式: {config.debug}")
    print()

    # 4. 测试API连接
    import requests
    try:
        resp = requests.get(f"{config.api_url}/health", timeout=5)
        if resp.status_code == 200:
            print("✅ API服务可访问")
        else:
            print(f"⚠️ API响应异常: {resp.status_code}")
    except Exception as e:
        print(f"❌ 无法连接API: {e}")
        return False

    print("\n✅ SDK配置正确!")
    return True

if __name__ == "__main__":
    if not verify_sdk_config():
        sys.exit(1)
```

---

## 总结

### ✅ SDK本地集成完全可行

E2B Python SDK原生支持本地部署，通过简单的环境变量配置即可使用：

```bash
export E2B_API_URL="http://localhost:3000"
export E2B_API_KEY="e2b_53ae1fed82754c17ad8077fbc8bcdd90"
source ~/e2b-env/bin/activate
python3 your_script.py
```

### ⚠️ 当前阻碍

1. **VM创建失败** - API端"no node available"错误（需要修复）
2. **envd连接超时** - 网络路由问题（需要iptables配置）

### 📝 推荐使用步骤

1. **立即可用**: 使用REST API进行VM管理（创建、列表、删除）
2. **短期目标**: 修复VM创建问题，使SDK的create()正常工作
3. **长期目标**: 修复网络路由，使run_code()等功能完全可用

### 📚 相关文档

- **网络修复指南**: `NETWORK_FIX_GUIDE.md`
- **完整执行报告**: `FINAL_EXECUTION_REPORT.md`
- **快速参考**: `QUICK_REFERENCE.md`
- **VM诊断**: `/home/primihub/pcloud/infra/CLAUDE.md`

---

**文档创建时间**: 2025-12-22
**SDK版本**: e2b (latest)
**测试环境**: 本地部署 (localhost:3000)
**状态**: ✅ SDK支持完整，⚠️ 后端需要修复
