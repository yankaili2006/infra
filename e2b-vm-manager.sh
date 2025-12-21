#!/bin/bash
# E2B VM Manager - 便捷启动和管理 E2B 虚拟机
# 版本: 1.0
# 日期: 2025-12-21

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 默认配置
DEFAULT_TEMPLATE_ID="base-template-000-0000-0000-000000000001"
DEFAULT_API_KEY="e2b_53ae1fed82754c17ad8077fbc8bcdd90"
DEFAULT_API_URL="http://localhost:3000"
DEFAULT_TIMEOUT=300

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 显示使用帮助
show_help() {
    cat << EOF
E2B VM Manager - 便捷启动和管理 E2B 虚拟机

用法:
    $0 [命令] [选项]

命令:
    create          创建新的虚拟机
    list            列出所有运行中的虚拟机
    connect         连接到虚拟机
    logs            获取虚拟机日志
    delete          删除虚拟机
    status          检查服务状态
    setup           初始化环境配置
    health          健康检查
    exec            在虚拟机中执行命令

选项:
    -t, --template   模板 ID (默认: $DEFAULT_TEMPLATE_ID)
    -k, --api-key    API Key (默认: $DEFAULT_API_KEY)
    -u, --url        API URL (默认: $DEFAULT_API_URL)
    -s, --sandbox    Sandbox ID (用于 connect/logs/delete/exec)
    -c, --cmd        要执行的命令 (用于 exec)
    --timeout        超时时间(秒) (默认: $DEFAULT_TIMEOUT)
    -h, --help       显示此帮助信息

示例:
    # 创建虚拟机
    $0 create

    # 创建带自定义模板的虚拟机
    $0 create -t my-custom-template

    # 列出所有虚拟机
    $0 list

    # 连接到虚拟机
    $0 connect -s <sandbox-id>

    # 获取日志
    $0 logs -s <sandbox-id>

    # 在虚拟机中执行命令
    $0 exec -s <sandbox-id> -c "ls -la"

    # 删除虚拟机
    $0 delete -s <sandbox-id>

    # 检查服务状态
    $0 status

    # 健康检查
    $0 health

EOF
}

# 解析命令行参数
parse_args() {
    COMMAND=""
    TEMPLATE_ID="$DEFAULT_TEMPLATE_ID"
    API_KEY="$DEFAULT_API_KEY"
    API_URL="$DEFAULT_API_URL"
    SANDBOX_ID=""
    EXEC_CMD=""
    TIMEOUT="$DEFAULT_TIMEOUT"

    while [[ $# -gt 0 ]]; do
        case $1 in
            create|list|connect|logs|delete|status|setup|health|exec)
                COMMAND="$1"
                shift
                ;;
            -t|--template)
                TEMPLATE_ID="$2"
                shift 2
                ;;
            -k|--api-key)
                API_KEY="$2"
                shift 2
                ;;
            -u|--url)
                API_URL="$2"
                shift 2
                ;;
            -s|--sandbox)
                SANDBOX_ID="$2"
                shift 2
                ;;
            -c|--cmd)
                EXEC_CMD="$2"
                shift 2
                ;;
            --timeout)
                TIMEOUT="$2"
                shift 2
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "未知参数: $1"
                show_help
                exit 1
                ;;
        esac
    done

    if [ -z "$COMMAND" ]; then
        log_error "请指定命令"
        show_help
        exit 1
    fi
}

# 环境检查
check_environment() {
    log_info "检查环境..."

    # 检查必要的命令
    local required_commands=("curl" "jq")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            log_error "缺少必要命令: $cmd"
            log_info "请安装: sudo apt-get install $cmd"
            exit 1
        fi
    done

    # 检查 API 服务是否可达
    if ! curl -s -f -m 5 "$API_URL/health" &> /dev/null; then
        log_warning "API 服务似乎不可达: $API_URL"
        log_warning "请确保服务正在运行"
    fi

    log_success "环境检查通过"
}

