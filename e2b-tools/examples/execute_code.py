#!/usr/bin/env python3
"""
通过gRPC在E2B VM中执行Python代码
直接连接到envd服务
"""

import sys
import os

# 添加生成的proto代码到路径
sys.path.insert(0, '/tmp/e2b_grpc')

import grpc
import process_pb2
import process_pb2_grpc
import time

def find_vm_ip():
    """尝试找到VM的IP地址"""
    import requests

    # 从API获取VM信息
    API_URL = "http://localhost:3000"
    API_KEY = "e2b_53ae1fed82754c17ad8077fbc8bcdd90"

    resp = requests.get(
        f"{API_URL}/sandboxes",
        headers={"X-API-Key": API_KEY}
    )

    if resp.status_code == 200:
        vms = resp.json()
        if vms:
            # 尝试从各种字段获取IP
            vm = vms[0]
            possible_ips = [
                vm.get('clientID'),
                vm.get('hostname'),
                vm.get('ipAddress'),
                vm.get('ip'),
            ]

            # 过滤掉None值
            ips = [ip for ip in possible_ips if ip]

            if not ips:
                # 尝试常见的IP地址
                print("⚠️  API未返回IP地址，尝试常见IP...")
                return [
                    "169.254.0.21",
                    "10.11.13.172",
                    "169.254.0.22",
                    "127.0.0.1"  # 本地测试
                ]

            return ips

    return []

def execute_code_via_envd(ip_address, code, use_python=True):
    """通过envd执行代码"""

    print(f"🔌 尝试连接到 {ip_address}:49983...")

    try:
        # 创建gRPC channel
        channel = grpc.insecure_channel(f'{ip_address}:49983')

        # 设置短超时测试连接
        grpc.channel_ready_future(channel).result(timeout=2)

        print(f"✅ 成功连接到envd!")

        # 创建stub
        stub = process_pb2_grpc.ProcessStub(channel)

        # 构造命令
        if use_python:
            cmd = '/usr/bin/python3'
            args = ['-c', code]
        else:
            cmd = '/bin/sh'
            args = ['-c', code]

        # 创建请求
        request = process_pb2.StartRequest(
            process=process_pb2.ProcessConfig(
                cmd=cmd,
                args=args,
                envs={'PATH': '/usr/local/bin:/usr/bin:/bin'}
            ),
            stdin=False
        )

        print(f"🚀 执行代码...")
        if use_python:
            print(f"   Python代码: {code[:100]}...")
        else:
            print(f"   Shell命令: {code[:100]}...")

        # 发送请求并获取响应流
        responses = stub.Start(request)

        stdout_data = b""
        stderr_data = b""
        exit_code = None
        pid = None

        for response in responses:
            event = response.event

            if event.HasField('start'):
                pid = event.start.pid
                print(f"   进程已启动 (PID: {pid})")

            elif event.HasField('data'):
                data = event.data
                if data.HasField('stdout'):
                    stdout_data += data.stdout
                elif data.HasField('stderr'):
                    stderr_data += data.stderr
                elif data.HasField('pty'):
                    stdout_data += data.pty

            elif event.HasField('end'):
                exit_code = event.end.exit_code
                status = event.end.status
                print(f"   进程结束 (状态: {status}, 退出码: {exit_code})")

                if event.end.error:
                    print(f"   错误: {event.end.error}")

        # 解码输出
        stdout_text = stdout_data.decode('utf-8', errors='replace')
        stderr_text = stderr_data.decode('utf-8', errors='replace')

        print()
        print("=" * 70)
        print("📤 执行结果:")
        print("=" * 70)

        if stdout_text:
            print("标准输出:")
            print(stdout_text)

        if stderr_text:
            print("标准错误:")
            print(stderr_text)

        print("=" * 70)
        print(f"退出码: {exit_code}")
        print("=" * 70)

        channel.close()
        return True, stdout_text, stderr_text, exit_code

    except grpc.FutureTimeoutError:
        print(f"❌ 连接超时: {ip_address}:49983")
        return False, None, None, None
    except Exception as e:
        print(f"❌ 错误: {e}")
        return False, None, None, None

def main():
    print("=" * 70)
    print("🚀 E2B VM Python代码执行器")
    print("=" * 70)
    print()

    # 查找VM IP
    print("1️⃣ 查找VM IP地址...")
    ips = find_vm_ip()

    if not ips:
        print("❌ 无法找到VM IP地址")
        return 1

    print(f"   找到 {len(ips)} 个可能的IP地址")
    print()

    # 测试代码
    python_tests = [
        {
            "name": "Hello World",
            "code": "print('Hello from E2B VM!')"
        },
        {
            "name": "基础计算",
            "code": """
numbers = [1, 2, 3, 4, 5]
print(f"数字: {numbers}")
print(f"总和: {sum(numbers)}")
print(f"平均值: {sum(numbers)/len(numbers)}")
"""
        },
        {
            "name": "系统信息",
            "code": """
import sys, platform, os
print(f"Python版本: {sys.version}")
print(f"操作系统: {platform.system()} {platform.release()}")
print(f"当前目录: {os.getcwd()}")
print(f"用户: {os.getenv('USER', 'unknown')}")
"""
        }
    ]

    # 尝试每个IP地址
    for ip in ips:
        print(f"2️⃣ 测试IP: {ip}")
        print("-" * 70)

        # 先测试简单命令
        success, stdout, stderr, exit_code = execute_code_via_envd(
            ip,
            "echo 'Connection test successful'",
            use_python=False
        )

        if not success:
            print(f"   跳过此IP，尝试下一个...")
            print()
            continue

        # 成功！执行Python测试
        print()
        print("✅ 找到可用的envd连接!")
        print()

        for i, test in enumerate(python_tests, 1):
            print(f"3️⃣ 测试 {i}/{len(python_tests)}: {test['name']}")
            print("-" * 70)

            success, stdout, stderr, exit_code = execute_code_via_envd(
                ip,
                test['code'],
                use_python=True
            )

            if success and exit_code == 0:
                print(f"✅ 测试通过!")
            else:
                print(f"⚠️  测试失败")

            print()
            time.sleep(1)

        print()
        print("=" * 70)
        print("🎉 所有测试完成!")
        print("=" * 70)
        return 0

    print()
    print("❌ 所有IP地址都无法连接")
    print()
    print("💡 可能的解决方案:")
    print("   1. 检查VM是否真的在运行")
    print("   2. 检查防火墙规则")
    print("   3. 检查网络路由配置")
    print("   4. 使用E2B Python SDK (会自动处理连接)")

    return 1

if __name__ == "__main__":
    sys.exit(main())
