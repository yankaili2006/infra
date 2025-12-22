#!/usr/bin/env python3
"""
使用E2B Python SDK在VM中执行代码
"""

import os
import sys

# 设置环境变量
os.environ["E2B_API_KEY"] = "e2b_53ae1fed82754c17ad8077fbc8bcdd90"
os.environ["E2B_API_URL"] = "http://localhost:3000"

try:
    from e2b import Sandbox
    print("✅ E2B SDK加载成功")
except ImportError as e:
    print(f"❌ 无法导入E2B SDK: {e}")
    print("请先安装: python3 -m pip install --user --break-system-packages e2b")
    sys.exit(1)

def main():
    print("=" * 70)
    print("🚀 使用E2B SDK在VM中执行Python代码")
    print("=" * 70)
    print()

    try:
        # 方法1: 连接到现有VM
        print("方法1: 使用现有VM")
        print("-" * 70)

        # 获取现有VM ID
        import requests
        resp = requests.get(
            "http://localhost:3000/sandboxes",
            headers={"X-API-Key": "e2b_53ae1fed82754c17ad8077fbc8bcdd90"}
        )

        if resp.status_code == 200 and resp.json():
            vm_id = resp.json()[0]['sandboxID']
            print(f"找到现有VM: {vm_id}")

            # 尝试使用SDK连接
            # 注意: E2B SDK可能不支持直接连接到现有VM
            # 需要创建新的VM
            print("⚠️  E2B SDK需要创建新VM")
            print()

        # 方法2: 创建新VM并执行代码
        print("方法2: 创建新VM并执行代码")
        print("-" * 70)
        print("⚠️  注意: 当前存在VM创建问题，这可能会失败")
        print()

        try:
            print("创建新VM...")
            sandbox = Sandbox(template="base")

            print(f"✅ VM已创建: {sandbox.sandbox_id}")
            print()

            # 测试1: Hello World
            print("🧪 测试1: Hello World")
            print("-" * 70)
            result = sandbox.run_code("print('Hello from E2B VM!')")
            print(f"输出: {result.text}")
            print()

            # 测试2: 基础计算
            print("🧪 测试2: 基础计算")
            print("-" * 70)
            code = """
numbers = [1, 2, 3, 4, 5]
print(f"数字: {numbers}")
print(f"总和: {sum(numbers)}")
print(f"平均值: {sum(numbers)/len(numbers)}")
"""
            result = sandbox.run_code(code)
            print(f"输出:\n{result.text}")
            print()

            # 测试3: 系统信息
            print("🧪 测试3: 系统信息")
            print("-" * 70)
            code = """
import sys, platform, os
print(f"Python版本: {sys.version}")
print(f"操作系统: {platform.system()} {platform.release()}")
print(f"当前目录: {os.getcwd()}")
"""
            result = sandbox.run_code(code)
            print(f"输出:\n{result.text}")
            print()

            # 测试4: 文件操作
            print("🧪 测试4: 文件操作")
            print("-" * 70)
            sandbox.filesystem.write("/tmp/test.txt", "Hello from E2B!")
            content = sandbox.filesystem.read("/tmp/test.txt")
            print(f"写入并读取文件: {content}")
            print()

            # 测试5: Shell命令
            print("🧪 测试5: Shell命令")
            print("-" * 70)
            result = sandbox.process.start("ls -la /tmp | head -10")
            print(f"输出:\n{result.stdout}")
            print()

            # 关闭VM
            print("关闭VM...")
            sandbox.close()
            print("✅ VM已关闭")

        except Exception as e:
            print(f"❌ SDK执行失败: {e}")
            print()
            print("这可能是因为:")
            print("1. VM创建问题 (kernel loading issue)")
            print("2. 网络路由问题")
            print("3. SDK与本地部署不兼容")
            print()
            return 1

    except KeyboardInterrupt:
        print("\n\n用户中断")
        return 1

    print()
    print("=" * 70)
    print("🎉 测试完成!")
    print("=" * 70)

    return 0

if __name__ == "__main__":
    sys.exit(main())
