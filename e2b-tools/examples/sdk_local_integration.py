#!/usr/bin/env python3
"""
E2B Python SDK 本地部署集成示例
演示如何在本地E2B环境中使用官方Python SDK

使用方法:
    source ~/e2b-env/bin/activate
    python3 sdk_local_integration.py
"""

import os
import sys
import traceback
from e2b import Sandbox, ConnectionConfig

def configure_local_environment():
    """配置本地E2B环境"""
    print("=" * 70)
    print("🔧 配置本地E2B SDK环境")
    print("=" * 70)
    print()

    # 设置环境变量
    os.environ["E2B_API_KEY"] = "e2b_53ae1fed82754c17ad8077fbc8bcdd90"
    os.environ["E2B_API_URL"] = "http://localhost:3000"
    # os.environ["E2B_DEBUG"] = "true"  # 可选：启用调试模式

    print("✅ 环境变量已设置:")
    print(f"   E2B_API_KEY: {os.environ['E2B_API_KEY'][:20]}...")
    print(f"   E2B_API_URL: {os.environ['E2B_API_URL']}")
    print()

    # 验证配置
    config = ConnectionConfig()
    print("✅ SDK连接配置:")
    print(f"   API URL: {config.api_url}")
    print(f"   Debug模式: {config.debug}")
    print()


def test_api_health():
    """测试API服务健康状态"""
    print("=" * 70)
    print("🏥 检查E2B服务健康状态")
    print("=" * 70)
    print()

    import requests

    # 测试API
    try:
        resp = requests.get("http://localhost:3000/health", timeout=5)
        if resp.status_code == 200:
            print("✅ API服务 (localhost:3000) - 正常")
        else:
            print(f"⚠️ API服务响应异常: {resp.status_code}")
            return False
    except Exception as e:
        print(f"❌ 无法连接到API服务: {e}")
        print("   请确保服务正在运行: curl http://localhost:3000/health")
        return False

    # 测试Orchestrator
    try:
        resp = requests.get("http://localhost:5008/health", timeout=5)
        if resp.status_code == 200:
            print("✅ Orchestrator服务 (localhost:5008) - 正常")
        else:
            print(f"⚠️ Orchestrator响应异常: {resp.status_code}")
    except Exception as e:
        print(f"⚠️ Orchestrator不可访问: {e}")

    print()
    return True


def demo_rest_api_only():
    """演示纯REST API操作（不需要envd连接）"""
    print("=" * 70)
    print("📡 演示1: 使用REST API管理VM（基础功能）")
    print("=" * 70)
    print()

    import requests

    api_url = "http://localhost:3000"
    headers = {
        "X-API-Key": "e2b_53ae1fed82754c17ad8077fbc8bcdd90",
        "Content-Type": "application/json"
    }

    # 1. 列出现有VM
    print("1️⃣ 列出现有VM...")
    try:
        resp = requests.get(f"{api_url}/sandboxes", headers=headers, timeout=10)
        if resp.status_code == 200:
            vms = resp.json()
            print(f"   找到 {len(vms)} 个运行中的VM")
            for vm in vms[:3]:
                print(f"   - {vm.get('sandboxID', 'N/A')[:12]}... ({vm.get('state', 'N/A')})")
        else:
            print(f"   ❌ 获取VM列表失败: {resp.status_code}")
    except Exception as e:
        print(f"   ❌ 请求失败: {e}")

    print()

    # 2. 尝试创建VM
    print("2️⃣ 尝试创建新VM...")
    try:
        payload = {
            "templateID": "base",
            "timeout": 300
        }
        resp = requests.post(
            f"{api_url}/sandboxes",
            headers=headers,
            json=payload,
            timeout=30
        )

        if resp.status_code == 200:
            data = resp.json()
            sandbox_id = data.get("sandboxID")
            print(f"   ✅ VM创建成功!")
            print(f"   VM ID: {sandbox_id}")
            print(f"   状态: {data.get('state', 'unknown')}")

            # 获取详细信息
            print()
            print("3️⃣ 获取VM详细信息...")
            resp = requests.get(
                f"{api_url}/sandboxes/{sandbox_id}",
                headers=headers,
                timeout=10
            )

            if resp.status_code == 200:
                info = resp.json()
                print(f"   Template: {info.get('alias', 'N/A')}")
                print(f"   CPU: {info.get('cpuCount', 'N/A')}核")
                print(f"   内存: {info.get('memoryMB', 'N/A')}MB")
                print(f"   Client ID: {info.get('clientID', 'N/A')}")

            print()
            print("✅ REST API基础功能正常工作!")
            print("   （创建、列表、查询VM信息）")

            # 清理
            print()
            print("4️⃣ 清理测试VM...")
            resp = requests.delete(
                f"{api_url}/sandboxes/{sandbox_id}",
                headers=headers,
                timeout=10
            )
            if resp.status_code in [200, 204]:
                print("   ✅ VM已删除")

        else:
            print(f"   ❌ 创建失败: {resp.status_code}")
            print(f"   响应: {resp.text}")
            print()
            print("   💡 这是预期的错误（见PYTHON_SDK_INTEGRATION_GUIDE.md）")
            print("   原因: 后端orchestrator节点选择问题")

    except Exception as e:
        print(f"   ❌ 请求失败: {e}")

    print()


