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
PCLOUD_HOME="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# 加载环境变量配置
if [ -f "$PCLOUD_HOME/config/env.sh" ]; then
    source "$PCLOUD_HOME/config/env.sh"
fi

# 设置默认值
PCLOUD_HOME="${PCLOUD_HOME:-/home/primihub/pcloud}"
E2B_STORAGE_PATH="${E2B_STORAGE_PATH:-$PCLOUD_HOME/../e2b-storage}"

echo ""
echo "=========================================="
echo -e "${BOLD}E2B 依赖检查工具${NC}"
echo "=========================================="
echo ""

# 检查结果统计
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0

# 检查函数
check_command() {
    local cmd=$1
    local name=$2
    local install_hint=$3

    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))

    if command -v "$cmd" &> /dev/null; then
        local version=$($cmd --version 2>&1 | head -n1 || echo "unknown")
        echo -e "${GREEN}✓${NC} $name: ${GREEN}已安装${NC}"
        echo "  版本: $version"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
        return 0
    else
        echo -e "${RED}✗${NC} $name: ${RED}未安装${NC}"
        if [ -n "$install_hint" ]; then
            echo -e "  ${YELLOW}安装提示:${NC} $install_hint"
        fi
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
        return 1
    fi
}

check_service() {
    local service=$1
    local name=$2

    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))

    if pgrep -x "$service" > /dev/null; then
        echo -e "${GREEN}✓${NC} $name: ${GREEN}运行中${NC}"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
        return 0
    else
        echo -e "${YELLOW}⚠${NC} $name: ${YELLOW}未运行${NC}"
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
        return 1
    fi
}

check_port() {
    local port=$1
    local name=$2

    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))

    if netstat -tuln 2>/dev/null | grep -q ":$port " || ss -tuln 2>/dev/null | grep -q ":$port "; then
        echo -e "${GREEN}✓${NC} $name (端口 $port): ${GREEN}监听中${NC}"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
        return 0
    else
        echo -e "${YELLOW}⚠${NC} $name (端口 $port): ${YELLOW}未监听${NC}"
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
        return 1
    fi
}

check_directory() {
    local dir=$1
    local name=$2

    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))

    if [ -d "$dir" ]; then
        echo -e "${GREEN}✓${NC} $name: ${GREEN}存在${NC}"
        echo "  路径: $dir"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
        return 0
    else
        echo -e "${RED}✗${NC} $name: ${RED}不存在${NC}"
        echo "  路径: $dir"
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
        return 1
    fi
}

# 1. 检查系统工具
echo ""
echo "=========================================="
echo -e "${BLUE}[1/7]${NC} 检查系统工具"
echo "=========================================="
echo ""

check_command "docker" "Docker" "curl -fsSL https://get.docker.com | sh"
check_command "docker-compose" "Docker Compose" "sudo apt install docker-compose"
check_command "git" "Git" "sudo apt install git"
check_command "curl" "cURL" "sudo apt install curl"
check_command "jq" "jq" "sudo apt install jq"

# 2. 检查 Consul 和 Nomad
echo ""
echo "=========================================="
echo -e "${BLUE}[2/7]${NC} 检查 Consul 和 Nomad"
echo "=========================================="
echo ""

check_command "consul" "Consul" "bash $SCRIPT_DIR/08-install-nomad-consul.sh"
check_command "nomad" "Nomad" "bash $SCRIPT_DIR/08-install-nomad-consul.sh"

# 3. 检查 Node.js 和 npm
echo ""
echo "=========================================="
echo -e "${BLUE}[3/7]${NC} 检查 Node.js 环境"
echo "=========================================="
echo ""

check_command "node" "Node.js" "curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash - && sudo apt install -y nodejs"
check_command "npm" "npm" "sudo apt install npm"
check_command "pnpm" "pnpm" "npm install -g pnpm"

# 4. 检查 Go 环境
echo ""
echo "=========================================="
echo -e "${BLUE}[4/7]${NC} 检查 Go 环境"
echo "=========================================="
echo ""

