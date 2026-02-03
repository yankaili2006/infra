#!/usr/bin/env python3
"""
E2B Infrastructure CLI Tool
一个方便的命令行工具，用于管理和运行 E2B Firecracker VM 演示

使用方法:
  ./infra_cli.py [命令] [选项]

命令:
  list        列出所有可用的演示
  run         运行指定的演示
  status      查看系统状态
  help        显示帮助信息
"""

import os
import sys
import subprocess
import argparse
import json
from pathlib import Path
from datetime import datetime


class Colors:
    """终端颜色"""
    HEADER = '\033[95m'
    BLUE = '\033[94m'
    CYAN = '\033[96m'
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    RED = '\033[91m'
    BOLD = '\033[1m'
    UNDERLINE = '\033[4m'
    END = '\033[0m'


class InfraCLI:
    """E2B Infrastructure CLI"""

    def __init__(self):
        self.base_dir = Path(__file__).parent
        self.bridge_manager_script = self.base_dir / 'socat_bridge_manager.sh'
        self.demos = {
            'sdk': {
                'name': 'SDK 完整演示',
                'script': 'e2b_vm_complete_demo.py',
                'description': '使用 E2B Python SDK 创建新的 Firecracker VM 并执行完整功能测试',
                'features': [
                    'VM 创建和销毁',
                    'Python 代码执行',
                    'Shell 命令执行',
                    '文件系统操作',
                    '数据处理分析',
                    '网络功能测试'
                ],
                'duration': '~2-3 分钟',
                'requires_api': True
            },
            'existing': {
                'name': '现有 VM 演示',
                'script': 'e2b_existing_vm_demo.py',
                'description': '连接到已运行的 Firecracker VM 并演示各种功能',
                'features': [
                    'VM 连接验证',
                    'Python 代码执行',
                    'Shell 命令执行',
                    '文件系统操作',
                    '数据统计分析',
                    '网络测试'
                ],
                'duration': '~1-2 分钟',
                'requires_api': False
            }
        }

    def print_banner(self):
        """打印欢迎横幅"""
        banner = f"""
{Colors.CYAN}{Colors.BOLD}╔══════════════════════════════════════════════════════════════╗
║                                                              ║
║        E2B Infrastructure CLI Tool v1.0                      ║
║        Firecracker VM 演示管理工具                            ║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝{Colors.END}
"""
        print(banner)

    def print_section(self, title):
        """打印章节标题"""
        print(f"\n{Colors.BOLD}{Colors.BLUE}{'='*70}{Colors.END}")
        print(f"{Colors.BOLD}{Colors.BLUE}  {title}{Colors.END}")
        print(f"{Colors.BOLD}{Colors.BLUE}{'='*70}{Colors.END}\n")

    def print_success(self, message):
        """打印成功消息"""
        print(f"{Colors.GREEN}✅ {message}{Colors.END}")

    def print_error(self, message):
        """打印错误消息"""
        print(f"{Colors.RED}❌ {message}{Colors.END}")

    def print_warning(self, message):
        """打印警告消息"""
        print(f"{Colors.YELLOW}⚠️  {message}{Colors.END}")

    def print_info(self, message):
        """打印信息消息"""
        print(f"{Colors.CYAN}ℹ️  {message}{Colors.END}")

    def check_prerequisites(self):
        """检查系统先决条件"""
        self.print_section("系统先决条件检查")

        checks = []

        # 检查 Python 版本
        python_version = sys.version.split()[0]
        checks.append({
            'name': 'Python 版本',
            'status': True,
            'detail': f'v{python_version}'
        })

        # 检查 E2B SDK
        try:
            import e2b
            try:
                version = e2b.__version__
            except AttributeError:
                version = '已安装'
            checks.append({
                'name': 'E2B SDK',
                'status': True,
                'detail': f'v{version}'
            })
        except ImportError:
            checks.append({
                'name': 'E2B SDK',
                'status': False,
                'detail': '未安装 (pip install e2b)'
            })

        # 检查演示脚本
        for demo_id, demo in self.demos.items():
            script_path = self.base_dir / demo['script']
            checks.append({
                'name': f"脚本: {demo['script']}",
                'status': script_path.exists(),
                'detail': str(script_path) if script_path.exists() else '未找到'
            })

        # 检查服务状态
        try:
            result = subprocess.run(['curl', '-s', 'http://localhost:3000/health'],
                                  capture_output=True, text=True, timeout=3)
            api_status = 'Health check successful' in result.stdout
            checks.append({
                'name': 'E2B API (Port 3000)',
                'status': api_status,
                'detail': '运行中' if api_status else '未运行'
            })
        except:
            checks.append({
                'name': 'E2B API (Port 3000)',
                'status': False,
                'detail': '无法连接'
            })

        try:
            result = subprocess.run(['curl', '-s', 'http://localhost:5008/health'],
                                  capture_output=True, text=True, timeout=3)
            orch_status = 'healthy' in result.stdout
            checks.append({
                'name': 'Orchestrator (Port 5008)',
                'status': orch_status,
                'detail': '运行中' if orch_status else '未运行'
            })
        except:
            checks.append({
                'name': 'Orchestrator (Port 5008)',
                'status': False,
                'detail': '无法连接'
            })

        # 检查 Firecracker VM
        try:
            result = subprocess.run(['ps', 'aux'], capture_output=True, text=True)
            vm_count = result.stdout.count('firecracker') - result.stdout.count('grep')
            checks.append({
                'name': 'Firecracker VMs',
                'status': vm_count > 0,
                'detail': f'{vm_count} 个运行中' if vm_count > 0 else '无运行中的VM'
            })
        except:
            checks.append({
                'name': 'Firecracker VMs',
                'status': False,
                'detail': '无法检查'
            })

        # 打印结果
        for check in checks:
            status_icon = "✅" if check['status'] else "❌"
            status_color = Colors.GREEN if check['status'] else Colors.RED
            print(f"{status_icon} {check['name']:30s} {status_color}{check['detail']}{Colors.END}")

        # 统计
        passed = sum(1 for c in checks if c['status'])
        total = len(checks)
        print(f"\n{Colors.BOLD}检查结果: {passed}/{total} 通过{Colors.END}")

        return passed == total

    def list_demos(self):
        """列出所有可用的演示"""
        self.print_section("可用的演示脚本")

        for demo_id, demo in self.demos.items():
            script_path = self.base_dir / demo['script']
            exists = script_path.exists()

            print(f"{Colors.BOLD}{Colors.CYAN}[{demo_id}] {demo['name']}{Colors.END}")
            print(f"  脚本: {demo['script']}")
            print(f"  状态: {Colors.GREEN}✅ 可用{Colors.END}" if exists else f"{Colors.RED}❌ 未找到{Colors.END}")
            print(f"  描述: {demo['description']}")
            print(f"  预计时间: {demo['duration']}")
            print(f"  需要API: {'是' if demo['requires_api'] else '否'}")
            print(f"  功能特性:")
            for feature in demo['features']:
                print(f"    • {feature}")
            print()

    def show_demo_info(self, demo_id):
        """显示演示详细信息"""
        if demo_id not in self.demos:
            self.print_error(f"未知的演示: {demo_id}")
            self.print_info(f"可用的演示: {', '.join(self.demos.keys())}")
            return

        demo = self.demos[demo_id]
        self.print_section(f"演示详情: {demo['name']}")

        print(f"{Colors.BOLD}基本信息:{Colors.END}")
        print(f"  ID: {demo_id}")
        print(f"  名称: {demo['name']}")
        print(f"  脚本: {demo['script']}")
        print(f"  预计时间: {demo['duration']}")
        print(f"  需要API: {'是' if demo['requires_api'] else '否'}")

        print(f"\n{Colors.BOLD}描述:{Colors.END}")
        print(f"  {demo['description']}")

        print(f"\n{Colors.BOLD}功能特性:{Colors.END}")
        for i, feature in enumerate(demo['features'], 1):
            print(f"  {i}. {feature}")

        script_path = self.base_dir / demo['script']
        print(f"\n{Colors.BOLD}脚本路径:{Colors.END}")
        print(f"  {script_path}")
        print(f"  存在: {Colors.GREEN}是{Colors.END}" if script_path.exists() else f"{Colors.RED}否{Colors.END}")

    def run_demo(self, demo_id, verbose=False):
        """运行指定的演示"""
        if demo_id not in self.demos:
            self.print_error(f"未知的演示: {demo_id}")
            self.print_info(f"可用的演示: {', '.join(self.demos.keys())}")
            return False

        demo = self.demos[demo_id]
        script_path = self.base_dir / demo['script']

        if not script_path.exists():
            self.print_error(f"脚本文件不存在: {script_path}")
            return False

        self.print_section(f"运行演示: {demo['name']}")

        print(f"{Colors.BOLD}准备运行:{Colors.END}")
        print(f"  脚本: {demo['script']}")
        print(f"  预计时间: {demo['duration']}")

        if demo['requires_api']:
            self.print_warning("此演示需要 E2B API 服务运行")

        print(f"\n{Colors.YELLOW}{'='*70}{Colors.END}\n")

        # 运行脚本
        start_time = datetime.now()

        try:
            cmd = [sys.executable, str(script_path)]
            result = subprocess.run(
                cmd,
                cwd=self.base_dir,
                capture_output=not verbose,
                text=True
            )

            end_time = datetime.now()
            duration = (end_time - start_time).total_seconds()

            if verbose and result.stdout:
                print(result.stdout)

            if result.returncode == 0:
                print(f"\n{Colors.YELLOW}{'='*70}{Colors.END}\n")
                self.print_success(f"演示完成! 耗时: {duration:.1f} 秒")
                return True
            else:
                print(f"\n{Colors.YELLOW}{'='*70}{Colors.END}\n")
                self.print_error(f"演示失败 (退出码: {result.returncode})")
                if result.stderr:
                    print(f"\n{Colors.RED}错误信息:{Colors.END}")
                    print(result.stderr)
                return False

        except KeyboardInterrupt:
            print(f"\n\n{Colors.YELLOW}演示被用户中断{Colors.END}")
            return False
        except Exception as e:
            self.print_error(f"运行出错: {str(e)}")
            return False

    def show_status(self):
        """显示系统状态"""
        self.print_section("E2B 系统状态")

        # API 状态
        print(f"{Colors.BOLD}服务状态:{Colors.END}")
        try:
            result = subprocess.run(['curl', '-s', 'http://localhost:3000/health'],
                                  capture_output=True, text=True, timeout=3)
            if 'Health check successful' in result.stdout:
                print(f"  API (Port 3000):        {Colors.GREEN}✅ 运行中{Colors.END}")
            else:
                print(f"  API (Port 3000):        {Colors.RED}❌ 异常{Colors.END}")
        except:
            print(f"  API (Port 3000):        {Colors.RED}❌ 未运行{Colors.END}")

        try:
            result = subprocess.run(['curl', '-s', 'http://localhost:5008/health'],
                                  capture_output=True, text=True, timeout=3)
            if 'healthy' in result.stdout:
                print(f"  Orchestrator (Port 5008): {Colors.GREEN}✅ 运行中{Colors.END}")
            else:
                print(f"  Orchestrator (Port 5008): {Colors.RED}❌ 异常{Colors.END}")
        except:
            print(f"  Orchestrator (Port 5008): {Colors.RED}❌ 未运行{Colors.END}")

        # Firecracker VMs
        print(f"\n{Colors.BOLD}Firecracker VMs:{Colors.END}")
        try:
            result = subprocess.run(['ps', 'aux'], capture_output=True, text=True)
            lines = [line for line in result.stdout.split('\n') if 'firecracker' in line and 'grep' not in line]

            if lines:
                print(f"  运行中的 VM: {Colors.GREEN}{len(lines)} 个{Colors.END}")
                for i, line in enumerate(lines[:5], 1):  # 最多显示5个
                    parts = line.split()
                    if len(parts) >= 11:
                        pid = parts[1]
                        cpu = parts[2]
                        mem = parts[3]
                        print(f"    {i}. PID {pid} - CPU: {cpu}% MEM: {mem}%")
            else:
                print(f"  运行中的 VM: {Colors.YELLOW}0 个{Colors.END}")
        except Exception as e:
            print(f"  {Colors.RED}无法获取 VM 信息{Colors.END}")

        # 网络命名空间
        print(f"\n{Colors.BOLD}网络隔离:{Colors.END}")
        try:
            result = subprocess.run(['sudo', 'ip', 'netns', 'list'],
                                  capture_output=True, text=True, timeout=3)
            if result.returncode == 0:
                ns_count = len([line for line in result.stdout.split('\n') if line.strip()])
                print(f"  网络命名空间: {Colors.GREEN}{ns_count} 个{Colors.END}")
        except:
            print(f"  网络命名空间: {Colors.YELLOW}无法检查{Colors.END}")

        # Nomad 作业
        print(f"\n{Colors.BOLD}Nomad 作业:{Colors.END}")
        try:
            result = subprocess.run(['nomad', 'job', 'status'],
                                  capture_output=True, text=True, timeout=3)
            if result.returncode == 0:
                lines = result.stdout.split('\n')
                for line in lines[1:]:  # 跳过标题行
                    if 'running' in line.lower() and line.strip():
                        parts = line.split()
                        if len(parts) >= 3:
                            print(f"  {parts[0]:15s} {Colors.GREEN}✅ {parts[2]}{Colors.END}")
        except:
            print(f"  {Colors.YELLOW}无法获取 Nomad 状态{Colors.END}")

    def bridge_start(self):
        """启动 socat 网络桥接"""
        self.print_section("启动网络桥接")

        if not self.bridge_manager_script.exists():
            self.print_error(f"桥接管理脚本不存在: {self.bridge_manager_script}")
            return False

        try:
            result = subprocess.run(
                [str(self.bridge_manager_script), 'start'],
                capture_output=True,
                text=True,
                timeout=10
            )

            print(result.stdout)

            if result.returncode == 0:
                self.print_success("网络桥接启动成功")
                return True
            else:
                self.print_error("网络桥接启动失败")
                if result.stderr:
                    print(result.stderr)
                return False

        except Exception as e:
            self.print_error(f"启动网络桥接出错: {str(e)}")
            return False

    def bridge_stop(self):
        """停止 socat 网络桥接"""
        self.print_section("停止网络桥接")

        if not self.bridge_manager_script.exists():
            self.print_error(f"桥接管理脚本不存在: {self.bridge_manager_script}")
            return False

        try:
            result = subprocess.run(
                [str(self.bridge_manager_script), 'stop'],
                capture_output=True,
                text=True,
                timeout=10
            )

            print(result.stdout)

            if result.returncode == 0:
                self.print_success("网络桥接已停止")
                return True
            else:
                self.print_error("停止网络桥接失败")
                if result.stderr:
                    print(result.stderr)
                return False

        except Exception as e:
            self.print_error(f"停止网络桥接出错: {str(e)}")
            return False

    def bridge_restart(self):
        """重启 socat 网络桥接"""
        self.print_section("重启网络桥接")

        if not self.bridge_manager_script.exists():
            self.print_error(f"桥接管理脚本不存在: {self.bridge_manager_script}")
            return False

        try:
            result = subprocess.run(
                [str(self.bridge_manager_script), 'restart'],
                capture_output=True,
                text=True,
                timeout=10
            )

            print(result.stdout)

            if result.returncode == 0:
                self.print_success("网络桥接重启成功")
                return True
            else:
                self.print_error("重启网络桥接失败")
                if result.stderr:
                    print(result.stderr)
                return False

        except Exception as e:
            self.print_error(f"重启网络桥接出错: {str(e)}")
            return False

    def bridge_status(self):
        """检查 socat 网络桥接状态"""
        self.print_section("网络桥接状态")

        if not self.bridge_manager_script.exists():
            self.print_error(f"桥接管理脚本不存在: {self.bridge_manager_script}")
            return False

        try:
            result = subprocess.run(
                [str(self.bridge_manager_script), 'status'],
                capture_output=True,
                text=True,
                timeout=10
            )

            print(result.stdout)

            # 返回值为0表示正在运行，1表示未运行
            return result.returncode == 0

        except Exception as e:
            self.print_error(f"检查网络桥接状态出错: {str(e)}")
            return False

    def bridge_test(self):
        """测试 socat 网络桥接连通性"""
        self.print_section("测试网络桥接")

        if not self.bridge_manager_script.exists():
            self.print_error(f"桥接管理脚本不存在: {self.bridge_manager_script}")
            return False

        try:
            result = subprocess.run(
                [str(self.bridge_manager_script), 'test'],
                capture_output=True,
                text=True,
                timeout=10
            )

            print(result.stdout)

            if result.returncode == 0:
                self.print_success("网络桥接连通性测试通过")
                return True
            else:
                self.print_warning("网络桥接连通性测试失败")
                if result.stderr:
                    print(result.stderr)
                return False

        except Exception as e:
            self.print_error(f"测试网络桥接出错: {str(e)}")
            return False

    def bridge_daemon(self):
        """以守护进程模式运行网络桥接（自动监控和重启）"""
        self.print_section("启动网络桥接守护进程")

        if not self.bridge_manager_script.exists():
            self.print_error(f"桥接管理脚本不存在: {self.bridge_manager_script}")
            return False

        self.print_info("守护进程将持续监控网络桥接状态并自动重启")
        self.print_warning("按 Ctrl+C 停止守护进程")
        print()

        try:
            result = subprocess.run(
                [str(self.bridge_manager_script), 'daemon'],
                timeout=None  # 无超时限制
            )

            return result.returncode == 0

        except KeyboardInterrupt:
            print(f"\n{Colors.YELLOW}守护进程被用户中断{Colors.END}")
            return True
        except Exception as e:
            self.print_error(f"运行守护进程出错: {str(e)}")
            return False

    def show_help(self):
        """显示帮助信息"""
        help_text = f"""
{Colors.BOLD}E2B Infrastructure CLI Tool - 使用指南{Colors.END}

{Colors.BOLD}命令列表:{Colors.END}

  {Colors.CYAN}list{Colors.END}
    列出所有可用的演示脚本
    示例: ./infra_cli.py list

  {Colors.CYAN}info <demo_id>{Colors.END}
    显示指定演示的详细信息
    示例: ./infra_cli.py info sdk

  {Colors.CYAN}run <demo_id> [--verbose]{Colors.END}
    运行指定的演示
    选项:
      --verbose, -v   显示详细输出
    示例:
      ./infra_cli.py run sdk
      ./infra_cli.py run existing -v

  {Colors.CYAN}status{Colors.END}
    查看 E2B 系统状态
    示例: ./infra_cli.py status

  {Colors.CYAN}check{Colors.END}
    检查系统先决条件
    示例: ./infra_cli.py check

  {Colors.CYAN}bridge <action>{Colors.END}
    管理 Socat 网络桥接
    动作:
      start    - 启动网络桥接
      stop     - 停止网络桥接
      restart  - 重启网络桥接
      status   - 查看桥接状态
      test     - 测试桥接连通性
      daemon   - 守护进程模式（自动监控和重启）
    示例:
      ./infra_cli.py bridge start
      ./infra_cli.py bridge status
      ./infra_cli.py bridge test

  {Colors.CYAN}help{Colors.END}
    显示此帮助信息
    示例: ./infra_cli.py help

{Colors.BOLD}可用的演示 ID:{Colors.END}
  sdk       - SDK 完整演示 (创建新 VM)
  existing  - 现有 VM 演示 (连接已运行的 VM)

{Colors.BOLD}网络桥接说明:{Colors.END}
  Socat 桥接用于将 Firecracker VM 内部的 envd 服务暴露到主机网络
  端口映射: 主机 :49983 -> VM 内部 169.254.0.21:49983

  注意: Orchestrator 有内置网络桥接，通常不需要独立的 socat 进程

{Colors.BOLD}快速开始:{Colors.END}
  1. 检查系统状态:    ./infra_cli.py status
  2. 检查网络桥接:    ./infra_cli.py bridge status
  3. 列出可用演示:    ./infra_cli.py list
  4. 运行演示:        ./infra_cli.py run existing

{Colors.BOLD}环境变量:{Colors.END}
  E2B_API_KEY    E2B API 密钥
  E2B_API_URL    E2B API 地址 (默认: http://localhost:3000)

{Colors.BOLD}更多信息:{Colors.END}
  文档: /home/primihub/pcloud/E2B_COMPLETE_DEMO_REPORT.md
  GitHub: https://github.com/e2b-dev/infra
"""
        print(help_text)


