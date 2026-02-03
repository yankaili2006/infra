#!/usr/bin/env python3
"""
在 E2B 虚拟机中执行 Python 代码的简单测试

直接使用 REST API 创建 VM 并展示如何执行代码
"""

import sys
import os
from pathlib import Path

# 添加 SDK 路径
sdk_path = Path(__file__).parent
sys.path.insert(0, str(sdk_path))

from e2b import Sandbox
import dotenv

# 加载配置
dotenv.load_dotenv('.env.local')

print("=" * 70)
print("E2B 虚拟机 Python 代码执行测试")
print("=" * 70)
print(f"API URL: {os.getenv('E2B_API_URL')}")
print("=" * 70)

try:
    # 使用简单的模板名称 "base"
    print("\n[1] 创建虚拟机沙箱...")
    sandbox = Sandbox.create(template="base", timeout=300)
    print(f"✓ 沙箱创建成功: {sandbox.sandbox_id}")

    # 执行简单的 Python 代码
    print("\n[2] 执行 Python 代码: print('Hello from E2B VM!')")
    result = sandbox.commands.run("python3 -c \"print('Hello from E2B VM!')\"")
    print(f"✓ 输出: {result.stdout.strip()}")
    print(f"  退出码: {result.exit_code}")

    # 执行更复杂的 Python 代码
    print("\n[3] 执行复杂 Python 代码...")
    python_code = """
import sys
import os

print(f'Python 版本: {sys.version}')
print(f'当前目录: {os.getcwd()}')
print(f'用户: {os.getenv("USER", "unknown")}')

# 简单计算
numbers = [1, 2, 3, 4, 5]
total = sum(numbers)
print(f'1+2+3+4+5 = {total}')
"""

    # 将代码写入文件并执行
    sandbox.filesystem.write("/tmp/test.py", python_code)
    result = sandbox.commands.run("python3 /tmp/test.py")
    print("✓ 输出:")
    for line in result.stdout.strip().split('\n'):
        print(f"  {line}")

    # 测试文件系统操作
    print("\n[4] 测试文件系统操作...")
    sandbox.filesystem.write("/tmp/hello.txt", "Hello from E2B!")
    content = sandbox.filesystem.read("/tmp/hello.txt")
    print(f"✓ 写入并读取文件: {content}")

    # 列出目录
    print("\n[5] 列出 /tmp 目录...")
    result = sandbox.commands.run("ls -lh /tmp")
    print("✓ 目录内容:")
    for line in result.stdout.strip().split('\n')[:5]:  # 只显示前5行
        print(f"  {line}")

    # 测试 numpy (如果可用)
    print("\n[6] 测试 Python 包安装和使用...")
    install_result = sandbox.commands.run("pip install numpy -q", timeout=60)
    if install_result.exit_code == 0:
        result = sandbox.commands.run(
            "python3 -c 'import numpy as np; arr = np.array([1,2,3,4,5]); print(f\"数组: {arr}\"); print(f\"平均值: {arr.mean()}\")'"
        )
        print("✓ numpy 测试:")
        for line in result.stdout.strip().split('\n'):
            print(f"  {line}")
    else:
        print("⚠ numpy 安装失败（可能网络问题）")

    # 关闭沙箱
    print("\n[7] 关闭沙箱...")
    sandbox.close()
    print("✓ 沙箱已关闭")

    print("\n" + "=" * 70)
    print("✓ 所有测试完成！虚拟机Python代码执行成功！")
    print("=" * 70)

except Exception as e:
    print(f"\n✗ 错误: {e}")
    import traceback
    traceback.print_exc()
    sys.exit(1)
