# 在E2B VM中执行程序 - 完整指南

## 📋 概述

本指南介绍如何使用Python在E2B虚拟机中执行程序，包括三种方法：
1. **REST API** - 使用HTTP请求管理VM（最简单）
2. **官方Python SDK** - 使用e2b包（功能最全）
3. **gRPC直接调用** - 连接envd执行命令（最灵活）

## 🚀 快速开始

### 方法1: 使用REST API（推荐入门）

已创建即用脚本：`/home/primihub/pcloud/infra/e2b-tools/examples/execute_in_vm.py`

```bash
# 查看帮助
python3 execute_in_vm.py help

# 运行完整演示
python3 execute_in_vm.py demo

# 查看gRPC示例
python3 execute_in_vm.py grpc

# 查看SDK示例
python3 execute_in_vm.py sdk
```

**功能演示**:
```python
from execute_in_vm import E2BClient

# 创建客户端
client = E2BClient(
    api_url="http://localhost:3000",
    api_key="e2b_53ae1fed82754c17ad8077fbc8bcdd90"
)

# 检查服务
if client.check_health():
    print("API服务正常")

# 创建VM
sandbox_id = client.create_sandbox(template_id="base", timeout=300)

# 获取VM信息
info = client.get_sandbox_info(sandbox_id)
print(f"VM IP: {info['clientID']}")
print(f"CPU: {info['cpuCount']}核")
print(f"内存: {info['memoryMB']}MB")

# 列出所有VM
vms = client.list_sandboxes()
for vm in vms:
    print(f"{vm['sandboxID']} - {vm['state']}")

# 删除VM
client.delete_sandbox(sandbox_id)
```

### 方法2: 使用官方E2B Python SDK

#### 安装SDK

```bash
# 安装e2b包
pip install e2b

# 或在虚拟环境中
python3 -m venv e2b-env
source e2b-env/bin/activate
pip install e2b
```

#### 配置环境变量

```bash
# 设置本地E2B API地址
export E2B_API_KEY="e2b_53ae1fed82754c17ad8077fbc8bcdd90"
export E2B_API_URL="http://localhost:3000"
```

#### 基础使用

```python
from e2b import Sandbox

# 创建沙箱
sandbox = Sandbox(template="base")

print(f"VM已创建: {sandbox.sandbox_id}")
```

#### 执行Python代码

```python
# 方式1: 运行Python代码字符串
result = sandbox.run_code("""
print("Hello from E2B VM!")
import sys
print(f"Python版本: {sys.version}")

# 计算示例
numbers = [1, 2, 3, 4, 5]
total = sum(numbers)
print(f"总和: {total}")
""")

print(result.text)
```

#### 执行Shell命令

```python
# 启动进程并获取输出
process = sandbox.process.start("ls -la /tmp")
print(f"输出: {process.stdout}")
print(f"错误: {process.stderr}")
print(f"退出码: {process.exit_code}")

# 复杂命令
result = sandbox.process.start("""
echo "系统信息:"
uname -a
echo "磁盘使用:"
df -h
echo "内存使用:"
free -h
""")

print(result.stdout)
```

#### 文件操作

```python
# 写入文件
sandbox.filesystem.write("/tmp/hello.txt", "Hello World!")

# 读取文件
content = sandbox.filesystem.read("/tmp/hello.txt")
print(f"文件内容: {content}")

# 上传本地文件
sandbox.upload_file("./local_file.txt", "/tmp/uploaded.txt")

# 下载文件
sandbox.download_file("/tmp/uploaded.txt", "./downloaded.txt")

# 列出目录
files = sandbox.filesystem.list("/tmp")
for file in files:
    print(f"{file.name} ({file.type})")

# 创建目录
sandbox.filesystem.make_dir("/tmp/mydir")

# 删除文件
sandbox.filesystem.remove("/tmp/hello.txt")
```

#### 运行复杂程序

```python
# 创建并运行Python脚本
script = """
import json
import time

def process_data(data):
    result = {
        'processed_at': time.time(),
        'count': len(data),
        'sum': sum(data),
        'average': sum(data) / len(data)
    }
    return result

data = [10, 20, 30, 40, 50]
result = process_data(data)
print(json.dumps(result, indent=2))
"""

sandbox.filesystem.write("/tmp/script.py", script)
process = sandbox.process.start("python3 /tmp/script.py")
print(process.stdout)
```

#### 安装包并运行

```python
# 安装Python包
sandbox.process.start("pip install numpy pandas")

# 使用安装的包
code = """
import numpy as np
import pandas as pd

arr = np.array([1, 2, 3, 4, 5])
print(f"NumPy数组: {arr}")
print(f"平均值: {arr.mean()}")

df = pd.DataFrame({
    'A': [1, 2, 3],
    'B': [4, 5, 6]
})
print("\\nPandas DataFrame:")
print(df)
"""

result = sandbox.run_code(code)
print(result.text)
```

