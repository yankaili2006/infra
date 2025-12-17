#!/usr/bin/env python3
"""
简单的E2B测试脚本
测试E2B SDK的基本功能
"""

import os
import sys

# 激活虚拟环境
venv_path = "/root/pcloud/e2b-venv"
activate_script = os.path.join(venv_path, "bin", "activate_this.py")
with open(activate_script) as f:
    exec(f.read(), {'__file__': activate_script})

try:
    from e2b import Sandbox
    print("✓ E2B SDK 导入成功")
except ImportError as e:
    print(f"✗ 无法导入E2B SDK: {e}")
    sys.exit(1)

def test_e2b_local():
    """测试E2B本地功能"""
    print("\n=== 测试E2B本地功能 ===")
    
    try:
        # 尝试创建沙箱
        print("1. 尝试创建沙箱...")
        
        # 对于本地部署，我们需要指定自定义端点
        sandbox = Sandbox(
            template="base",
            api_key="local-test",  # 本地测试不需要真实API key
            cwd="/home/user",
            # 尝试使用本地端点
            # domain="localhost:3000"  # 本地API端点
        )
        
        print("   ✓ 沙箱对象创建成功")
        
        # 运行简单命令
        print("2. 运行测试命令...")
        try:
            # 注意：这需要E2B服务正在运行
            result = sandbox.process.start("echo 'Hello E2B'")
            print(f"   输出: {result.stdout}")
        except Exception as e:
            print(f"   注意: 命令执行失败（需要E2B服务）: {e}")
        
        # 获取沙箱信息
        print("3. 沙箱信息:")
        print(f"   ID: {sandbox.id}")
        print(f"   模板: {sandbox.template}")
        
        # 关闭沙箱
        print("4. 关闭沙箱...")
        sandbox.close()
        print("   ✓ 沙箱已关闭")
        
        return True
        
    except Exception as e:
        print(f"✗ 测试失败: {e}")
        print("\n这可能是正常的，因为:")
        print("1. 需要E2B API服务正在运行")
        print("2. 需要配置正确的API端点")
        print("3. 需要有效的API密钥")
        return False

def check_system_requirements():
    """检查系统要求"""
    print("\n=== 系统要求检查 ===")
    
    requirements = {
        "Docker": "docker --version",
        "KVM设备": "ls /dev/kvm",
        "当前用户在kvm组": "groups | grep kvm",
        "当前用户在docker组": "groups | grep docker",
        "内存": "free -h | head -2",
        "CPU虚拟化": "grep -E '(vmx|svm)' /proc/cpuinfo | head -1",
    }
    
    all_ok = True
    for name, cmd in requirements.items():
        print(f"检查 {name}...")
        result = os.system(f"{cmd} > /dev/null 2>&1")
        if result == 0:
            print(f"  ✓ {name} 通过")
        else:
            print(f"  ✗ {name} 失败")
            all_ok = False
    
    return all_ok

def create_simple_e2b_service():
    """创建简单的E2B服务配置"""
    print("\n=== 创建简单E2B服务配置 ===")
    
    # Docker Compose配置
    compose = """version: '3.8'
services:
  # E2B API服务
  e2b-api:
    image: e2bdev/api:latest
    ports:
      - "3000:3000"
    environment:
      - DATABASE_URL=postgresql://postgres:postgres@db:5432/e2b
      - REDIS_URL=redis://redis:6379/0
      - NODE_ENV=development
    depends_on:
      - db
      - redis
    volumes:
      - /tmp/e2b-template-storage:/tmp/e2b-template-storage
      - /tmp/e2b-template-cache:/tmp/e2b-template-cache
    cap_add:
      - NET_ADMIN
      - SYS_ADMIN
    devices:
      - /dev/kvm:/dev/kvm
      - /dev/net/tun:/dev/net/tun
  
  # 数据库
  db:
    image: postgres:15-alpine
    environment:
      - POSTGRES_USER=postgres
      - POSTGRES_PASSWORD=postgres
      - POSTGRES_DB=e2b
    volumes:
      - postgres_data:/var/lib/postgresql/data
  
  # Redis
  redis:
    image: redis:7-alpine
    command: redis-server --appendonly yes
    volumes:
      - redis_data:/data

volumes:
  postgres_data:
  redis_data:
"""
    
    config_file = "/tmp/e2b-docker-compose.yml"
    with open(config_file, "w") as f:
        f.write(compose)
    
    print(f"✓ Docker Compose配置已创建: {config_file}")
    
    # 创建存储目录
    os.system("mkdir -p /tmp/e2b-template-storage /tmp/e2b-template-cache")
    print("✓ 存储目录已创建")
    
    return config_file

if __name__ == "__main__":
    print("E2B完整部署测试")
    print("=" * 60)
    
    # 检查系统要求
    if not check_system_requirements():
        print("\n⚠ 一些系统要求未满足")
        print("但我们可以继续尝试...")
    
    # 创建E2B服务配置
    compose_file = create_simple_e2b_service()
    
    # 测试E2B SDK
    test_e2b_local()
    
    print("\n" + "=" * 60)
    print("E2B部署准备完成！")
    print("\n下一步操作:")
    print(f"1. 下载E2B镜像: docker pull e2bdev/api:latest")
    print(f"2. 启动服务: docker compose -f {compose_file} up -d")
    print(f"3. 检查服务: docker compose -f {compose_file} ps")
    print(f"4. 查看日志: docker compose -f {compose_file} logs -f")
    print(f"5. 测试API: curl http://localhost:3000/health")
    print("\n注意: E2B API镜像可能需要从Docker Hub下载")
    print("如果下载失败，可以尝试构建本地镜像")