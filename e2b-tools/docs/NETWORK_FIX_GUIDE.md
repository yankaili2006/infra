# E2B VM网络路由问题解决方案

## 📋 问题诊断

**当前状态**: 2025-12-22

### 诊断结果

1. ✅ **VM运行正常**
   - VM ID: itzzutamgzsz4dpf7tjbq
   - 状态: running
   - 资源: 2核CPU, 512MB内存
   - envd: v0.0.1 运行中

2. ❌ **网络路由问题**
   - 无法直接连接到VM的envd服务 (端口49983)
   - clientID为null (网络信息缺失)
   - 测试的IP地址均超时

3. ❌ **环境限制**
   - pip未安装/受限 (PEP 668保护)
   - sudo权限受限
   - grpc模块未安装

## 🔧 解决方案

### 方案1: 使用虚拟环境安装SDK (推荐)

```bash
# 1. 创建Python虚拟环境
python3 -m venv ~/e2b-env

# 2. 激活虚拟环境
source ~/e2b-env/bin/activate

# 3. 安装E2B SDK
pip install e2b grpcio grpcio-tools

# 4. 设置环境变量
export E2B_API_KEY="e2b_53ae1fed82754c17ad8077fbc8bcdd90"
export E2B_API_URL="http://localhost:3000"

# 5. 测试
python3 << 'EOF'
from e2b import Sandbox

with Sandbox(template="base") as sandbox:
    result = sandbox.run_code("print('Hello from VM!')")
    print(result.text)
EOF
```

### 方案2: 手动安装pip

```bash
# 下载get-pip.py
curl https://bootstrap.pypa.io/get-pip.py -o /tmp/get-pip.py

# 在虚拟环境中安装
python3 -m venv ~/e2b-env
source ~/e2b-env/bin/activate
python3 /tmp/get-pip.py
```

### 方案3: 使用Docker容器

```bash
# 创建包含所有依赖的Docker容器
docker run -it --network=host \
  -v /home/primihub/pcloud/infra:/workspace \
  python:3.12 bash

# 在容器内
pip install e2b grpcio
export E2B_API_KEY="e2b_53ae1fed82754c17ad8077fbc8bcdd90"
export E2B_API_URL="http://localhost:3000"

# 执行代码
python3 << 'EOF'
from e2b import Sandbox
sandbox = Sandbox(template="base")
result = sandbox.run_code("print('Hello!')")
print(result.text)
sandbox.close()
EOF
```

### 方案4: 修复网络路由 (高级)

```bash
# 1. 查找VM的实际IP地址
# 通过orchestrator日志
ORCH_ALLOC=$(nomad job allocs orchestrator | grep running | awk '{print $1}')
nomad alloc logs "$ORCH_ALLOC" 2>&1 | grep -i "IP\|address\|169.254"

# 2. 检查路由表
ip route show

# 3. 添加路由 (需要sudo)
sudo ip route add 169.254.0.0/16 dev <interface>

# 4. 测试连接
curl http://<VM_IP>:49983/health
```

### 方案5: 使用gRPC通过orchestrator (需要proto编译)

```bash
# 1. 编译proto文件
cd /tmp
mkdir grpc_client && cd grpc_client

# 复制proto文件
cp /home/primihub/pcloud/infra/packages/envd/spec/process/process.proto .

# 2. 生成Python代码 (需要grpcio-tools)
python3 -m grpc_tools.protoc \
  -I. \
  --python_out=. \
  --grpc_python_out=. \
  process.proto

# 3. 使用生成的代码
python3 << 'EOF'
import grpc
import process_pb2
import process_pb2_grpc

channel = grpc.insecure_channel('VM_IP:49983')
stub = process_pb2_grpc.ProcessStub(channel)

request = process_pb2.StartRequest(
    process=process_pb2.ProcessConfig(
        cmd='/usr/bin/python3',
        args=['-c', 'print("Hello from VM!")']
    )
)

for response in stub.Start(request):
    if response.event.HasField('data'):
        print(response.event.data.stdout.decode())
EOF
```

## 🚀 立即可用的测试脚本

### 脚本1: 使用venv安装并测试

```bash
#!/bin/bash
# 文件: /tmp/setup_e2b_env.sh

set -e

echo "🔧 设置E2B Python环境..."

# 创建虚拟环境
if [ ! -d ~/e2b-env ]; then
    echo "创建虚拟环境..."
    python3 -m venv ~/e2b-env
fi

# 激活虚拟环境
source ~/e2b-env/bin/activate

# 安装依赖
echo "安装E2B SDK..."
pip install -q e2b requests

# 设置环境变量
export E2B_API_KEY="e2b_53ae1fed82754c17ad8077fbc8bcdd90"
export E2B_API_URL="http://localhost:3000"

echo "✅ 环境准备完成!"
echo ""
echo "激活环境: source ~/e2b-env/bin/activate"
echo "测试SDK: python3 /tmp/test_sdk.py"
```

### 脚本2: SDK测试代码