# 健康检查
health_check() {
    log_info "执行健康检查..."

    # 检查 API 健康状态
    log_info "检查 API 服务..."
    local api_response=$(curl -s -w "\n%{http_code}" "$API_URL/health" 2>/dev/null)
    local api_status=$(echo "$api_response" | tail -n1)

    if [ "$api_status" = "200" ]; then
        log_success "API 服务健康 ($API_URL)"
    else
        log_error "API 服务异常 (HTTP $api_status)"
        return 1
    fi

    # 检查 Orchestrator (如果在本地)
    if command -v nomad &> /dev/null; then
        log_info "检查 Orchestrator 服务..."
        if nomad job status orchestrator &> /dev/null; then
            local orch_status=$(nomad job status orchestrator | grep "Status" | awk '{print $3}')
            if [ "$orch_status" = "running" ]; then
                log_success "Orchestrator 服务运行中"
            else
                log_warning "Orchestrator 状态: $orch_status"
            fi
        else
            log_warning "无法获取 Orchestrator 状态"
        fi
    fi

    log_success "健康检查完成"
}

# 创建虚拟机
create_vm() {
    log_info "创建虚拟机..."
    log_info "模板: $TEMPLATE_ID"
    log_info "超时: $TIMEOUT 秒"

    local response=$(curl -s -w "\n%{http_code}" -X POST "$API_URL/sandboxes" \
        -H "Content-Type: application/json" \
        -H "X-API-Key: $API_KEY" \
        -d "{\"templateID\": \"$TEMPLATE_ID\", \"timeout\": $TIMEOUT}")

    local http_code=$(echo "$response" | tail -n1)
    local body=$(echo "$response" | sed '$d')

    if [ "$http_code" = "200" ] || [ "$http_code" = "201" ]; then
        local sandbox_id=$(echo "$body" | jq -r '.sandboxID // .id // empty')
        local client_id=$(echo "$body" | jq -r '.clientID // empty')

        if [ -n "$sandbox_id" ]; then
            log_success "虚拟机创建成功!"
            echo ""
            echo "虚拟机信息:"
            echo "  Sandbox ID: $sandbox_id"
            [ -n "$client_id" ] && echo "  Client ID:  $client_id"
            echo ""
            echo "连接命令:"
            echo "  $0 connect -s $sandbox_id"
            echo ""
            echo "执行命令:"
            echo "  $0 exec -s $sandbox_id -c \"<your-command>\""
            echo ""
            echo "查看日志:"
            echo "  $0 logs -s $sandbox_id"
            echo ""

            # 保存最后创建的 sandbox ID
            echo "$sandbox_id" > /tmp/e2b_last_sandbox_id
        else
            log_warning "虚拟机可能已创建，但无法解析 Sandbox ID"
            echo "$body" | jq '.' 2>/dev/null || echo "$body"
        fi
    else
        log_error "创建虚拟机失败 (HTTP $http_code)"
        echo "$body" | jq '.' 2>/dev/null || echo "$body"
        exit 1
    fi
}

# 列出虚拟机
list_vms() {
    log_info "获取虚拟机列表..."

    local response=$(curl -s -w "\n%{http_code}" -X GET "$API_URL/sandboxes" \
        -H "X-API-Key: $API_KEY")

    local http_code=$(echo "$response" | tail -n1)
    local body=$(echo "$response" | sed '$d')

    if [ "$http_code" = "200" ]; then
        echo "$body" | jq -r '.sandboxes[] | "ID: \(.sandboxID // .id) | Template: \(.templateID) | Started: \(.startedAt)"' 2>/dev/null || {
            log_warning "无法解析虚拟机列表"
            echo "$body" | jq '.' 2>/dev/null || echo "$body"
        }
    else
        log_error "获取虚拟机列表失败 (HTTP $http_code)"
        echo "$body" | jq '.' 2>/dev/null || echo "$body"
        exit 1
    fi
}

