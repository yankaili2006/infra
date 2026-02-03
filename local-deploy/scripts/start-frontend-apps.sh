#!/bin/bash
# 前端应用启动脚本 - 自动检查和安装依赖
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

# 加载环境变量
if [ -f "$PCLOUD_HOME/config/env.sh" ]; then
    source "$PCLOUD_HOME/config/env.sh"
fi

# 设置默认值
E2B_STORAGE_PATH="${E2B_STORAGE_PATH:-$PCLOUD_HOME/../e2b-storage}"
LOG_DIR="$E2B_STORAGE_PATH/logs"

# 应用配置
FRAGMENTS_DIR="$PCLOUD_HOME/infra/fragments"
SURF_DIR="$PCLOUD_HOME/infra/surf"

echo ""
echo "=========================================="
echo -e "${BOLD}E2B 前端应用启动脚本${NC}"
echo "=========================================="
echo ""

# 创建日志目录
mkdir -p "$LOG_DIR"

# 检查 Node.js 和 npm
check_nodejs() {
    echo -e "${BLUE}[1/5]${NC} 检查 Node.js 环境..."

    if ! command -v node &> /dev/null; then
        echo -e "${RED}✗${NC} Node.js 未安装"
        echo "请安装 Node.js: https://nodejs.org/"
        exit 1
    fi

    if ! command -v npm &> /dev/null; then
        echo -e "${RED}✗${NC} npm 未安装"
        exit 1
    fi

    NODE_VERSION=$(node --version)
    NPM_VERSION=$(npm --version)
    echo -e "${GREEN}✓${NC} Node.js $NODE_VERSION"
    echo -e "${GREEN}✓${NC} npm $NPM_VERSION"
    echo ""
}

# 检查并安装依赖
check_and_install_deps() {
    local app_name=$1
    local app_dir=$2

    echo -e "${BLUE}检查 $app_name 依赖...${NC}"

    if [ ! -d "$app_dir" ]; then
        echo -e "${RED}✗${NC} 目录不存在: $app_dir"
        return 1
    fi

    cd "$app_dir"

    # 检查 package.json 是否存在
    if [ ! -f "package.json" ]; then
        echo -e "${RED}✗${NC} package.json 不存在"
        return 1
    fi

    # 检查 node_modules 是否存在
    if [ ! -d "node_modules" ]; then
        echo -e "${YELLOW}⚠${NC} node_modules 不存在，开始安装依赖..."
        npm install
        echo -e "${GREEN}✓${NC} 依赖安装完成"
        return 0
    fi

    # 检查 package.json 是否比 node_modules 新
    if [ "package.json" -nt "node_modules" ]; then
        echo -e "${YELLOW}⚠${NC} package.json 已更新，重新安装依赖..."
        npm install
        echo -e "${GREEN}✓${NC} 依赖更新完成"
        return 0
    fi

    # 检查 package-lock.json 是否比 node_modules 新
    if [ -f "package-lock.json" ] && [ "package-lock.json" -nt "node_modules" ]; then
        echo -e "${YELLOW}⚠${NC} package-lock.json 已更新，重新安装依赖..."
        npm install
        echo -e "${GREEN}✓${NC} 依赖更新完成"
        return 0
    fi

    echo -e "${GREEN}✓${NC} 依赖已是最新"
}

# 停止已运行的应用
stop_existing_apps() {
    echo -e "${BLUE}[2/5]${NC} 检查并停止已运行的应用..."

    # 查找并停止 Fragments
    FRAGMENTS_PID=$(pgrep -f "next dev.*fragments" || true)
    if [ -n "$FRAGMENTS_PID" ]; then
        echo -e "${YELLOW}⚠${NC} 停止已运行的 Fragments (PID: $FRAGMENTS_PID)"
        kill $FRAGMENTS_PID 2>/dev/null || true
        sleep 2
    fi

    # 查找并停止 Surf
    SURF_PID=$(pgrep -f "next dev.*surf" || true)
    if [ -n "$SURF_PID" ]; then
        echo -e "${YELLOW}⚠${NC} 停止已运行的 Surf (PID: $SURF_PID)"
        kill $SURF_PID 2>/dev/null || true
        sleep 2
    fi

    echo -e "${GREEN}✓${NC} 清理完成"
    echo ""
}