#### 长时间运行的任务

```python
# 后台运行任务
process = sandbox.process.start("""
#!/bin/bash
for i in {1..10}; do
    echo "处理步骤 $i/10"
    sleep 1
done
echo "完成!"
""", background=True)

# 检查进程状态
while process.is_alive():
    print("任务运行中...")
    time.sleep(2)

print("任务完成!")
print(process.stdout)
```

#### 清理和关闭

```python
# 关闭沙箱（自动清理资源）
sandbox.close()

# 或使用上下文管理器（自动关闭）
with Sandbox(template="base") as sandbox:
    result = sandbox.run_code("print('Hello')")
    print(result.text)
# 离开with块时自动关闭
```

### 方法3: 使用gRPC直接调用envd

这是最底层的方式，直接连接到VM内的envd服务。

#### 安装依赖

```bash
pip install grpcio grpcio-tools protobuf
```

#### 获取Proto文件

```bash
# Proto文件位置
ls /home/primihub/pcloud/infra/packages/shared/pkg/grpc/envd/
```

#### 生成Python代码

```bash
cd /home/primihub/pcloud/infra/packages/shared/pkg/grpc/envd

python3 -m grpc_tools.protoc \
  -I. \
  --python_out=. \
  --grpc_python_out=. \
  process.proto filesystem.proto
```

#### 连接到envd执行命令

```python
import grpc
from process_pb2 import StartRequest, ProcessConfig
from process_pb2_grpc import ProcessServiceStub

# 获取VM的IP地址（通过API）
sandbox_id = "your-sandbox-id"
resp = requests.get(
    f"http://localhost:3000/sandboxes/{sandbox_id}",
    headers={"X-API-Key": "e2b_53ae1fed82754c17ad8077fbc8bcdd90"}
)
vm_ip = resp.json()['clientID']  # 例如: 10.11.13.172

# 连接到VM的envd (端口49983)
channel = grpc.insecure_channel(f'{vm_ip}:49983')
stub = ProcessServiceStub(channel)

# 执行命令
request = StartRequest(
    process=ProcessConfig(
        cmd='/bin/sh',
        args=['-c', 'echo "Hello from envd" && uname -a'],
        envs={'PATH': '/usr/bin:/bin'},
    )
)

response = stub.Start(request)
print(f"进程ID: {response.process_id}")
print(f"输出: {response.stdout}")
print(f"错误: {response.stderr}")
print(f"退出码: {response.exit_code}")

# 关闭连接
channel.close()
```

## 📚 完整示例程序

### 示例1: 数据处理任务

```python
from e2b import Sandbox

def run_data_processing():
    """在VM中运行数据处理任务"""

    with Sandbox(template="base") as sandbox:
        # 1. 安装所需包
        print("安装依赖...")
        sandbox.process.start("pip install pandas matplotlib")

        # 2. 上传数据文件
        print("上传数据...")
        sandbox.upload_file("./data.csv", "/tmp/data.csv")

        # 3. 创建处理脚本
        script = """
import pandas as pd
import matplotlib.pyplot as plt

# 读取数据
df = pd.read_csv('/tmp/data.csv')

# 处理
result = df.describe()
print(result)

# 生成图表
df.plot()
plt.savefig('/tmp/plot.png')
print("图表已保存")
"""

        sandbox.filesystem.write("/tmp/process.py", script)

        # 4. 运行处理
        print("运行处理...")
        result = sandbox.process.start("python3 /tmp/process.py")
        print(result.stdout)

        # 5. 下载结果
        print("下载结果...")
        sandbox.download_file("/tmp/plot.png", "./result_plot.png")

        print("✅ 处理完成!")

run_data_processing()
```

### 示例2: 并行测试

```python
from e2b import Sandbox
import concurrent.futures

def run_test(test_id):
    """在独立VM中运行测试"""
    with Sandbox(template="base") as sandbox:
        # 运行测试
        result = sandbox.run_code(f"""
import time
print(f"测试 {test_id} 开始")
time.sleep(2)
print(f"测试 {test_id} 完成")
        """)
        return f"Test {test_id}: {result.text}"

# 并行运行5个测试
with concurrent.futures.ThreadPoolExecutor(max_workers=5) as executor:
    futures = [executor.submit(run_test, i) for i in range(5)]
    results = [f.result() for f in concurrent.futures.as_completed(futures)]

for result in results:
    print(result)
```

### 示例3: Web服务器

```python
from e2b import Sandbox

with Sandbox(template="base") as sandbox:
    # 启动简单HTTP服务器
    print("启动Web服务器...")

    # 创建HTML文件
    sandbox.filesystem.write("/tmp/index.html", """
    <html>
    <body>
        <h1>Hello from E2B VM!</h1>
        <p>当前时间: <span id="time"></span></p>
        <script>
            setInterval(() => {
                document.getElementById('time').textContent = new Date().toLocaleString();
            }, 1000);
        </script>
    </body>
    </html>
    """)

    # 启动服务器（后台）
    process = sandbox.process.start(
        "python3 -m http.server 8000 -d /tmp",
        background=True
    )

    print(f"✅ Web服务器已启动")
    print(f"   访问: http://{sandbox.hostname}:8000/index.html")
    print(f"   按Enter键停止...")

    input()

    # 停止服务器
    process.kill()
    print("服务器已停止")
```

