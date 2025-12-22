#!/usr/bin/env python3
"""
测试在运行中的E2B VM中执行代码
"""

import requests
import json
import sys

def test_vm_execution():
    """测试VM代码执行"""

    print("=" * 60)
    print("🧪 E2B VM代码执行测试")
    print("=" * 60)
    print()

    API_URL = "http://localhost:3000"
    API_KEY = "e2b_53ae1fed82754c17ad8077fbc8bcdd90"
    headers = {
        "X-API-Key": API_KEY,
        "Content-Type": "application/json"
    }

    # 1. 获取运行中的VM
    print("1️⃣ 获取运行中的VM...")
    try:
        resp = requests.get(f"{API_URL}/sandboxes", headers=headers, timeout=10)
        if resp.status_code != 200:
            print(f"❌ API返回错误: {resp.status_code}")
            return 1

        vms = resp.json()
        if not vms:
            print("❌ 没有运行中的VM")
            return 1

        vm = vms[0]
        vm_id = vm['sandboxID']
        vm_ip = vm.get('clientID', 'N/A')

        print(f"✅ 找到VM: {vm_id}")
        print(f"   状态: {vm['state']}")
        print(f"   Client ID: {vm_ip}")
        print(f"   CPU: {vm.get('cpuCount', 'N/A')}核")
        print(f"   内存: {vm.get('memoryMB', 'N/A')}MB")
        print()

    except Exception as e:
        print(f"❌ 获取VM失败: {e}")
        return 1

    # 2. 测试通过API执行命令的可能性
    print("2️⃣ 测试E2B API端点...")

    # E2B通常提供以下端点来执行命令
    test_endpoints = [
        f"/sandboxes/{vm_id}/execute",
        f"/sandboxes/{vm_id}/commands",
        f"/sandboxes/{vm_id}/process",
        f"/sandboxes/{vm_id}/filesystem",
    ]

    for endpoint in test_endpoints:
        try:
            resp = requests.get(f"{API_URL}{endpoint}", headers=headers, timeout=5)
            if resp.status_code != 404:
                print(f"   ✅ 找到端点: {endpoint} (状态: {resp.status_code})")
                print(f"      响应: {resp.text[:100]}")
        except Exception as e:
            pass

    print()

    # 3. 尝试通过gRPC连接到envd
    print("3️⃣ 测试envd连接...")
    print(f"   envd版本: {vm.get('envdVersion', 'N/A')}")
    print(f"   envd通常监听端口: 49983")
    print()

    # 尝试推断VM的IP地址
    # E2B VM通常使用169.254.x.x或10.11.x.x范围的IP
    possible_ips = [
        f"169.254.0.{21 + len(vms)}",  # 基于VM数量推测
        "10.11.13.172",  # 常见的orchestrator分配的IP
        "169.254.0.21",  # 默认第一个VM的IP
    ]

    print("   尝试连接到可能的VM IP地址:")
    for test_ip in possible_ips:
        try:
            test_url = f"http://{test_ip}:49983/health"
            resp = requests.get(test_url, timeout=2)
            print(f"   ✅ 找到envd! IP: {test_ip}")
            print(f"      健康检查响应: {resp.status_code}")

            # 如果找到了，尝试执行命令
            print()
            print("4️⃣ 尝试执行测试命令...")
            print(f"   连接到: {test_ip}:49983")
            print(f"   ⚠️  需要gRPC客户端才能执行命令")
            print(f"   参考文档: /home/primihub/pcloud/infra/e2b-tools/docs/execute-programs-in-vm.md")

            return 0
        except Exception as e:
            print(f"   ❌ {test_ip}:49983 - {type(e).__name__}")

    print()

    # 4. 展示如何使用官方SDK
    print("4️⃣ 推荐的执行方式:")
    print()

    print("   方式A: 使用E2B Python SDK (最简单)")
    print("   " + "-" * 50)
    print("""
   pip install e2b

   from e2b import Sandbox

   # 连接到现有VM或创建新VM
   sandbox = Sandbox(template="base")

   # 执行代码
   result = sandbox.run_code('print("Hello from VM!")')
   print(result.text)

   # 执行Shell命令
   result = sandbox.process.start("ls -la /")
   print(result.stdout)

   sandbox.close()
   """)

    print()
    print("   方式B: 使用gRPC直接连接envd")
    print("   " + "-" * 50)
    print(f"""
   pip install grpcio grpcio-tools

   import grpc
   from process_pb2 import StartRequest, ProcessConfig
   from process_pb2_grpc import ProcessServiceStub

   # 连接到VM的envd (需要正确的IP地址)
   channel = grpc.insecure_channel('VM_IP:49983')
   stub = ProcessServiceStub(channel)

   # 执行命令
   request = StartRequest(
       process=ProcessConfig(
           cmd='/bin/sh',
           args=['-c', 'echo "Hello from VM" && uname -a'],
       )
   )

   response = stub.Start(request)
   print(response.stdout)
   """)

    print()
    print("   方式C: 通过Orchestrator gRPC API")
    print("   " + "-" * 50)
    print("""
   # 连接到orchestrator (localhost:5008)
   # 使用sandbox.SandboxService/Execute RPC方法
   # 详见: /home/primihub/pcloud/infra/packages/orchestrator
   """)

    print()
    print("=" * 60)
    print("📚 完整文档:")
    print("   /home/primihub/pcloud/infra/e2b-tools/docs/execute-programs-in-vm.md")
    print("=" * 60)

    return 0

if __name__ == "__main__":
    sys.exit(test_vm_execution())
