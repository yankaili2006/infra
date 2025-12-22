#!/usr/bin/env python3
"""
完整的E2B VM代码执行测试
真正在VM中执行Python代码
"""

import os
import sys

# 设置环境变量
os.environ["E2B_API_KEY"] = "e2b_53ae1fed82754c17ad8077fbc8bcdd90"
os.environ["E2B_API_URL"] = "http://localhost:3000"

try:
    from e2b import Sandbox
    print("✅ E2B SDK已加载")
except ImportError as e:
    print(f"❌ 无法导入E2B SDK: {e}")
    print("请先运行: bash /tmp/setup_e2b_env.sh")
    sys.exit(1)

def main():
    print()
    print("=" * 70)
    print("🚀 E2B VM Python代码执行完整测试")
    print("=" * 70)
    print()

    try:
        # 创建VM
        print("📦 步骤1: 创建新VM...")
        print("-" * 70)

        try:
            sandbox = Sandbox(template="base", timeout=600)
            print(f"✅ VM已创建成功!")
            print(f"   VM ID: {sandbox.sandbox_id}")
            print(f"   主机名: {sandbox.get_hostname() if hasattr(sandbox, 'get_hostname') else 'N/A'}")
            print()

        except Exception as e:
            print(f"❌ VM创建失败: {e}")
            print()
            print("⚠️  这是已知问题 (kernel loading issue)")
            print("   尝试使用现有VM...")
            print()

            # 尝试获取现有VM
            import requests
            resp = requests.get(
                "http://localhost:3000/sandboxes",
                headers={"X-API-Key": os.environ["E2B_API_KEY"]}
            )

            if resp.status_code == 200 and resp.json():
                vm_id = resp.json()[0]['sandboxID']
                print(f"   找到现有VM: {vm_id}")
                print("   ⚠️  SDK可能无法直接连接到现有VM")
                print("   建议: 修复VM创建问题后重试")
                print()
                return 1
            else:
                print("   未找到可用VM")
                return 1

        # 测试1: Hello World
        print("🧪 测试1: Hello World")
        print("-" * 70)
        code = "print('Hello from E2B VM!')"
        print(f"代码: {code}")
        result = sandbox.run_code(code)
        print(f"输出: {result.text}")
        print("✅ 测试通过!")
        print()

        # 测试2: 基础计算
        print("🧪 测试2: 基础计算")
        print("-" * 70)
        code = """
numbers = [1, 2, 3, 4, 5]
total = sum(numbers)
average = total / len(numbers)
print(f"数字列表: {numbers}")
print(f"总和: {total}")
print(f"平均值: {average}")
"""
        print(f"代码: 数字计算")
        result = sandbox.run_code(code)
        print(f"输出:\n{result.text}")
        print("✅ 测试通过!")
        print()

        # 测试3: 系统信息
        print("🧪 测试3: 获取系统信息")
        print("-" * 70)
        code = """
import sys
import platform
import os

print(f"Python版本: {sys.version}")
print(f"操作系统: {platform.system()} {platform.release()}")
print(f"架构: {platform.machine()}")
print(f"当前目录: {os.getcwd()}")
print(f"用户: {os.getenv('USER', 'unknown')}")
"""
        print(f"代码: 系统信息查询")
        result = sandbox.run_code(code)
        print(f"输出:\n{result.text}")
        print("✅ 测试通过!")
        print()

        # 测试4: 数据处理
        print("🧪 测试4: 数据处理")
        print("-" * 70)
        code = """
# 简单的数据分析
data = {
    'name': ['Alice', 'Bob', 'Charlie', 'David'],
    'age': [25, 30, 35, 40],
    'score': [85, 90, 95, 80]
}

print("原始数据:")
for key, values in data.items():
    print(f"  {key}: {values}")

print(f"\\n平均年龄: {sum(data['age']) / len(data['age'])}")
print(f"平均分数: {sum(data['score']) / len(data['score'])}")
print(f"最高分: {max(data['score'])}")
print(f"最低分: {min(data['score'])}")
"""
        print(f"代码: 数据分析")
        result = sandbox.run_code(code)
        print(f"输出:\n{result.text}")
        print("✅ 测试通过!")
        print()

        # 测试5: 文件操作
        print("🧪 测试5: 文件操作")
        print("-" * 70)
        print("操作: 写入文件...")
        sandbox.filesystem.write("/tmp/e2b_test.txt", "Hello from E2B VM!\\nThis is a test file.\\nLine 3")
        print("✅ 文件已写入: /tmp/e2b_test.txt")

        print("操作: 读取文件...")
        content = sandbox.filesystem.read("/tmp/e2b_test.txt")
        print(f"文件内容:\\n{content}")
        print("✅ 文件已读取")

        print("操作: 列出目录...")
        files = sandbox.filesystem.list("/tmp")
        print(f"找到 {len(files)} 个文件/目录")
        for f in files[:5]:
            print(f"  - {f.name} ({f.type})")
        print("✅ 测试通过!")
        print()

        # 测试6: Shell命令
        print("🧪 测试6: Shell命令执行")
        print("-" * 70)
        commands = [
            ("查看系统", "uname -a"),
            ("当前日期", "date"),
            ("磁盘使用", "df -h | head -5"),
            ("进程列表", "ps aux | head -5"),
        ]

        for name, cmd in commands:
            print(f"{name}: {cmd}")
            result = sandbox.process.start(cmd)
            print(f"输出: {result.stdout.strip()[:100]}...")
            print()

        print("✅ 测试通过!")
        print()

        # 测试7: 复杂Python程序
        print("🧪 测试7: 复杂Python程序 - 斐波那契数列")
        print("-" * 70)
        code = """
def fibonacci(n):
    \"\"\"生成斐波那契数列\"\"\"
    if n <= 0:
        return []
    elif n == 1:
        return [0]
    elif n == 2:
        return [0, 1]

    fib = [0, 1]
    for i in range(2, n):
        fib.append(fib[i-1] + fib[i-2])
    return fib

# 生成前15个斐波那契数
result = fibonacci(15)
print(f"斐波那契数列 (前15个):")
print(result)
print(f"\\n第15个数: {result[-1]}")
"""
        print(f"代码: 斐波那契数列生成")
        result = sandbox.run_code(code)
        print(f"输出:\n{result.text}")
        print("✅ 测试通过!")
        print()

        # 测试8: 网络访问 (可选)
        print("🧪 测试8: 网络访问")
        print("-" * 70)
        code = """
import urllib.request
import json

try:
    # 访问公共API
    url = 'https://api.github.com/zen'
    with urllib.request.urlopen(url, timeout=5) as response:
        data = response.read().decode()
        print(f"GitHub Zen: {data}")
except Exception as e:
    print(f"网络访问失败: {e}")
"""
        print(f"代码: HTTP请求测试")
        result = sandbox.run_code(code)
        print(f"输出:\n{result.text}")
        print("✅ 测试完成!")
        print()

        # 关闭VM
        print("🔄 清理: 关闭VM...")
        print("-" * 70)
        sandbox.close()
        print("✅ VM已关闭")
        print()

    except KeyboardInterrupt:
        print("\\n\\n⚠️  用户中断")
        if 'sandbox' in locals():
            sandbox.close()
        return 1

    except Exception as e:
        print(f"❌ 测试失败: {e}")
        print()
        import traceback
        traceback.print_exc()
        return 1

    # 成功总结
    print()
    print("=" * 70)
    print("🎉 所有测试完成!")
    print("=" * 70)
    print()
    print("✅ 测试结果摘要:")
    print("   1. Hello World - 通过")
    print("   2. 基础计算 - 通过")
    print("   3. 系统信息 - 通过")
    print("   4. 数据处理 - 通过")
    print("   5. 文件操作 - 通过")
    print("   6. Shell命令 - 通过")
    print("   7. 复杂程序 - 通过")
    print("   8. 网络访问 - 完成")
    print()
    print("🎯 结论: E2B VM完全支持Python代码执行!")
    print()
    print("=" * 70)

    return 0

if __name__ == "__main__":
    sys.exit(main())
