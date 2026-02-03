#!/usr/bin/env python3
"""
E2B VM程序执行示例
演示如何使用Python通过REST API在VM中执行程序
"""

import requests
import json
import time
import sys

class E2BClient:
    """E2B API客户端"""

    def __init__(self, api_url="http://localhost:3000", api_key="e2b_53ae1fed82754c17ad8077fbc8bcdd90"):
        self.api_url = api_url.rstrip('/')
        self.api_key = api_key
        self.headers = {
            "X-API-Key": self.api_key,
            "Content-Type": "application/json"
        }

    def check_health(self):
        """检查API健康状态"""
        try:
            resp = requests.get(f"{self.api_url}/health", timeout=5)
            return resp.status_code == 200
        except Exception as e:
            print(f"❌ API健康检查失败: {e}")
            return False

    def create_sandbox(self, template_id="base", timeout=300):
        """创建VM沙箱"""
        print(f"📦 创建VM (模板: {template_id}, 超时: {timeout}秒)...")

        payload = {
            "templateID": template_id,
            "timeout": timeout
        }

        try:
            resp = requests.post(
                f"{self.api_url}/sandboxes",
                headers=self.headers,
                json=payload,
                timeout=30
            )

            if resp.status_code in [200, 201]:
                data = resp.json()
                sandbox_id = data.get("sandboxID")
                print(f"✅ VM创建成功! ID: {sandbox_id}")
                return sandbox_id
            else:
                print(f"❌ 创建失败: {resp.status_code} - {resp.text}")
                return None

        except Exception as e:
            print(f"❌ 创建VM时出错: {e}")
            return None

    def list_sandboxes(self):
        """列出所有VM"""
        try:
            resp = requests.get(
                f"{self.api_url}/sandboxes",
                headers=self.headers,
                timeout=10
            )

            if resp.status_code == 200:
                return resp.json()
            else:
                print(f"❌ 获取VM列表失败: {resp.status_code}")
                return []

        except Exception as e:
            print(f"❌ 获取VM列表时出错: {e}")
            return []

    def get_sandbox_info(self, sandbox_id):
        """获取VM详细信息"""
        try:
            resp = requests.get(
                f"{self.api_url}/sandboxes/{sandbox_id}",
                headers=self.headers,
                timeout=10
            )

            if resp.status_code == 200:
                return resp.json()
            else:
                print(f"❌ 获取VM信息失败: {resp.status_code}")
                return None

        except Exception as e:
            print(f"❌ 获取VM信息时出错: {e}")
            return None

    def execute_command(self, sandbox_id, command):
        """
        在VM中执行命令
        注意：这需要连接到VM内的envd服务
        """
        print(f"🚀 在VM中执行: {command}")

        # 获取VM信息以找到envd端口
        info = self.get_sandbox_info(sandbox_id)
        if not info:
            print("❌ 无法获取VM信息")
            return None

        # E2B的envd通常运行在VM内部的49983端口
        # 需要通过orchestrator的gRPC接口或直接连接到VM
        print("⚠️ 注意: 直接命令执行需要连接到envd服务")
        print(f"   VM信息: {json.dumps(info, indent=2)}")

        return info

    def delete_sandbox(self, sandbox_id):
        """删除VM"""
        print(f"🗑️ 删除VM: {sandbox_id}")

        try:
            resp = requests.delete(
                f"{self.api_url}/sandboxes/{sandbox_id}",
                headers=self.headers,
                timeout=10
            )

            if resp.status_code in [200, 204]:
                print("✅ VM已删除")
                return True
            else:
                print(f"❌ 删除失败: {resp.status_code} - {resp.text}")
                return False

        except Exception as e:
            print(f"❌ 删除VM时出错: {e}")
            return False