# 连接到虚拟机
connect_vm() {
    if [ -z "$SANDBOX_ID" ]; then
        # 尝试使用最后创建的 sandbox
        if [ -f /tmp/e2b_last_sandbox_id ]; then
            SANDBOX_ID=$(cat /tmp/e2b_last_sandbox_id)
            log_info "使用最后创建的 Sandbox ID: $SANDBOX_ID"
        else
            log_error "请指定 Sandbox ID: -s <sandbox-id>"
            exit 1
        fi
    fi

    log_info "连接到虚拟机: $SANDBOX_ID"

    local response=$(curl -s -w "\n%{http_code}" -X POST "$API_URL/sandboxes/$SANDBOX_ID/connect" \
        -H "X-API-Key: $API_KEY")

    local http_code=$(echo "$response" | tail -n1)
    local body=$(echo "$response" | sed '$d')

    if [ "$http_code" = "200" ]; then
        log_success "连接成功!"
        echo ""
        echo "虚拟机详细信息:"
        echo "$body" | jq '.' 2>/dev/null || echo "$body"
        echo ""
        echo "可用操作:"
        echo "  执行命令: $0 exec -s $SANDBOX_ID -c \"<command>\""
        echo "  查看日志: $0 logs -s $SANDBOX_ID"
        echo "  删除虚拟机: $0 delete -s $SANDBOX_ID"
    else
        log_error "连接失败 (HTTP $http_code)"
        echo "$body" | jq '.' 2>/dev/null || echo "$body"
        exit 1
    fi
}

# 获取日志
get_logs() {
    if [ -z "$SANDBOX_ID" ]; then
        if [ -f /tmp/e2b_last_sandbox_id ]; then
            SANDBOX_ID=$(cat /tmp/e2b_last_sandbox_id)
            log_info "使用最后创建的 Sandbox ID: $SANDBOX_ID"
        else
            log_error "请指定 Sandbox ID: -s <sandbox-id>"
            exit 1
        fi
    fi

    log_info "获取虚拟机日志: $SANDBOX_ID"

    local response=$(curl -s -w "\n%{http_code}" -X GET "$API_URL/sandboxes/$SANDBOX_ID/logs" \
        -H "X-API-Key: $API_KEY")

    local http_code=$(echo "$response" | tail -n1)
    local body=$(echo "$response" | sed '$d')

    if [ "$http_code" = "200" ]; then
        echo "$body" | jq -r '.logs[]? // .logEntries[]? | "\(.timestamp) [\(.level // "INFO")] \(.message)"' 2>/dev/null || {
            echo "$body" | jq '.' 2>/dev/null || echo "$body"
        }
    else
        log_error "获取日志失败 (HTTP $http_code)"
        echo "$body" | jq '.' 2>/dev/null || echo "$body"
        exit 1
    fi
}

# 在虚拟机中执行命令 (需要 envd 支持)
exec_command() {
    if [ -z "$SANDBOX_ID" ]; then
        if [ -f /tmp/e2b_last_sandbox_id ]; then
            SANDBOX_ID=$(cat /tmp/e2b_last_sandbox_id)
            log_info "使用最后创建的 Sandbox ID: $SANDBOX_ID"
        else
            log_error "请指定 Sandbox ID: -s <sandbox-id>"
            exit 1
        fi
    fi

    if [ -z "$EXEC_CMD" ]; then
        log_error "请指定要执行的命令: -c \"<command>\""
        exit 1
    fi

    log_warning "注意: 此功能需要虚拟机内的 envd 服务正常运行"
    log_info "在虚拟机 $SANDBOX_ID 中执行: $EXEC_CMD"

    # 这里需要根据实际的 API 端点调整
    # E2B 通常通过 WebSocket 或 gRPC 与 envd 通信
    log_error "exec 命令需要通过 E2B SDK 或 gRPC 客户端实现"
    log_info "请使用官方 E2B SDK (Python/JavaScript) 或直接调用 envd gRPC 接口"
}

