#!/bin/bash
# E2B快速启动脚本

set -e

echo "=========================================="
echo "E2B快速启动"
echo "=========================================="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
E2B_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_ROOT="$(dirname "$(dirname "$E2B_DIR")")"

cd "$E2B_DIR"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

show_menu() {
    echo ""
    echo "请选择部署选项:"
    echo "1. 检查系统要求"
    echo "2. 启动E2B服务 (简化版)"
    echo "3. 创建测试VM (Docker容器)"
    echo "4. 查看文档"
    echo "5. 退出"
    echo ""
    read -p "请输入选项 [1-5]: " choice
}

check_requirements() {
    echo ""
    echo "检查系统要求..."
    bash "$SCRIPT_DIR/check_e2b_requirements.sh"
}

start_e2b_service() {
    echo ""
    echo "启动E2B服务..."
    
    # 检查Docker
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}错误: Docker未安装${NC}"
        return 1
    fi
    
    # 检查Docker服务
    if ! systemctl is-active --quiet docker; then
        echo "启动Docker服务..."
        sudo systemctl start docker
    fi
    
    # 启动E2B服务
    echo "启动E2B基础设施..."
    bash "$SCRIPT_DIR/start_e2b_service.sh"
}

create_test_vm() {
    echo ""
    echo "创建测试VM..."
    
    # 检查是否有可用的创建脚本
    if [ -f "$PROJECT_ROOT/create_simple_vm.sh" ]; then
        bash "$PROJECT_ROOT/create_simple_vm.sh"
    else
        echo -e "${YELLOW}警告: 未找到create_simple_vm.sh脚本${NC}"
        echo "使用Docker直接创建测试容器..."
        
        VM_NAME="e2b-test-vm-$(date +%s)"
        echo "创建测试容器: $VM_NAME"
        
        docker run -d \
            --name "$VM_NAME" \
            --hostname "$VM_NAME" \
            ubuntu:22.04 \
            sleep infinity
        
        echo -e "${GREEN}✓ 测试VM创建成功${NC}"
        echo "名称: $VM_NAME"
        echo "容器ID: $(docker ps -q -f name=$VM_NAME)"
        echo ""
        echo "管理命令:"
        echo "  进入VM: docker exec -it $VM_NAME bash"
        echo "  停止VM: docker stop $VM_NAME"
        echo "  删除VM: docker rm -f $VM_NAME"
    fi
}

show_docs() {
    echo ""
    echo "E2B文档:"
    echo "1. 完整部署指南: $E2B_DIR/docs/e2b_complete_deployment_guide.md"
    echo "2. 升级指南: $E2B_DIR/docs/upgrade_for_e2b_deployment.md"
    echo "3. README: $E2B_DIR/README.md"
    echo ""
    echo "示例代码:"
    echo "  $E2B_DIR/examples/"
    echo ""
    echo "相关文件:"
    echo "  - 配置: $E2B_DIR/config/"
    echo "  - 脚本: $E2B_DIR/scripts/"
}

main() {
    echo "E2B目录: $E2B_DIR"
    echo "项目根目录: $PROJECT_ROOT"
    echo ""
    
    while true; do
        show_menu
        
        case $choice in
            1)
                check_requirements
                ;;
            2)
                start_e2b_service
                ;;
            3)
                create_test_vm
                ;;
            4)
                show_docs
                ;;
            5)
                echo "退出"
                exit 0
                ;;
            *)
                echo -e "${RED}无效选项${NC}"
                ;;
        esac
        
        echo ""
        echo "按Enter继续..."
        read
    done
}

# 检查是否以交互模式运行
if [[ $- == *i* ]]; then
    main
else
    # 非交互模式，显示帮助
    echo "E2B快速启动脚本"
    echo ""
    echo "用法:"
    echo "  $0                 # 交互模式"
    echo "  $0 check          # 检查系统要求"
    echo "  $0 start          # 启动E2B服务"
    echo "  $0 create-vm      # 创建测试VM"
    echo "  $0 docs           # 显示文档"
    echo ""
    
    # 处理命令行参数
    case "$1" in
        check)
            check_requirements
            ;;
        start)
            start_e2b_service
            ;;
        create-vm)
            create_test_vm
            ;;
        docs)
            show_docs
            ;;
        *)
            echo "未知命令: $1"
            exit 1
            ;;
    esac
fi