## 🔧 高级用法

### 环境变量

```python
# 设置环境变量
sandbox.process.start("export MY_VAR=hello")

# 在命令中使用
result = sandbox.process.start("echo $MY_VAR")
```

### 工作目录

```python
# 改变工作目录
sandbox.process.start("cd /tmp && pwd")

# 或在SDK中设置
sandbox = Sandbox(template="base", cwd="/tmp")
```

### 超时控制

```python
# 设置VM超时（秒）
sandbox = Sandbox(template="base", timeout=600)  # 10分钟

# 设置命令超时
result = sandbox.process.start("long_running_task", timeout=30)
```

### 资源限制

```python
# 创建VM时指定资源
sandbox = Sandbox(
    template="base",
    cpu=2,        # 2核CPU
    memory=1024,  # 1GB内存
)
```

## 📝 最佳实践

### 1. 使用上下文管理器

```python
# ✅ 推荐
with Sandbox(template="base") as sandbox:
    result = sandbox.run_code("print('hello')")

# ❌ 不推荐（需要手动关闭）
sandbox = Sandbox(template="base")
result = sandbox.run_code("print('hello')")
sandbox.close()  # 容易忘记
```

### 2. 错误处理

```python
from e2b import SandboxException

try:
    with Sandbox(template="base") as sandbox:
        result = sandbox.run_code("1/0")  # 会引发异常
except SandboxException as e:
    print(f"沙箱错误: {e}")
except Exception as e:
    print(f"其他错误: {e}")
```

### 3. 日志记录

```python
import logging

logging.basicConfig(level=logging.INFO)

with Sandbox(template="base") as sandbox:
    logging.info(f"创建VM: {sandbox.sandbox_id}")
    result = sandbox.run_code("print('test')")
    logging.info(f"执行结果: {result.text}")
```

### 4. 清理资源

```python
# 确保资源被清理
sandboxes = []
try:
    for i in range(5):
        sb = Sandbox(template="base")
        sandboxes.append(sb)
        # 使用sb...
finally:
    for sb in sandboxes:
        sb.close()
```

## 🐛 故障排查

### 问题1: 无法连接到API

```python
# 检查API状态
import requests
try:
    resp = requests.get("http://localhost:3000/health", timeout=5)
    print(f"API状态: {resp.status_code}")
except Exception as e:
    print(f"API不可用: {e}")
    print("请确保API服务正在运行:")
    print("  nomad job status api")
```

### 问题2: VM创建失败

```bash
# 检查orchestrator日志
ORCH_ALLOC=$(nomad job allocs orchestrator | grep running | awk '{print $1}')
nomad alloc logs $ORCH_ALLOC 2>&1 | tail -50

# 检查模板是否存在
docker exec local-dev-postgres-1 psql -U postgres -d postgres -c "SELECT id FROM envs;"
```

### 问题3: 命令执行超时

```python
# 增加超时时间
result = sandbox.process.start(
    "very_long_task",
    timeout=300  # 5分钟
)
```

### 问题4: envd连接被拒绝

```bash
# 检查VM的IP地址
e2b info <sandbox-id>

# 测试连接
curl http://<vm-ip>:49983/health

# 检查防火墙规则
sudo iptables -L -n | grep 49983
```

## 📚 相关资源

- **REST API客户端**: `/home/primihub/pcloud/infra/e2b-tools/examples/execute_in_vm.py`
- **CLI工具**: `/usr/local/bin/e2b`
- **VM使用指南**: `/home/primihub/pcloud/infra/e2b-tools/docs/vm-usage-guide.md`
- **官方SDK示例**: `/home/primihub/pcloud/infra/e2b/examples/`
- **Proto文件**: `/home/primihub/pcloud/infra/packages/shared/pkg/grpc/envd/`

## 🎯 快速参考

```bash
# 使用REST API脚本
cd /home/primihub/pcloud/infra/e2b-tools/examples
python3 execute_in_vm.py demo

# 使用CLI
e2b create                    # 创建VM
e2b ls                        # 列出VM
e2b info <vm-id>              # 查看详情
e2b rm <vm-id>                # 删除VM

# 使用Python SDK
pip install e2b
python3 -c "from e2b import Sandbox; s = Sandbox('base'); print(s.sandbox_id); s.close()"
```

---

**文档创建时间**: 2025-12-22
**状态**: 已测试
**示例脚本**: `/home/primihub/pcloud/infra/e2b-tools/examples/execute_in_vm.py`