```python
#!/usr/bin/env python3
# 文件: /tmp/test_sdk.py

import os
os.environ["E2B_API_KEY"] = "e2b_53ae1fed82754c17ad8077fbc8bcdd90"
os.environ["E2B_API_URL"] = "http://localhost:3000"

from e2b import Sandbox

print("🚀 测试E2B SDK...")
print()

try:
    # 创建VM
    print("1️⃣ 创建VM...")
    sandbox = Sandbox(template="base")
    print(f"✅ VM已创建: {sandbox.sandbox_id}")
    print()

    # 执行Python代码
    print("2️⃣ 执行Python代码...")
    tests = [
        ("Hello World", "print('Hello from E2B VM!')"),
        ("基础计算", "print(f'2 + 2 = {2+2}')"),
        ("列表操作", "nums = [1,2,3,4,5]; print(f'Sum: {sum(nums)}')"),
    ]

    for name, code in tests:
        print(f"   测试: {name}")
        result = sandbox.run_code(code)
        print(f"   结果: {result.text.strip()}")
        print()

    # 文件操作
    print("3️⃣ 文件操作...")
    sandbox.filesystem.write("/tmp/test.txt", "Hello from E2B!")
    content = sandbox.filesystem.read("/tmp/test.txt")
    print(f"   写入并读取: {content}")
    print()

    # Shell命令
    print("4️⃣ Shell命令...")
    result = sandbox.process.start("uname -a")
    print(f"   系统信息: {result.stdout.strip()}")
    print()

    # 关闭VM
    sandbox.close()
    print("✅ 测试完成!")

except Exception as e:
    print(f"❌ 错误: {e}")
    print()
    print("可能的原因:")
    print("1. VM创建问题 (kernel loading issue - 见CLAUDE.md)")
    print("2. 网络路由问题")
    print("3. API连接问题")
```

## 📊 诊断命令

### 检查VM状态

```bash
# 1. 列出所有VM
curl -s http://localhost:3000/sandboxes \
  -H "X-API-Key: e2b_53ae1fed82754c17ad8077fbc8bcdd90" | jq .

# 2. 检查特定VM
VM_ID=itzzutamgzsz4dpf7tjbq
curl -s http://localhost:3000/sandboxes/$VM_ID \
  -H "X-API-Key: e2b_53ae1fed82754c17ad8077fbc8bcdd90" | jq .

# 3. 检查Firecracker进程
ps aux | grep firecracker | grep $VM_ID
```

### 检查网络

```bash
# 1. 网络接口
ip addr show | grep -A 2 "fc-"

# 2. 路由表
ip route show

# 3. iptables规则
sudo iptables -t nat -L -n -v | grep 49983

# 4. 网络命名空间
sudo ip netns list
```

### 检查服务

```bash
# 1. API服务
curl http://localhost:3000/health

# 2. Orchestrator服务
curl http://localhost:5008/health

# 3. Nomad作业
nomad job status
nomad alloc logs $(nomad job allocs orchestrator | grep running | awk '{print $1}')
```

## 🎯 推荐执行步骤

### 步骤1: 准备环境 (5分钟)

```bash
# 创建并激活虚拟环境
python3 -m venv ~/e2b-env
source ~/e2b-env/bin/activate

# 升级pip
curl https://bootstrap.pypa.io/get-pip.py | python3

# 安装SDK
pip install e2b
```

### 步骤2: 测试连接 (2分钟)

```bash
# 设置环境变量
export E2B_API_KEY="e2b_53ae1fed82754c17ad8077fbc8bcdd90"
export E2B_API_URL="http://localhost:3000"

# 测试API
curl http://localhost:3000/health

# 测试SDK导入
python3 -c "from e2b import Sandbox; print('SDK已就绪')"
```

### 步骤3: 执行代码 (1分钟)

```bash
# 运行测试脚本
python3 << 'EOF'
from e2b import Sandbox
with Sandbox(template="base") as s:
    print(s.run_code("print('Success!')").text)
EOF
```

## ⚠️ 已知问题和限制

### 问题1: VM创建失败 (CLAUDE.md已记录)

**症状**: `Failed to place sandbox`

**原因**: Kernel loading issue

**临时方案**: 使用已存在的VM

### 问题2: 网络路由不通

**症状**: 无法连接envd:49983

**原因**:
- VM网络配置缺失
- 路由表未正确设置
- iptables规则问题

**解决**: 使用E2B SDK (SDK内部处理路由)

### 问题3: pip安装受限

**症状**: PEP 668错误

**解决**: 使用venv或--break-system-packages

## 📚 相关文档

- **网络问题**: CLAUDE.md "VM Creation Troubleshooting Guide" 章节
- **代码执行指南**: /home/primihub/pcloud/infra/e2b-tools/docs/execute-programs-in-vm.md
- **快速参考**: /home/primihub/pcloud/infra/e2b-tools/docs/QUICK_REFERENCE.md
- **测试报告**: /home/primihub/pcloud/infra/e2b-tools/docs/VM_EXECUTION_TEST_REPORT.md

## 🎉 成功案例

一旦环境配置正确，以下代码应该能够工作：

```python
from e2b import Sandbox

# 数据分析示例
with Sandbox(template="base") as sandbox:
    # 安装包
    sandbox.process.start("pip install pandas numpy")

    # 执行数据分析
    code = """
import pandas as pd
import numpy as np

data = {'A': [1, 2, 3], 'B': [4, 5, 6]}
df = pd.DataFrame(data)
print(df.describe())
"""

    result = sandbox.run_code(code)
    print(result.text)
```

---

**创建时间**: 2025-12-22
**状态**: 解决方案已准备，等待环境配置
**优先级**: 高
**预计时间**: 10-15分钟完成配置
