#!/usr/bin/env python3
"""
创建E2B虚拟机的简单脚本
"""

import os
import sys
from e2b import Sandbox

def main():
    print("=" * 50)
    print("E2B 虚拟机创建脚本")
    print("=" * 50)
    
    # 设置环境变量
    os.environ["E2B_API_KEY"] = "e2b_53ae1fed82754c17ad8077fbc8bcdd90"
    os.environ["E2B_API_URL"] = "http://localhost:3000"
    
    print(f"API URL: {os.environ['E2B_API_URL']}")
    print(f"API Key: {os.environ['E2B_API_KEY'][:10]}...")
    print()
    
    try:
        print("1. 尝试连接到E2B API...")
        
        # 首先尝试列出可用的模板
        print("2. 检查可用的模板...")
        
        # 尝试创建沙箱（虚拟机）
        print("3. 创建虚拟机...")
        
        # 使用默认模板创建沙箱
        sandbox = Sandbox(
            template="base",  # 基础模板
            timeout=300,      # 5分钟超时
            metadata={
                "name": "test-vm-from-python",
                "purpose": "testing e2b integration"
            }
        )
        
        print(f"✓ 虚拟机创建成功!")
        print(f"  虚拟机ID: {sandbox.sandbox_id}")
        print(f"  状态: {sandbox.state}")
        print()
        
        # 执行一个简单的命令
        print("4. 在虚拟机中执行命令...")
        result = sandbox.run_code("echo 'Hello from E2B VM!' && uname -a")
        print(f"  命令输出: {result}")
        print()
        
        # 获取虚拟机信息
        print("5. 虚拟机信息:")
        print(f"  - 主机名: {sandbox.hostname}")
        print(f"  - 端口: {sandbox.ports}")
        print(f"  - 进程ID: {sandbox.process_id}")
        
        print()
        print("6. 虚拟机操作:")
        print("   - 执行命令: sandbox.run_code('your command')")
        print("   - 上传文件: sandbox.upload_file('local_path', 'remote_path')")
        print("   - 下载文件: sandbox.download_file('remote_path', 'local_path')")
        print("   - 关闭虚拟机: sandbox.close()")
        
        # 保持虚拟机运行
        print()
        print("虚拟机正在运行...")
        print("按 Ctrl+C 停止虚拟机")
        
        # 等待用户输入
        input("按 Enter 键关闭虚拟机...")
        
        # 关闭虚拟机
        print("正在关闭虚拟机...")
        sandbox.close()
        print("✓ 虚拟机已关闭")
        
    except Exception as e:
        print(f"✗ 错误: {e}")
        print()
        print("故障排除:")
        print("1. 确保E2B服务正在运行:")
        print("   - API: http://localhost:3000/health")
        print("   - Orchestrator: http://localhost:5008/health")
        print("2. 检查API密钥是否正确")
        print("3. 确保有可用的模板")
        return 1
    
    return 0

if __name__ == "__main__":
    sys.exit(main())