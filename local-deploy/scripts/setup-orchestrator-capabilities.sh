#!/bin/bash
# Orchestrator Capabilities 设置脚本
# 用途：为 orchestrator 二进制文件设置必要的 capabilities，使其无需 root 权限运行
# 版本：v1.0
# 创建时间：2026-02-02

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

# 打印分隔线
print_separator() {
    echo "=================================================="
}

# 检查是否以 root 权限运行
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "此脚本需要 root 权限运行"
        log_info "请使用: sudo $0"
        exit 1
    fi
}

# 设置环境变量
setup_env() {
    export PCLOUD_HOME="${PCLOUD_HOME:-/mnt/data1/pcloud}"
    log_info "PCLOUD_HOME: $PCLOUD_HOME"
}

# 检查 orchestrator 二进制文件是否存在
check_orchestrator_binary() {
    local ORCHESTRATOR_BIN="$PCLOUD_HOME/infra/packages/orchestrator/bin/orchestrator"

    if [ ! -f "$ORCHESTRATOR_BIN" ]; then
        log_error "Orchestrator 二进制文件不存在: $ORCHESTRATOR_BIN"
        log_info "请先编译 orchestrator:"
        echo "  cd $PCLOUD_HOME/infra/packages/orchestrator"
        echo "  go build -o bin/orchestrator ."
        exit 1
    fi

    log_success "找到 orchestrator 二进制文件: $ORCHESTRATOR_BIN"
}

# 设置 capabilities
set_capabilities() {
    local ORCHESTRATOR_BIN="$PCLOUD_HOME/infra/packages/orchestrator/bin/orchestrator"

    log_info "正在设置 capabilities..."

    # 设置 cap_net_admin 和 cap_sys_admin capabilities
    if setcap cap_net_admin,cap_sys_admin+ep "$ORCHESTRATOR_BIN"; then
        log_success "Capabilities 设置成功"
    else
        log_error "Capabilities 设置失败"
        exit 1
    fi
}

# 验证 capabilities
verify_capabilities() {
    local ORCHESTRATOR_BIN="$PCLOUD_HOME/infra/packages/orchestrator/bin/orchestrator"

    log_info "验证 capabilities..."

    local caps=$(getcap "$ORCHESTRATOR_BIN")
    if [ -z "$caps" ]; then
        log_error "Capabilities 未设置"
        exit 1
    fi

    log_success "当前 capabilities: $caps"

    # 检查是否包含必需的 capabilities
    if echo "$caps" | grep -q "cap_net_admin" && echo "$caps" | grep -q "cap_sys_admin"; then
        log_success "所有必需的 capabilities 已正确设置"
    else
        log_warning "Capabilities 可能不完整"
    fi
}

# 处理 sudoers 模板文件
setup_sudoers() {
    local TEMPLATE_FILE="$PCLOUD_HOME/infra/local-deploy/config/sudoers-orchestrator.template"
    local TEMP_FILE="/tmp/sudoers-orchestrator-$$"
    local TARGET_FILE="/etc/sudoers.d/orchestrator"

    log_info "处理 sudoers 配置文件..."

    # 检查模板文件是否存在
    if [ ! -f "$TEMPLATE_FILE" ]; then
        log_error "模板文件不存在: $TEMPLATE_FILE"
        exit 1
    fi

    # 替换占位符并生成临时文件
    sed "s|{{PCLOUD_HOME}}|$PCLOUD_HOME|g" "$TEMPLATE_FILE" > "$TEMP_FILE"
    log_success "已生成临时 sudoers 文件: $TEMP_FILE"

    # 验证语法
    log_info "验证 sudoers 文件语法..."
    if visudo -c -f "$TEMP_FILE"; then
        log_success "Sudoers 文件语法验证通过"
    else
        log_error "Sudoers 文件语法验证失败"
        rm -f "$TEMP_FILE"
        exit 1
    fi

    # 拷贝到目标位置
    log_info "拷贝 sudoers 文件到 $TARGET_FILE..."
    if cp "$TEMP_FILE" "$TARGET_FILE"; then
        log_success "Sudoers 文件拷贝成功"
    else
        log_error "Sudoers 文件拷贝失败"
        rm -f "$TEMP_FILE"
        exit 1
    fi

    # 设置正确的权限
    log_info "设置 sudoers 文件权限..."
    if chmod 0440 "$TARGET_FILE"; then
        log_success "Sudoers 文件权限设置成功 (0440)"
    else
        log_error "Sudoers 文件权限设置失败"
        rm -f "$TEMP_FILE"
        exit 1
    fi

    # 清理临时文件
    rm -f "$TEMP_FILE"
    log_success "Sudoers 配置完成"
}

# 处理 orchestrator.hcl 模板文件
setup_orchestrator_hcl() {
    local TEMPLATE_FILE="$PCLOUD_HOME/infra/local-deploy/jobs/orchestrator.hcl.template"
    local TARGET_FILE="$PCLOUD_HOME/infra/local-deploy/jobs/orchestrator.hcl"

    log_info "处理 orchestrator.hcl 配置文件..."

    # 检查模板文件是否存在
    if [ ! -f "$TEMPLATE_FILE" ]; then
        log_error "模板文件不存在: $TEMPLATE_FILE"
        exit 1
    fi

    # 替换占位符并生成目标文件
    sed "s|{{PCLOUD_HOME}}|$PCLOUD_HOME|g" "$TEMPLATE_FILE" > "$TARGET_FILE"
    log_success "已生成 orchestrator.hcl: $TARGET_FILE"
}

# 主函数
main() {
    print_separator
    echo -e "${BLUE}Orchestrator Capabilities 设置脚本${NC}"
    print_separator
    echo ""

    # 检查 root 权限
    check_root

    # 设置环境变量
    setup_env

    # 检查二进制文件
    check_orchestrator_binary

    # 处理 sudoers 配置文件
    setup_sudoers

    # 处理 orchestrator.hcl 配置文件
    setup_orchestrator_hcl

    # 设置 capabilities
    set_capabilities

    # 验证 capabilities
    verify_capabilities

    echo ""
    print_separator
    log_success "Orchestrator capabilities 设置完成！"
    print_separator
    echo ""
    log_info "现在可以无需 root 权限运行 orchestrator"
    log_info "Nomad 配置应使用: command = \"$PCLOUD_HOME/infra/local-deploy/scripts/start-orchestrator.sh\""
    echo ""
}

# 执行主函数
main "$@"