# 删除虚拟机
delete_vm() {
    if [ -z "$SANDBOX_ID" ]; then
        if [ -f /tmp/e2b_last_sandbox_id ]; then
            SANDBOX_ID=$(cat /tmp/e2b_last_sandbox_id)
            log_info "使用最后创建的 Sandbox ID: $SANDBOX_ID"
        else
            log_error "请指定 Sandbox ID: -s <sandbox-id>"
            exit 1
        fi
    fi

    log_info "删除虚拟机: $SANDBOX_ID"

    local response=$(curl -s -w "\n%{http_code}" -X DELETE "$API_URL/sandboxes/$SANDBOX_ID" \
        -H "X-API-Key: $API_KEY")

    local http_code=$(echo "$response" | tail -n1)
    local body=$(echo "$response" | sed '$d')

    if [ "$http_code" = "200" ] || [ "$http_code" = "204" ]; then
        log_success "虚拟机已删除"
        rm -f /tmp/e2b_last_sandbox_id
    else
        log_error "删除失败 (HTTP $http_code)"
        echo "$body" | jq '.' 2>/dev/null || echo "$body"
        exit 1
    fi
}

# 检查服务状态
check_status() {
    log_info "检查服务状态..."
    echo ""

    # API 服务
    echo "=== API 服务 ==="
    if curl -s -f -m 5 "$API_URL/health" &> /dev/null; then
        log_success "API 运行中: $API_URL"
    else
        log_error "API 不可达: $API_URL"
    fi
    echo ""

    # Nomad 服务 (如果可用)
    if command -v nomad &> /dev/null; then
        echo "=== Nomad 服务 ==="
        nomad job status 2>/dev/null || log_warning "无法获取 Nomad 状态"
        echo ""
    fi

    # 检查运行中的 Firecracker 进程
    echo "=== Firecracker 虚拟机 ==="
    local fc_count=$(pgrep -c firecracker 2>/dev/null || echo "0")
    if [ "$fc_count" -gt 0 ]; then
        log_success "发现 $fc_count 个运行中的 Firecracker 进程"
        ps aux | grep firecracker | grep -v grep | head -5
    else
        log_info "没有运行中的 Firecracker 虚拟机"
    fi
}

# 初始化环境配置
setup_environment() {
    log_info "初始化 E2B 环境配置..."

    # 创建配置文件
    local config_file="$HOME/.e2b_config"

    cat > "$config_file" << EOF
# E2B VM Manager Configuration
# 生成时间: $(date)

# API 配置
E2B_API_URL="$API_URL"
E2B_API_KEY="$API_KEY"
E2B_DEFAULT_TEMPLATE="$TEMPLATE_ID"
E2B_DEFAULT_TIMEOUT=$TIMEOUT

# 存储路径配置
STORAGE_PROVIDER="Local"
LOCAL_TEMPLATE_STORAGE_BASE_PATH="/home/\$USER/e2b-storage/e2b-template-storage"
TEMPLATE_CACHE_DIR="/home/\$USER/e2b-storage/e2b-template-cache"
BUILD_CACHE_BUCKET_NAME="/home/\$USER/e2b-storage/e2b-build-cache"

# 数据库配置
POSTGRES_CONNECTION_STRING="postgresql://postgres:postgres@localhost:5432/postgres?sslmode=disable"
EOF

    log_success "配置文件已创建: $config_file"
    log_info "添加以下行到 ~/.bashrc 或 ~/.zshrc:"
    echo ""
    echo "  source $config_file"
    echo ""
}

# 主函数
main() {
    # 显示脚本头部
    echo ""
    echo "========================================="
    echo "   E2B VM Manager v1.0"
    echo "========================================="
    echo ""

    parse_args "$@"

    case $COMMAND in
        setup)
            setup_environment
            ;;
        health)
            check_environment
            health_check
            ;;
        create)
            check_environment
            create_vm
            ;;
        list)
            list_vms
            ;;
        connect)
            connect_vm
            ;;
        logs)
            get_logs
            ;;
        exec)
            exec_command
            ;;
        delete)
            delete_vm
            ;;
        status)
            check_status
            ;;
        *)
            log_error "未知命令: $COMMAND"
            show_help
            exit 1
            ;;
    esac
}

# 运行主函数
main "$@"
