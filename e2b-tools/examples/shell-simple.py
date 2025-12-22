#!/usr/bin/env python3
"""
E2B 简单交互式Shell - 概念验证
不需要完整PTY，但可以执行命令并查看输出
"""

import sys
import requests
import json

class E2BShell:
    def __init__(self, sandbox_id, api_url="http://localhost:3000", api_key="e2b_53ae1fed82754c17ad8077fbc8bcdd90"):
        self.sandbox_id = sandbox_id
        self.api_url = api_url
        self.api_key = api_key
        self.headers = {
            "X-API-Key": api_key,
            "Content-Type": "application/json"
        }
        
        # 获取VM信息
        self.vm_info = self._get_vm_info()
        
    def _get_vm_info(self):
        """获取VM信息"""
        response = requests.get(
            f"{self.api_url}/sandboxes/{self.sandbox_id}",
            headers={"X-API-Key": self.api_key}
        )
        if response.status_code == 200:
            return response.json()
        else:
            print(f"错误: 无法获取VM信息 (HTTP {response.status_code})")
            sys.exit(1)
    
    def exec_command(self, command):
        """
        执行命令（通过API或envd）
        注意: 这是简化版，真正的实现需要直接连接envd的gRPC接口
        """
        print(f"[模拟执行] {command}")
        print("注意: 当前为模拟模式")
        print("真正的执行需要连接到envd gRPC接口")
        print(f"envd地址: 可以从VM metadata获取")
        print()
        
        # TODO: 实现真正的envd gRPC调用
        # 参考: /home/primihub/pcloud/infra/packages/shared/pkg/grpc/envd/
        
        return None
    
    def run(self):
        """运行交互式shell"""
        print("=" * 60)
        print(f"E2B 简单Shell - VM: {self.sandbox_id[:12]}...")
        print(f"状态: {self.vm_info.get('state', 'unknown')}")
        print(f"模板: {self.vm_info.get('alias', 'unknown')}")
        print("=" * 60)
        print()
        print("注意: 这是概念验证版本，显示如何实现交互式访问")
        print("完整实现需要:")
        print("  1. 安装 grpcio 和 e2b proto定义")
        print("  2. 直接连接到 envd (port 49983)")
        print("  3. 实现PTY支持以获得完整终端体验")
        print()
        print("输入 'exit' 退出, 'help' 查看帮助")
        print()
        
        while True:
            try:
                command = input(f"e2b@{self.sandbox_id[:8]}> ").strip()
                
                if not command:
                    continue
                    
                if command == "exit":
                    print("断开连接")
                    break
                    
                if command == "help":
                    self.show_help()
                    continue
                
                # 执行命令
                self.exec_command(command)
                
            except KeyboardInterrupt:
                print("\n使用 'exit' 退出")
                continue
            except EOFError:
                print("\n断开连接")
                break
    
    def show_help(self):
        """显示帮助"""
        print("""
可用命令:
  任意Linux命令  - 在VM中执行（模拟）
  help          - 显示帮助
  exit          - 退出shell
  
实现真正的交互式shell需要:
  1. 使用 grpcio 连接到 envd
  2. 调用 process.Process/Start with PTY
  3. 实现流式输入输出处理
  
示例代码:
  import grpc
  from e2b_envd import ProcessServiceStub
  
  channel = grpc.insecure_channel('10.11.13.173:49983')
  client = ProcessServiceStub(channel)
  # ... 实现PTY通信
""")

def main():
    if len(sys.argv) < 2:
        print("用法: python3 e2b-shell-simple.py <sandbox-id>")
        print()
        print("获取运行中的VM:")
        print("  e2b ls")
        sys.exit(1)
    
    sandbox_id = sys.argv[1]
    
    try:
        shell = E2BShell(sandbox_id)
        shell.run()
    except Exception as e:
        print(f"错误: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
