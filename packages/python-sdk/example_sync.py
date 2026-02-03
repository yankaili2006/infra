#!/usr/bin/env python3
"""
E2B 同步 API 示例
使用同步方式访问本地 E2B 服务

这个示例更简单，适合快速测试
"""

import os
import sys
from pathlib import Path

# 添加 SDK 到 Python 路径
sdk_path = Path(__file__).parent
sys.path.insert(0, str(sdk_path))

from e2b import Sandbox
import dotenv

# 加载本地环境配置
dotenv.load_dotenv('.env.local')


def main():
    """同步方式使用 E2B"""

    print("=" * 60)
    print("E2B Sync API Example (本地服务)")
    print("=" * 60)
    print(f"API URL: {os.getenv('E2B_API_URL')}")
    print("=" * 60)

    # 使用 with 语句自动管理沙箱生命周期
    with Sandbox.create(
        template="base-template-000-0000-0000-000000000001",
        timeout=300
    ) as sandbox:

        print(f"\n✓ Sandbox 创建成功: {sandbox.sandbox_id}")

        # 执行命令
        print("\n执行命令: uname -a")
        result = sandbox.process.start_and_wait("uname -a")
        print(f"  输出: {result.stdout.strip()}")

        # 执行 Python 代码
        print("\n执行 Python 代码...")
        result = sandbox.process.start_and_wait("python3 -c 'print(2 + 2)'")
        print(f"  结果: {result.stdout.strip()}")

        # 文件操作
        print("\n文件操作测试...")
        sandbox.filesystem.write("/tmp/hello.txt", "Hello E2B Local!")
        content = sandbox.filesystem.read("/tmp/hello.txt")
        print(f"  读取文件内容: {content}")

        print("\n✓ 所有测试完成!")

    print("\n✓ Sandbox 已自动关闭")


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"\n✗ 错误: {e}")
        sys.exit(1)
