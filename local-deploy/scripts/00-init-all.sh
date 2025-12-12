#!/bin/bash
set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# 脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo ""
echo "=========================================="
echo -e "${BOLD}E2B 本地部署 - 总初始化脚本${NC}"
echo "=========================================="
echo ""
echo "此脚本将完整初始化 E2B 本地部署环境"
echo ""
echo "执行步骤:"
echo "  1. 检查系统要求"
echo "  2. 安装依赖软件"
echo "  3. 配置内核模块"
echo "  4. 配置 Sudo 权限"
echo "  5. 创建存储目录"
echo "  6. 构建 Go 二进制"
echo "  7. 构建 Docker 镜像"
echo "  8. 安装 Nomad & Consul"
echo "  9. 初始化数据库"
echo ""
echo -e "${YELLOW}⚠ 注意:${NC}"
echo "  - 此过程可能需要 30-60 分钟"
echo "  - 步骤 2-4 需要 sudo 权限"
echo "  - 确保网络连接正常（需下载大量软件包）"
echo "  - 建议在开始前关闭其他占用资源的程序"
echo ""

# 询问是否继续
read -p "是否继续? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "已取消"
    exit 0
fi

echo ""

# 记录开始时间
START_TIME=$(date +%s)

# 脚本执行函数
run_script() {
    local script_num=$1
    local script_name=$2
    local need_sudo=$3

    echo ""
    echo "=========================================="
    echo -e "${BLUE}步骤 $script_num: $script_name${NC}"
    echo "=========================================="
    echo ""

    local script_file="$SCRIPT_DIR/${script_num}-${script_name}.sh"

    if [ ! -f "$script_file" ]; then
        echo -e "${RED}✗${NC} 脚本不存在: $script_file"
        exit 1
    fi

    # 确保脚本可执行
    chmod +x "$script_file"

    # 执行脚本
    local step_start=$(date +%s)

    if [ "$need_sudo" = "sudo" ]; then
        if sudo bash "$script_file"; then
            local step_end=$(date +%s)
            local step_time=$((step_end - step_start))
            echo -e "${GREEN}✓ 步骤 $script_num 完成${NC} (耗时: ${step_time}s)"
        else
            echo -e "${RED}✗ 步骤 $script_num 失败${NC}"
            echo ""
            echo "初始化失败，请检查错误信息"
            exit 1
        fi
    else
        if bash "$script_file"; then
            local step_end=$(date +%s)
            local step_time=$((step_end - step_start))
            echo -e "${GREEN}✓ 步骤 $script_num 完成${NC} (耗时: ${step_time}s)"
        else
            echo -e "${RED}✗ 步骤 $script_num 失败${NC}"
            echo ""
            echo "初始化失败，请检查错误信息"
            exit 1
        fi
    fi
}

# 执行所有初始化脚本
echo ""
echo "开始初始化..."
echo ""

# 步骤 1: 检查系统要求
run_script "01" "check-requirements" "no-sudo"

# 步骤 2: 安装依赖
echo ""
read -p "步骤 2 需要 sudo 权限安装软件，是否继续? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo -e "${YELLOW}⚠${NC} 跳过步骤 2，请手动运行: sudo bash $SCRIPT_DIR/02-install-deps.sh"
    echo "然后重新运行此脚本"
    exit 0
fi
run_script "02" "install-deps" "sudo"

# 提示重新登录（如果需要）
echo ""
echo -e "${YELLOW}⚠ 重要提示:${NC}"
echo "如果您是首次运行此脚本，步骤 2 已将您添加到 docker 和 kvm 组"
echo "这些组权限需要重新登录才能生效"
echo ""
read -p "是否已经重新登录或确认组权限已生效? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo "请重新登录后运行此脚本"
    echo "或手动验证: groups | grep -E 'docker|kvm'"
    exit 0
fi

# 步骤 3: 配置内核
run_script "03" "setup-kernel" "sudo"

# 步骤 4: 配置 Sudo
run_script "04" "setup-sudo" "sudo"