def demo_basic_usage():
    """演示基本使用"""
    print("=" * 60)
    print("E2B VM程序执行演示")
    print("=" * 60)
    print()

    # 创建客户端
    client = E2BClient()

    # 1. 健康检查
    print("1️⃣ 检查API服务...")
    if not client.check_health():
        print("❌ E2B API服务不可用")
        print("   请确保服务正在运行:")
        print("   - API: http://localhost:3000/health")
        print("   - Orchestrator: http://localhost:5008/health")
        return 1
    print("✅ API服务正常\n")

    # 2. 列出现有VM
    print("2️⃣ 列出现有VM...")
    vms = client.list_sandboxes()
    if vms:
        print(f"   找到 {len(vms)} 个VM:")
        for vm in vms[:3]:  # 只显示前3个
            print(f"   - {vm.get('sandboxID', 'N/A')} ({vm.get('state', 'N/A')})")
    else:
        print("   当前没有运行中的VM")
    print()

    # 3. 创建新VM
    print("3️⃣ 创建新VM...")
    sandbox_id = client.create_sandbox(template_id="base", timeout=300)

    if not sandbox_id:
        print("❌ 无法创建VM")
        return 1
    print()

    # 4. 获取VM信息
    print("4️⃣ 获取VM详细信息...")
    info = client.get_sandbox_info(sandbox_id)
    if info:
        print(f"   VM ID: {info.get('sandboxID')}")
        print(f"   状态: {info.get('state')}")
        print(f"   IP地址: {info.get('clientID')}")
        print(f"   CPU: {info.get('cpuCount')}核")
        print(f"   内存: {info.get('memoryMB')}MB")
        print(f"   启动时间: {info.get('startedAt')}")
    print()

    # 5. 执行命令（概念演示）
    print("5️⃣ 在VM中执行程序...")
    print("   ⚠️ 直接在VM中执行程序需要连接到envd服务")
    print("   envd运行在VM内部的49983端口")
    print()
    print("   可用的执行方式:")
    print("   A. 使用gRPC连接到envd (推荐)")
    print("   B. 使用官方e2b Python SDK")
    print("   C. 通过orchestrator的gRPC接口")
    print()

    # 6. 保持VM运行
    print("6️⃣ VM已创建并运行")
    print(f"   VM ID: {sandbox_id}")
    print(f"   使用CLI查看: e2b info {sandbox_id}")
    print(f"   使用CLI查看日志: e2b logs {sandbox_id}")
    print()

    # 询问是否删除
    try:
        choice = input("是否删除此VM? (y/N): ").strip().lower()
        if choice == 'y':
            client.delete_sandbox(sandbox_id)
        else:
            print(f"✅ VM保持运行: {sandbox_id}")
            print(f"   5分钟后自动过期，或使用以下命令删除:")
            print(f"   e2b rm {sandbox_id}")
    except KeyboardInterrupt:
        print(f"\n\n✅ VM保持运行: {sandbox_id}")

    print()
    print("=" * 60)
    return 0


def demo_with_grpc():
    """演示使用gRPC直接执行命令"""
    print("=" * 60)
    print("使用gRPC在VM中执行程序")
    print("=" * 60)
    print()

    print("这需要安装grpcio和protobuf:")
    print("  pip install grpcio grpcio-tools protobuf")
    print()

    print("示例代码 (需要proto文件):")
    print("""
import grpc
from process_pb2 import StartRequest, ProcessConfig
from process_pb2_grpc import ProcessServiceStub

# 连接到VM的envd服务
channel = grpc.insecure_channel('10.11.13.172:49983')
stub = ProcessServiceStub(channel)

# 执行命令
request = StartRequest(
    process=ProcessConfig(
        cmd='/bin/sh',
        args=['-c', 'echo "Hello from VM" && uname -a'],
    )
)

response = stub.Start(request)
print(f"输出: {response.stdout}")
    """)
    print()


def demo_with_sdk():
    """演示使用官方e2b SDK"""
    print("=" * 60)
    print("使用官方E2B Python SDK")
    print("=" * 60)
    print()

    print("1. 安装SDK:")
    print("   pip install e2b")
    print()

    print("2. 使用示例:")
    print("""
from e2b import Sandbox

# 创建沙箱
sandbox = Sandbox(template="base")

# 执行Python代码
result = sandbox.run_code('''
print("Hello from E2B VM!")
import os
print(f"当前目录: {os.getcwd()}")
print(f"系统: {os.uname()}")
''')

print(result.text)

# 执行Shell命令
result = sandbox.process.start("ls -la /")
print(result.stdout)

# 上传文件
sandbox.filesystem.write("/tmp/test.txt", "Hello World")

# 下载文件
content = sandbox.filesystem.read("/tmp/test.txt")
print(content)

# 关闭
sandbox.close()
    """)
    print()


def main():
    """主函数"""
    if len(sys.argv) > 1:
        command = sys.argv[1]

        if command == "demo":
            return demo_basic_usage()
        elif command == "grpc":
            demo_with_grpc()
            return 0
        elif command == "sdk":
            demo_with_sdk()
            return 0
        elif command == "help":
            print("使用方法:")
            print("  python execute_in_vm.py demo   # 运行基本演示")
            print("  python execute_in_vm.py grpc   # 查看gRPC示例")
            print("  python execute_in_vm.py sdk    # 查看SDK示例")
            return 0
        else:
            print(f"未知命令: {command}")
            return 1
    else:
        # 默认运行演示
        return demo_basic_usage()


if __name__ == "__main__":
    sys.exit(main())