def main():
    """主函数"""
    cli = InfraCLI()

    # 解析命令行参数
    parser = argparse.ArgumentParser(
        description='E2B Infrastructure CLI Tool',
        add_help=False
    )
    parser.add_argument('command', nargs='?', default='help',
                       choices=['list', 'info', 'run', 'status', 'check', 'bridge', 'help'],
                       help='命令')
    parser.add_argument('subcommand', nargs='?', help='子命令 (用于 bridge 等命令)')
    parser.add_argument('-v', '--verbose', action='store_true', help='详细输出')
    parser.add_argument('--no-banner', action='store_true', help='不显示横幅')

    args = parser.parse_args()

    # 显示横幅
    if not args.no_banner:
        cli.print_banner()

    # 执行命令
    try:
        if args.command == 'list':
            cli.list_demos()

        elif args.command == 'info':
            if not args.subcommand:
                cli.print_error("请指定演示 ID")
                cli.print_info(f"使用方法: {sys.argv[0]} info <demo_id>")
                cli.print_info(f"可用的演示: {', '.join(cli.demos.keys())}")
                sys.exit(1)
            cli.show_demo_info(args.subcommand)

        elif args.command == 'run':
            if not args.subcommand:
                cli.print_error("请指定演示 ID")
                cli.print_info(f"使用方法: {sys.argv[0]} run <demo_id>")
                cli.print_info(f"可用的演示: {', '.join(cli.demos.keys())}")
                sys.exit(1)
            success = cli.run_demo(args.subcommand, verbose=args.verbose)
            sys.exit(0 if success else 1)

        elif args.command == 'status':
            cli.show_status()

        elif args.command == 'check':
            all_passed = cli.check_prerequisites()
            sys.exit(0 if all_passed else 1)

        elif args.command == 'bridge':
            if not args.subcommand:
                cli.print_error("请指定桥接动作")
                cli.print_info(f"使用方法: {sys.argv[0]} bridge <action>")
                cli.print_info("可用的动作: start, stop, restart, status, test, daemon")
                sys.exit(1)

            action = args.subcommand.lower()
            if action == 'start':
                success = cli.bridge_start()
            elif action == 'stop':
                success = cli.bridge_stop()
            elif action == 'restart':
                success = cli.bridge_restart()
            elif action == 'status':
                success = cli.bridge_status()
            elif action == 'test':
                success = cli.bridge_test()
            elif action == 'daemon':
                success = cli.bridge_daemon()
            else:
                cli.print_error(f"未知的桥接动作: {action}")
                cli.print_info("可用的动作: start, stop, restart, status, test, daemon")
                sys.exit(1)

            sys.exit(0 if success else 1)

        elif args.command == 'help':
            cli.show_help()

        else:
            cli.show_help()

    except KeyboardInterrupt:
        print(f"\n\n{Colors.YELLOW}操作被用户中断{Colors.END}")
        sys.exit(130)
    except Exception as e:
        cli.print_error(f"发生错误: {str(e)}")
        if args.verbose:
            import traceback
            traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
