#!/usr/bin/env python3
"""
实际测试E2B VM代码执行
使用Python requests库直接与API交互
"""

import requests
import json
import time

def demo_code_execution():
    """演示在VM中执行代码的各种方式"""

    print("=" * 70)
    print("🚀 E2B VM代码执行实战演示")
    print("=" * 70)
    print()

    API_URL = "http://localhost:3000"
    API_KEY = "e2b_53ae1fed82754c17ad8077fbc8bcdd90"
    headers = {
        "X-API-Key": API_KEY,
        "Content-Type": "application/json"
    }

    # 1. 获取现有VM
    print("📦 步骤1: 获取运行中的VM")
    print("-" * 70)

    resp = requests.get(f"{API_URL}/sandboxes", headers=headers)
    vms = resp.json()

    if not vms:
        print("❌ 没有运行中的VM")
        print("   请先创建一个VM: e2b create")
        return

    vm = vms[0]
    vm_id = vm['sandboxID']

    print(f"✅ VM ID: {vm_id}")
    print(f"   状态: {vm['state']}")
    print(f"   CPU: {vm.get('cpuCount')}核 | 内存: {vm.get('memoryMB')}MB")
    print(f"   envd版本: {vm.get('envdVersion')}")
    print()

    # 2. 展示VM可以做什么
    print("💡 步骤2: VM功能展示")
    print("-" * 70)

    capabilities = [
        ("✅ 运行Python代码", "执行任意Python代码片段"),
        ("✅ 执行Shell命令", "运行系统命令如ls、cat、grep等"),
        ("✅ 文件操作", "创建、读取、写入、删除文件"),
        ("✅ 安装软件包", "pip install、apt install等"),
        ("✅ 网络访问", "curl、wget、HTTP请求"),
        ("✅ 数据处理", "pandas、numpy、matplotlib等"),
        ("✅ Web服务", "启动HTTP服务器、Flask应用等"),
        ("✅ 后台任务", "长时间运行的进程"),
    ]

    for capability, description in capabilities:
        print(f"   {capability:30} - {description}")

    print()

    # 3. 代码执行示例（概念演示）
    print("📝 步骤3: 代码执行示例")
    print("-" * 70)

    examples = [
        {
            "name": "Python基础计算",
            "code": """
# Python计算示例
numbers = [1, 2, 3, 4, 5]
total = sum(numbers)
average = total / len(numbers)
print(f"数字: {numbers}")
print(f"总和: {total}")
print(f"平均值: {average}")
            """
        },
        {
            "name": "系统信息",
            "code": """
import os, platform
print(f"操作系统: {platform.system()} {platform.release()}")
print(f"Python版本: {platform.python_version()}")
print(f"当前目录: {os.getcwd()}")
print(f"用户: {os.getenv('USER', 'unknown')}")
            """
        },
        {
            "name": "文件操作",
            "code": """
# 写入文件
with open('/tmp/test.txt', 'w') as f:
    f.write('Hello from E2B VM!')

# 读取文件
with open('/tmp/test.txt', 'r') as f:
    content = f.read()
    print(f"文件内容: {content}")

# 列出目录
import os
files = os.listdir('/tmp')
print(f"临时目录文件数: {len(files)}")
            """
        },
        {
            "name": "网络请求",
            "code": """
import urllib.request
import json

# 获取公共API数据
url = 'https://api.github.com/zen'
with urllib.request.urlopen(url) as response:
    data = response.read().decode()
    print(f"GitHub禅语: {data}")
            """
        },
    ]

    for i, example in enumerate(examples, 1):
        print(f"\n   示例 {i}: {example['name']}")
        print(f"   " + "─" * 65)
        for line in example['code'].strip().split('\n')[:8]:
            print(f"   {line}")
        if len(example['code'].strip().split('\n')) > 8:
            print(f"   ... (更多代码)")
        print()

    # 4. 如何实际执行
    print("🔧 步骤4: 实际执行方法")
    print("-" * 70)
    print()

    print("   方法A: 使用E2B Python SDK")
    print("   " + "=" * 65)
    print("""
   # 安装
   pip install e2b

   # 设置环境变量
   export E2B_API_KEY="e2b_53ae1fed82754c17ad8077fbc8bcdd90"
   export E2B_API_URL="http://localhost:3000"

   # 使用示例
   from e2b import Sandbox

   with Sandbox(template="base") as sandbox:
       # 执行Python代码
       result = sandbox.run_code('''
       print("Hello from E2B!")
       import sys
       print(f"Python: {sys.version}")
       ''')
       print(result.text)

       # 执行Shell命令
       result = sandbox.process.start("ls -la /tmp")
       print(result.stdout)

       # 文件操作
       sandbox.filesystem.write("/tmp/hello.txt", "Hello World")
       content = sandbox.filesystem.read("/tmp/hello.txt")
       print(content)
   """)

    print()
    print("   方法B: 使用gRPC直接连接envd")
    print("   " + "=" * 65)
    print("""
   # 需要proto文件和grpcio库
   pip install grpcio grpcio-tools

   # 生成Python代码
   cd /home/primihub/pcloud/infra/packages/shared/pkg/grpc/envd
   python3 -m grpc_tools.protoc -I. \\
       --python_out=. --grpc_python_out=. \\
       process.proto filesystem.proto

   # 使用示例
   import grpc
   from process_pb2 import StartRequest, ProcessConfig
   from process_pb2_grpc import ProcessServiceStub

   # 连接到VM的envd (需要正确的IP地址和网络配置)
   channel = grpc.insecure_channel('VM_IP:49983')
   stub = ProcessServiceStub(channel)

   request = StartRequest(
       process=ProcessConfig(
           cmd='/bin/sh',
           args=['-c', 'echo "Hello" && python3 --version'],
       )
   )

   response = stub.Start(request)
   print(response.stdout)
   """)

    print()
    print("   方法C: 使用CLI工具")
    print("   " + "=" * 65)
    print(f"""
   # 查看VM
   e2b ls

   # 查看日志（显示VM内的活动）
   e2b logs {vm_id}

   # 查看详细信息
   e2b info {vm_id}

   # 延长VM生命周期
   e2b extend 3600 {vm_id}
   """)

    print()

    # 5. 当前状态和限制
    print("⚠️  步骤5: 当前状态")
    print("-" * 70)

    print("""
   ✅ 已就绪:
      - E2B API服务运行正常 (http://localhost:3000)
      - VM已创建并运行 (ID: {})
      - envd守护进程在VM内运行 (v{})
      - REST API可以管理VM生命周期

   ⚠️  已知限制:
      - VM网络路由问题导致无法直接连接到envd (见CLAUDE.md)
      - 新VM创建存在kernel loading issue
      - 需要修复网络配置才能完全使用代码执行功能

   🔧 推荐方案:
      1. 安装E2B Python SDK (pip install e2b)
      2. SDK会自动处理与VM的通信
      3. 参考完整文档: /home/primihub/pcloud/infra/e2b-tools/docs/execute-programs-in-vm.md
   """.format(vm_id, vm.get('envdVersion', 'N/A')))

    print()
    print("=" * 70)
    print("📚 相关资源:")
    print("   - 完整执行指南: e2b-tools/docs/execute-programs-in-vm.md")
    print("   - 快速参考: e2b-tools/docs/QUICK_REFERENCE.md")
    print("   - VM使用指南: e2b-tools/docs/vm-usage-guide.md")
    print("   - 官方示例: e2b/examples/")
    print("=" * 70)

if __name__ == "__main__":
    demo_code_execution()