# 步骤 5: 创建存储目录
run_script "05" "setup-storage" "sudo"

# 步骤 6: 构建 Go 二进制
echo ""
echo -e "${BLUE}步骤 6 将构建 Go 二进制文件，这可能需要 10-20 分钟${NC}"
read -p "是否继续? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "已跳过步骤 6"
    echo "手动运行: bash $SCRIPT_DIR/06-build-binaries.sh"
else
    run_script "06" "build-binaries" "no-sudo"
fi

# 步骤 7: 构建 Docker 镜像
echo ""
echo -e "${BLUE}步骤 7 将构建 Docker 镜像，这可能需要 10-20 分钟${NC}"
read -p "是否继续? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "已跳过步骤 7"
    echo "手动运行: bash $SCRIPT_DIR/07-build-images.sh"
else
    run_script "07" "build-images" "no-sudo"
fi

# 步骤 8: 安装 Nomad & Consul
run_script "08" "install-nomad-consul" "sudo"

# 步骤 9: 初始化数据库
echo ""
echo -e "${BLUE}步骤 9 将启动基础设施服务并初始化数据库${NC}"
read -p "是否继续? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "已跳过步骤 9"
    echo "手动运行: bash $SCRIPT_DIR/09-init-database.sh"
else
    run_script "09" "init-database" "no-sudo"
fi

# 计算总耗时
END_TIME=$(date +%s)
TOTAL_TIME=$((END_TIME - START_TIME))
MINUTES=$((TOTAL_TIME / 60))
SECONDS=$((TOTAL_TIME % 60))

# 总结
echo ""
echo "=========================================="
echo -e "${GREEN}${BOLD}✓ 初始化完成！${NC}"
echo "=========================================="
echo ""
echo "总耗时: ${MINUTES}分${SECONDS}秒"
echo ""

echo "已完成的配置:"
echo -e "  ${GREEN}✓${NC} 系统要求检查"
echo -e "  ${GREEN}✓${NC} 依赖软件安装"
echo -e "  ${GREEN}✓${NC} 内核模块配置"
echo -e "  ${GREEN}✓${NC} Sudo 权限配置"
echo -e "  ${GREEN}✓${NC} 存储目录创建"
echo -e "  ${GREEN}✓${NC} Go 二进制构建"
echo -e "  ${GREEN}✓${NC} Docker 镜像构建"
echo -e "  ${GREEN}✓${NC} Nomad & Consul 安装"
echo -e "  ${GREEN}✓${NC} 数据库初始化"
echo ""

echo "下一步："
echo ""
echo "1. 启动所有服务:"
echo "   bash $SCRIPT_DIR/start-all.sh"
echo ""
echo "2. 或分步启动:"
echo "   bash $SCRIPT_DIR/start-infra.sh       # 启动基础设施"
echo "   bash $SCRIPT_DIR/start-consul.sh      # 启动 Consul"
echo "   bash $SCRIPT_DIR/start-nomad.sh       # 启动 Nomad"
echo "   bash $SCRIPT_DIR/deploy-all-jobs.sh   # 部署 Jobs"
echo ""
echo "3. 验证部署:"
echo "   bash $SCRIPT_DIR/verify-deployment.sh"
echo ""
echo "4. 访问服务:"
echo "   Nginx:     http://localhost:80"
echo "   API:       http://localhost:3000"
echo "   Grafana:   http://localhost:53000"
echo "   Nomad UI:  http://localhost:4646"
echo "   Consul UI: http://localhost:8500"
echo ""

echo "快捷访问目录:"
if [ -n "$SUDO_USER" ]; then
    echo "   ~/e2b-storage"
else
    echo "   $HOME/e2b-storage"
fi
echo ""

echo "文档和帮助:"
echo "   README: $PROJECT_ROOT/local-deploy/README.md"
echo ""

echo -e "${GREEN}🎉 E2B 本地部署环境已就绪！${NC}"
echo ""