check_command "go" "Go" "wget https://go.dev/dl/go1.21.0.linux-amd64.tar.gz && sudo tar -C /usr/local -xzf go1.21.0.linux-amd64.tar.gz"

# 5. 检查运行中的服务
echo ""
echo "=========================================="
echo -e "${BLUE}[5/7]${NC} 检查运行中的服务"
echo "=========================================="
echo ""

check_service "consul" "Consul"
check_service "nomad" "Nomad"
check_service "dockerd" "Docker Daemon"

# 6. 检查端口占用
echo ""
echo "=========================================="
echo -e "${BLUE}[6/7]${NC} 检查端口占用"
echo "=========================================="
echo ""

check_port "8500" "Consul UI"
check_port "4646" "Nomad UI"
check_port "3000" "API 服务"
check_port "3001" "Fragments"
check_port "3003" "Surf"
check_port "5432" "PostgreSQL"
check_port "6379" "Redis"
check_port "9000" "ClickHouse"

# 7. 检查目录结构
echo ""
echo "=========================================="
echo -e "${BLUE}[7/7]${NC} 检查目录结构"
echo "=========================================="
echo ""

check_directory "$PCLOUD_HOME" "PCloud 根目录"
check_directory "$E2B_STORAGE_PATH" "E2B 存储目录"
check_directory "$E2B_STORAGE_PATH/logs" "日志目录"
check_directory "$PCLOUD_HOME/infra/fragments" "Fragments 应用"
check_directory "$PCLOUD_HOME/infra/surf" "Surf 应用"
check_directory "$PCLOUD_HOME/infra/packages" "Go 包目录"

# 检查前端应用依赖
echo ""
TOTAL_CHECKS=$((TOTAL_CHECKS + 2))
if [ -d "$PCLOUD_HOME/infra/fragments/node_modules" ]; then
    echo -e "${GREEN}✓${NC} Fragments 依赖: ${GREEN}已安装${NC}"
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
else
    echo -e "${YELLOW}⚠${NC} Fragments 依赖: ${YELLOW}未安装${NC}"
    echo -e "  ${YELLOW}提示:${NC} cd $PCLOUD_HOME/infra/fragments && pnpm install"
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
fi

if [ -d "$PCLOUD_HOME/infra/surf/node_modules" ]; then
    echo -e "${GREEN}✓${NC} Surf 依赖: ${GREEN}已安装${NC}"
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
else
    echo -e "${YELLOW}⚠${NC} Surf 依赖: ${YELLOW}未安装${NC}"
    echo -e "  ${YELLOW}提示:${NC} cd $PCLOUD_HOME/infra/surf && pnpm install"
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
fi

# 显示检查结果
echo ""
echo "=========================================="
echo -e "${BOLD}检查结果汇总${NC}"
echo "=========================================="
echo ""
echo "总检查项: $TOTAL_CHECKS"
echo -e "通过: ${GREEN}$PASSED_CHECKS${NC}"
echo -e "失败: ${RED}$FAILED_CHECKS${NC}"
echo ""

# 计算通过率
PASS_RATE=$((PASSED_CHECKS * 100 / TOTAL_CHECKS))

if [ $PASS_RATE -eq 100 ]; then
    echo -e "${GREEN}${BOLD}✓ 所有检查通过！系统已就绪${NC}"
    echo ""
    exit 0
elif [ $PASS_RATE -ge 80 ]; then
    echo -e "${YELLOW}${BOLD}⚠ 大部分检查通过 ($PASS_RATE%)${NC}"
    echo ""
    echo "建议修复失败的检查项以确保系统正常运行"
    echo ""
    exit 0
else
    echo -e "${RED}${BOLD}✗ 检查失败较多 ($PASS_RATE%)${NC}"
    echo ""
    echo "请修复失败的检查项后再启动系统"
    echo ""
    exit 1
fi
