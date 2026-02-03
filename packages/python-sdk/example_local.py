#!/usr/bin/env python3
"""
E2B Local Infrastructure Example
使用本地 E2B 基础设施的示例脚本

确保运行前：
1. 本地 E2B 服务已启动（API on localhost:3000）
2. 已安装依赖: pip install python-dotenv
3. 配置了 .env.local 文件
"""

import os
import sys
import asyncio
import logging
from pathlib import Path

# 添加 SDK 到 Python 路径
sdk_path = Path(__file__).parent
sys.path.insert(0, str(sdk_path))

from e2b import AsyncSandbox
import dotenv

# 加载本地环境配置
dotenv.load_dotenv('.env.local')

# 配置日志
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


async def main():
    """主函数 - 演示本地 E2B 使用"""

    # 显示配置信息
    logger.info("=" * 60)
    logger.info("E2B Local Infrastructure Example")
    logger.info("=" * 60)
    logger.info(f"API URL: {os.getenv('E2B_API_URL', 'Not Set')}")
    logger.info(f"Debug Mode: {os.getenv('E2B_DEBUG', 'false')}")
    logger.info(f"API Key: {os.getenv('E2B_API_KEY', 'Not Set')[:20]}...")
    logger.info("=" * 60)

    try:
        # 创建沙箱
        logger.info("Creating sandbox...")
        sandbox = await AsyncSandbox.create(
            template="base-template-000-0000-0000-000000000001",
            timeout=300
        )

        logger.info(f"✓ Sandbox created: {sandbox.sandbox_id}")
        logger.info(f"  Template: {sandbox.template_id}")

        # 执行简单命令
        logger.info("\nExecuting command: echo 'Hello from E2B Local!'")
        result = await sandbox.process.start_and_wait("echo 'Hello from E2B Local!'")
        logger.info(f"  stdout: {result.stdout}")
        logger.info(f"  stderr: {result.stderr}")
        logger.info(f"  exit_code: {result.exit_code}")

        # 执行 Python 代码
        logger.info("\nExecuting Python code...")
        python_code = """
import sys
print(f"Python version: {sys.version}")
print("Hello from Python in E2B sandbox!")
"""
        result = await sandbox.process.start_and_wait(f"python3 -c '{python_code}'")
        logger.info(f"  stdout:\n{result.stdout}")

        # 文件系统操作
        logger.info("\nTesting filesystem operations...")

        # 写入文件
        test_content = "Hello from E2B Local Infrastructure!"
        await sandbox.filesystem.write("/tmp/test.txt", test_content)
        logger.info(f"  ✓ Written to /tmp/test.txt")

        # 读取文件
        content = await sandbox.filesystem.read("/tmp/test.txt")
        logger.info(f"  ✓ Read from /tmp/test.txt: {content}")

        # 列出文件
        files = await sandbox.filesystem.list("/tmp")
        logger.info(f"  ✓ Files in /tmp: {[f.name for f in files[:5]]}")

        # 关闭沙箱
        logger.info("\nClosing sandbox...")
        await sandbox.close()
        logger.info("✓ Sandbox closed")

        logger.info("\n" + "=" * 60)
        logger.info("✓ All tests passed!")
        logger.info("=" * 60)

    except Exception as e:
        logger.error(f"✗ Error: {e}", exc_info=True)
        return 1

    return 0


if __name__ == "__main__":
    exit_code = asyncio.run(main())
    sys.exit(exit_code)
