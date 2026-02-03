#!/usr/bin/env python3
"""
E2B Python SDK 基础测试
测试 SDK 基本功能，不需要完整 E2B 服务运行

测试内容：
1. SDK 模块导入
2. 配置加载
3. 连接配置创建
4. 基础类型检查
"""

import sys
import os
from pathlib import Path

# 添加 SDK 路径
sdk_path = Path(__file__).parent
sys.path.insert(0, str(sdk_path))

print("=" * 70)
print("E2B Python SDK 基础测试")
print("=" * 70)

# 测试 1: 导入核心模块
print("\n[测试 1] 导入核心模块...")
try:
    from e2b import Sandbox, AsyncSandbox
    from e2b.connection_config import ConnectionConfig, ApiParams
    from e2b.exceptions import SandboxError
    print("  ✓ 核心模块导入成功")
    print(f"    - Sandbox: {Sandbox}")
    print(f"    - AsyncSandbox: {AsyncSandbox}")
    print(f"    - ConnectionConfig: {ConnectionConfig}")
except ImportError as e:
    print(f"  ✗ 导入失败: {e}")
    sys.exit(1)

# 测试 2: 加载环境配置
print("\n[测试 2] 加载环境配置...")
try:
    import dotenv
    env_file = sdk_path / '.env.local'
    if env_file.exists():
        dotenv.load_dotenv(env_file)
        print(f"  ✓ 配置文件加载成功: {env_file}")

        # 显示配置
        api_url = os.getenv('E2B_API_URL', 'Not Set')
        api_key = os.getenv('E2B_API_KEY', 'Not Set')
        debug = os.getenv('E2B_DEBUG', 'false')

        print(f"    - E2B_API_URL: {api_url}")
        print(f"    - E2B_API_KEY: {api_key[:20]}..." if api_key != 'Not Set' else "    - E2B_API_KEY: Not Set")
        print(f"    - E2B_DEBUG: {debug}")
    else:
        print(f"  ⚠ 配置文件不存在: {env_file}")
except Exception as e:
    print(f"  ✗ 配置加载失败: {e}")

# 测试 3: 创建连接配置对象
print("\n[测试 3] 创建连接配置对象...")
try:
    config = ConnectionConfig(
        api_url="http://localhost:3000",
        api_key="test-key",
        debug=True
    )
    print("  ✓ ConnectionConfig 创建成功")
    print(f"    - API URL: {config.api_url}")
    print(f"    - Debug: {config.debug}")
    print(f"    - Domain: {config.domain}")
    print(f"    - Request Timeout: {config.request_timeout}s")
except Exception as e:
    print(f"  ✗ 创建失败: {e}")
    sys.exit(1)

# 测试 4: 测试配置方法
print("\n[测试 4] 测试配置方法...")
try:
    # 测试 get_host
    host = config.get_host(
        sandbox_id="test-sandbox",
        sandbox_domain="e2b.local",
        port=49983
    )
    print(f"  ✓ get_host(): {host}")

    # 测试 get_sandbox_url
    sandbox_url = config.get_sandbox_url(
        sandbox_id="test-sandbox",
        sandbox_domain="e2b.local"
    )
    print(f"  ✓ get_sandbox_url(): {sandbox_url}")

    # 测试 get_api_params
    api_params = config.get_api_params()
    print(f"  ✓ get_api_params() 返回 {len(api_params)} 个参数")
except Exception as e:
    print(f"  ✗ 方法调用失败: {e}")
    sys.exit(1)

# 测试 5: 检查依赖包
print("\n[测试 5] 检查依赖包...")
dependencies = {
    'httpx': 'HTTP 客户端',
    'protobuf': 'Protocol Buffers',
    'python_dateutil': '日期处理',
    'wcmatch': '文件匹配',
}

for module, desc in dependencies.items():
    try:
        __import__(module)
        print(f"  ✓ {module:20s} - {desc}")
    except ImportError:
        print(f"  ✗ {module:20s} - {desc} (未安装)")

# 测试 6: SDK 版本信息
print("\n[测试 6] SDK 版本信息...")
try:
    from e2b.api.metadata import package_version
    print(f"  ✓ E2B SDK 版本: {package_version}")
except Exception as e:
    print(f"  ⚠ 无法获取版本: {e}")

# 测试 7: 检查 Protocol Buffer 定义
print("\n[测试 7] 检查 Protocol Buffer 定义...")
try:
    from e2b.envd.process import process_pb2
    from e2b.envd.filesystem import filesystem_pb2
    print("  ✓ 进程管理 proto 定义已加载")
    print("  ✓ 文件系统 proto 定义已加载")
except ImportError as e:
    print(f"  ⚠ Proto 定义加载失败: {e}")

# 测试总结
print("\n" + "=" * 70)
print("✓ 基础测试完成！")
print("=" * 70)
print("\n💡 提示：")
print("   - SDK 模块可以正常导入和使用")
print("   - 要运行完整功能测试，需要启动 E2B 服务：")
print("     cd /home/primihub/pcloud/infra/local-deploy")
print("     ./scripts/start-all.sh")
print()
print("   - 然后运行完整示例：")
print("     python3 example_sync.py")
print("=" * 70)