# 安装依赖
install_dependencies() {
    echo -e "${BLUE}[3/5]${NC} 检查和安装依赖..."
    echo ""

    # Fragments
    check_and_install_deps "Fragments" "$FRAGMENTS_DIR"
    echo ""

    # Surf
    check_and_install_deps "Surf" "$SURF_DIR"
    echo ""
}

# 启动应用
start_apps() {
    echo -e "${BLUE}[4/5]${NC} 启动应用..."
    echo ""

    # 启动 Fragments
    echo -e "启动 Fragments..."
    cd "$FRAGMENTS_DIR"
    nohup npm run dev > "$LOG_DIR/fragments.log" 2>&1 &
    FRAGMENTS_PID=$!
    echo -e "${GREEN}✓${NC} Fragments 已启动 (PID: $FRAGMENTS_PID)"

    # 启动 Surf
    echo -e "启动 Surf..."
    cd "$SURF_DIR"
    nohup npm run dev > "$LOG_DIR/surf.log" 2>&1 &
    SURF_PID=$!
    echo -e "${GREEN}✓${NC} Surf 已启动 (PID: $SURF_PID)"

    echo ""
}

# 健康检查
health_check() {
    echo -e "${BLUE}[5/5]${NC} 健康检查..."
    echo ""

    echo "等待应用启动..."
    sleep 5

    # 检查 Fragments
    echo -n "Fragments: "
    if curl -s http://localhost:3001 > /dev/null 2>&1; then
        echo -e "${GREEN}✓ 运行中${NC} (http://localhost:3001)"
    else
        # 尝试 3002 端口
        if curl -s http://localhost:3002 > /dev/null 2>&1; then
            echo -e "${GREEN}✓ 运行中${NC} (http://localhost:3002)"
        else
            echo -e "${YELLOW}⚠ 启动中...${NC}"
            echo "  查看日志: tail -f $LOG_DIR/fragments.log"
        fi
    fi

    # 检查 Surf
    echo -n "Surf: "
    if curl -s http://localhost:3003 > /dev/null 2>&1; then
        echo -e "${GREEN}✓ 运行中${NC} (http://localhost:3003)"
    else
        # 尝试 3004 端口
        if curl -s http://localhost:3004 > /dev/null 2>&1; then
            echo -e "${GREEN}✓ 运行中${NC} (http://localhost:3004)"
        else
            echo -e "${YELLOW}⚠ 启动中...${NC}"
            echo "  查看日志: tail -f $LOG_DIR/surf.log"
        fi
    fi

    echo ""
}

# 显示状态
show_status() {
    echo ""
    echo "=========================================="
    echo -e "${GREEN}${BOLD}✓ 前端应用启动完成${NC}"
    echo "=========================================="
    echo ""

    echo "访问地址:"
    echo "  Fragments: http://localhost:3001 (或 3002)"
    echo "  Surf:      http://localhost:3003 (或 3004)"
    echo ""

    echo "日志文件:"
    echo "  Fragments: $LOG_DIR/fragments.log"
    echo "  Surf:      $LOG_DIR/surf.log"
    echo ""

    echo "查看日志:"
    echo "  tail -f $LOG_DIR/fragments.log"
    echo "  tail -f $LOG_DIR/surf.log"
    echo ""

    echo "停止应用:"
    echo "  pkill -f 'next dev'"
    echo ""

    echo -e "${GREEN}🎉 准备就绪！${NC}"
    echo ""
}

# 主流程
main() {
    check_nodejs
    stop_existing_apps
    install_dependencies
    start_apps
    health_check
    show_status
}

# 执行主流程
main