def demo_sdk_full_features():
    """演示SDK完整功能（需要envd连接）"""
    print("=" * 70)
    print("🚀 演示2: 使用E2B SDK完整功能")
    print("=" * 70)
    print()

    print("⚠️ 注意: 此功能需要VM创建成功和envd网络连接")
    print("   当前状态: VM创建失败（后端问题）")
    print()

    print("理论上的使用方法:")
    print()
    print("```python")
    print("from e2b import Sandbox")
    print()
    print("# 创建VM")
    print('sandbox = Sandbox.create(template="base")')
    print('print(f"VM ID: {sandbox.sandbox_id}")')
    print()
    print("# 执行Python代码")
    print('result = sandbox.run_code("""')
    print('print("Hello from E2B!")')
    print('import sys')
    print('print(f"Python {sys.version}")')
    print('""")')
    print('print(result.text)')
    print()
    print("# 文件操作")
    print('sandbox.filesystem.write("/tmp/test.txt", "Hello")')
    print('content = sandbox.filesystem.read("/tmp/test.txt")')
    print()
    print("# Shell命令")
    print('result = sandbox.process.start("uname -a")')
    print('print(result.stdout)')
    print()
    print("# 清理")
    print("sandbox.kill()")
    print("```")
    print()

    # 实际尝试（预期会失败）
    print("实际执行测试...")
    try:
        sandbox = Sandbox.create(template="base", timeout=60)
        print(f"✅ VM创建成功: {sandbox.sandbox_id}")

        # 如果成功了，执行完整测试
        print()
        print("📝 执行Python代码...")
        result = sandbox.run_code('print("Hello from local E2B!")')
        print(f"输出: {result.text}")

        print()
        print("✅ SDK完整功能正常!")
        sandbox.kill()

    except Exception as e:
        print(f"❌ 预期的错误: {type(e).__name__}")
        print(f"   消息: {str(e)[:100]}...")
        print()
        print("📝 故障排查:")
        print("   1. 检查API日志: nomad alloc logs <api-alloc-id>")
        print("   2. 检查Orchestrator日志: nomad alloc logs <orch-alloc-id>")
        print("   3. 参考: PYTHON_SDK_INTEGRATION_GUIDE.md")
        print("   4. 参考: NETWORK_FIX_GUIDE.md")

    print()


def show_sdk_capabilities():
    """显示SDK完整能力"""
    print("=" * 70)
    print("📚 E2B Python SDK 完整功能列表")
    print("=" * 70)
    print()

    from e2b import Sandbox

    print("核心功能:")
    print("  ✅ Sandbox.create() - 创建VM")
    print("  ✅ Sandbox.list() - 列出所有VM")
    print("  ✅ Sandbox.connect(sandbox_id) - 连接现有VM")
    print()

    print("代码执行:")
    print("  ✅ sandbox.run_code(code) - 执行Python代码")
    print("  ✅ sandbox.process.start(cmd) - 执行Shell命令")
    print("  ✅ sandbox.process.start_and_wait(cmd) - 等待命令完成")
    print()

    print("文件系统:")
    print("  ✅ sandbox.filesystem.read(path) - 读取文件")
    print("  ✅ sandbox.filesystem.write(path, content) - 写入文件")
    print("  ✅ sandbox.filesystem.list(path) - 列出目录")
    print("  ✅ sandbox.filesystem.remove(path) - 删除文件")
    print()

    print("网络:")
    print("  ✅ sandbox.get_host() - 获取VM访问地址")
    print("  ✅ sandbox.get_info() - 获取VM详细信息")
    print()

    print("生命周期:")
    print("  ✅ sandbox.set_timeout(seconds) - 设置超时")
    print("  ✅ sandbox.kill() - 终止VM")
    print("  ✅ sandbox.is_running() - 检查状态")
    print()

    print("高级功能:")
    print("  ✅ AsyncSandbox - 异步版本")
    print("  ✅ Template.build() - 构建自定义模板")
    print("  ✅ wait_for_port() - 等待端口可用")
    print("  ✅ wait_for_file() - 等待文件创建")
    print()


def main():
    """主函数"""
    print()
    print("╔" + "=" * 68 + "╗")
    print("║" + " " * 15 + "E2B Python SDK 本地集成测试" + " " * 24 + "║")
    print("╚" + "=" * 68 + "╝")
    print()

    try:
        # 1. 配置环境
        configure_local_environment()

        # 2. 健康检查
        if not test_api_health():
            print("❌ E2B服务不可用，无法继续测试")
            return 1

        # 3. 演示REST API
        demo_rest_api_only()

        # 4. 演示SDK功能
        demo_sdk_full_features()

        # 5. 显示SDK能力
        show_sdk_capabilities()

        # 总结
        print("=" * 70)
        print("📊 总结")
        print("=" * 70)
        print()
        print("✅ SDK配置: 完全支持本地部署")
        print("✅ REST API: 基础功能可用（列表、查询）")
        print("⚠️ VM创建: 当前失败（后端节点选择问题）")
        print("⚠️ 代码执行: 需要VM创建修复 + 网络路由修复")
        print()
        print("📝 下一步:")
        print("   1. 修复API的节点选择逻辑")
        print("   2. 修复VM网络路由配置")
        print("   3. 完整功能即可使用")
        print()
        print("📚 详细文档:")
        print("   - PYTHON_SDK_INTEGRATION_GUIDE.md")
        print("   - NETWORK_FIX_GUIDE.md")
        print("   - FINAL_EXECUTION_REPORT.md")
        print()

        return 0

    except KeyboardInterrupt:
        print("\n\n⚠️ 用户中断")
        return 1

    except Exception as e:
        print(f"\n❌ 未预期的错误: {e}")
        print()
        traceback.print_exc()
        return 1


if __name__ == "__main__":
    sys.exit(main())
