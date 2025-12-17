#!/usr/bin/env python3
"""
简单的E2B测试脚本
使用E2B Python SDK创建和运行沙箱
"""

import os
import sys
import time

# 尝试导入E2B SDK
try:
    from e2b import Sandbox
    print("✓ E2B SDK 已安装")
except ImportError:
    print("✗ E2B SDK 未安装，尝试安装...")
    os.system("pip install e2b")
    try:
        from e2b import Sandbox
        print("✓ E2B SDK 安装成功")
    except ImportError:
        print("✗ 无法安装E2B SDK")
        sys.exit(1)

def test_e2b_sandbox():
    """测试E2B沙箱"""
    print("\n=== 测试E2B沙箱 ===")
    
    try:
        # 创建沙箱
        print("1. 创建沙箱...")
        sandbox = Sandbox(
            template="base",  # 使用基础模板
            api_key="test-key",  # 本地部署不需要API key
            cwd="/home/user"
        )
        print("   ✓ 沙箱创建成功")
        
        # 运行命令
        print("2. 运行测试命令...")
        result = sandbox.process.start("echo 'Hello from E2B Sandbox!'")
        print(f"   输出: {result.stdout}")
        
        # 检查系统信息
        print("3. 检查系统信息...")
        result = sandbox.process.start("uname -a")
        print(f"   系统: {result.stdout}")
        
        # 检查Python版本
        print("4. 检查Python版本...")
        result = sandbox.process.start("python3 --version")
        print(f"   Python: {result.stdout}")
        
        # 运行Python代码
        print("5. 运行Python代码...")
        code = """
import platform
print(f"Python {platform.python_version()} on {platform.system()} {platform.release()}")
print("E2B沙箱工作正常！")
"""
        result = sandbox.process.start(f"python3 -c \"{code}\"")
        print(f"   输出: {result.stdout}")
        
        # 关闭沙箱
        print("6. 关闭沙箱...")
        sandbox.close()
        print("   ✓ 沙箱已关闭")
        
        print("\n=== E2B测试完成 ===")
        print("✓ 所有测试通过")
        return True
        
    except Exception as e:
        print(f"✗ 测试失败: {e}")
        return False

def test_local_e2b():
    """测试本地E2B部署"""
    print("\n=== 测试本地E2B部署 ===")
    
    # 检查必要的服务
    services = {
        "Docker": "docker ps",
        "KVM": "ls /dev/kvm",
        "Firecracker": "which firecracker || echo '未安装'",
    }
    
    for service, cmd in services.items():
        print(f"检查 {service}...")
        result = os.system(f"{cmd} > /dev/null 2>&1")
        if result == 0:
            print(f"  ✓ {service} 可用")
        else:
            print(f"  ✗ {service} 不可用")
    
    # 尝试启动简单的E2B服务
    print("\n尝试启动简化E2B服务...")
    
    # 创建简单的Docker Compose文件
    compose_content = """
version: '3.8'
services:
  e2b-api:
    image: e2bdev/api:latest
    ports:
      - "3000:3000"
    environment:
      - DATABASE_URL=postgresql://postgres:postgres@db:5432/e2b
      - REDIS_URL=redis://redis:6379
    depends_on:
      - db
      - redis
  
  db:
    image: postgres:15-alpine
    environment:
      - POSTGRES_USER=postgres
      - POSTGRES_PASSWORD=postgres
      - POSTGRES_DB=e2b
    volumes:
      - postgres_data:/var/lib/postgresql/data
  
  redis:
    image: redis:7-alpine
    volumes:
      - redis_data:/data

volumes:
  postgres_data:
  redis_data:
"""
    
    with open("/tmp/docker-compose-e2b.yml", "w") as f:
        f.write(compose_content)
    
    print("简化E2B Docker Compose配置已创建")
    print("文件位置: /tmp/docker-compose-e2b.yml")
    
    return True

if __name__ == "__main__":
    print("E2B部署测试")
    print("=" * 50)
    
    # 测试1: E2B SDK
    # test_e2b_sandbox()
    
    # 测试2: 本地E2B部署
    test_local_e2b()
    
    print("\n下一步:")
    print("1. 下载E2B镜像: docker pull e2bdev/api:latest")
    print("2. 启动服务: docker compose -f /tmp/docker-compose-e2b.yml up -d")
    print("3. 访问API: http://localhost:3000/health")