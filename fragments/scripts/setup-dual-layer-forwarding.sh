#!/bin/bash
#
# E2B 双层端口转发设置工具
#
# 用途：为 E2B 沙箱设置完整的双层 TCP 端口转发
# 架构：Tailscale IP → vpeerIP (Layer 1) → VM Internal IP (Layer 2)
#
# 使用方法：
#   ./setup-dual-layer-forwarding.sh setup <sandbox_ip> <port> <external_port>
#   ./setup-dual-layer-forwarding.sh cleanup <sandbox_ip> <port> <external_port>
#   ./setup-dual-layer-forwarding.sh status <sandbox_ip> <port>
#

set -e

# 配置
TAILSCALE_IP="${TAILSCALE_IP:-100.64.0.23}"
VM_INTERNAL_IP="169.254.0.21"
SUDO_PASSWORD="${SUDO_PASSWORD:-Primihub@2022.}"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 从 sandbox IP 计算网络参数
calculate_network_params() {
    local sandbox_ip=$1

    # 分割 IP 地址
    IFS='.' read -r -a ip_parts <<< "$sandbox_ip"

    # 计算 slot index: 第3段 * 256 + 第4段
    local slot_idx=$(( ${ip_parts[2]} * 256 + ${ip_parts[3]} ))

    # 计算 namespace ID
    local namespace_id="ns-${slot_idx}"

    # 计算 vpeerIP: 10.12.0.0 + (slot_idx * 2 + 1)
    local vpeer_offset=$(( slot_idx * 2 + 1 ))
    local vpeer_third=$(( vpeer_offset / 256 ))
    local vpeer_fourth=$(( vpeer_offset % 256 ))
    local vpeer_ip="10.12.${vpeer_third}.${vpeer_fourth}"

    # 输出结果（使用 echo 以便被捕获）
    echo "${slot_idx}|${namespace_id}|${vpeer_ip}"
}

# 设置双层端口转发
setup_forwarding() {
    local sandbox_ip=$1
    local port=$2
    local external_port=$3

    log_info "设置双层端口转发..."
    log_info "  Sandbox IP: ${sandbox_ip}"
    log_info "  Port: ${port}"
    log_info "  External Port: ${external_port}"

    # 计算网络参数
    local params=$(calculate_network_params "$sandbox_ip")
    IFS='|' read -r slot_idx namespace_id vpeer_ip <<< "$params"

    log_info "  Slot Index: ${slot_idx}"
    log_info "  Namespace: ${namespace_id}"
    log_info "  VpeerIP: ${vpeer_ip}"

    # 检查 namespace 是否存在
    if ! echo "$SUDO_PASSWORD" | sudo -S ip netns list | grep -q "$namespace_id"; then
        log_error "Network namespace ${namespace_id} 不存在"
        log_error "请确保沙箱已正确创建"
        return 1
    fi

    log_info "✓ Network namespace 存在"

    # 清理已存在的转发
    log_info "清理旧的端口转发进程..."
    pkill -f "socat.*${external_port}" 2>/dev/null || true
    echo "$SUDO_PASSWORD" | sudo -S pkill -f "socat.*${vpeer_ip}:${port}" 2>/dev/null || true
    sleep 1

    # 设置 Layer 2 转发（在网络命名空间内）
    log_info "设置 Layer 2 转发: ${vpeer_ip}:${port} → ${VM_INTERNAL_IP}:${port}"

    echo "$SUDO_PASSWORD" | sudo -S ip netns exec "$namespace_id" \
        socat "TCP4-LISTEN:${port},bind=${vpeer_ip},reuseaddr,fork" \
              "TCP4:${VM_INTERNAL_IP}:${port}" \
        > /dev/null 2>&1 &

    sleep 1

    # 验证 Layer 2 进程
    if echo "$SUDO_PASSWORD" | sudo -S ip netns exec "$namespace_id" ps aux | grep -q "socat.*${port}.*${VM_INTERNAL_IP}"; then
        log_info "✓ Layer 2 转发已启动"
    else
        log_error "✗ Layer 2 转发启动失败"
        return 1
    fi

    # 设置 Layer 1 转发（在主机上）
    log_info "设置 Layer 1 转发: ${TAILSCALE_IP}:${external_port} → ${vpeer_ip}:${port}"

    socat "TCP-LISTEN:${external_port},bind=${TAILSCALE_IP},fork,reuseaddr" \
          "TCP:${vpeer_ip}:${port}" \
        > /dev/null 2>&1 &

    sleep 1

    # 验证 Layer 1 进程
    if ps aux | grep -q "socat.*${external_port}.*${vpeer_ip}"; then
        log_info "✓ Layer 1 转发已启动"
    else
        log_error "✗ Layer 1 转发启动失败"
        return 1
    fi

    log_info ""
    log_info "✅ 双层端口转发设置成功！"
    log_info ""
    log_info "访问 URL: http://${TAILSCALE_IP}:${external_port}"
    log_info ""
    log_info "转发路径："
    log_info "  ${TAILSCALE_IP}:${external_port}"
    log_info "    ↓ Layer 1 (Host)"
    log_info "  ${vpeer_ip}:${port}"
    log_info "    ↓ Layer 2 (Namespace ${namespace_id})"
    log_info "  ${VM_INTERNAL_IP}:${port}"
    log_info "    ↓"
    log_info "  Application in VM"
}

# 清理端口转发
cleanup_forwarding() {
    local sandbox_ip=$1
    local port=$2
    local external_port=$3

    log_info "清理端口转发..."
    log_info "  Sandbox IP: ${sandbox_ip}"
    log_info "  Port: ${port}"
    log_info "  External Port: ${external_port}"

    # 计算网络参数
    local params=$(calculate_network_params "$sandbox_ip")
    IFS='|' read -r slot_idx namespace_id vpeer_ip <<< "$params"

    log_info "  Namespace: ${namespace_id}"
    log_info "  VpeerIP: ${vpeer_ip}"

    # 清理 Layer 1 进程
    log_info "清理 Layer 1 转发进程..."
    if pkill -f "socat.*${external_port}.*${vpeer_ip}" 2>/dev/null; then
        log_info "✓ Layer 1 进程已清理"
    else
        log_warn "未找到 Layer 1 进程"
    fi

    # 清理 Layer 2 进程
    log_info "清理 Layer 2 转发进程..."
    if echo "$SUDO_PASSWORD" | sudo -S pkill -f "socat.*${vpeer_ip}:${port}" 2>/dev/null; then
        log_info "✓ Layer 2 进程已清理"
    else
        log_warn "未找到 Layer 2 进程"
    fi

    log_info "✅ 端口转发清理完成"
}

# 查看端口转发状态
status_forwarding() {
    local sandbox_ip=$1
    local port=$2

    log_info "查询端口转发状态..."
    log_info "  Sandbox IP: ${sandbox_ip}"
    log_info "  Port: ${port}"

    # 计算网络参数
    local params=$(calculate_network_params "$sandbox_ip")
    IFS='|' read -r slot_idx namespace_id vpeer_ip <<< "$params"

    log_info "  Namespace: ${namespace_id}"
    log_info "  VpeerIP: ${vpeer_ip}"
    echo ""

    # 检查 namespace 是否存在
    if echo "$SUDO_PASSWORD" | sudo -S ip netns list | grep -q "$namespace_id"; then
        log_info "✓ Network namespace ${namespace_id} 存在"
    else
        log_error "✗ Network namespace ${namespace_id} 不存在"
        return 1
    fi

    # 检查 Layer 2 进程
    echo ""
    log_info "Layer 2 转发状态 (在 ${namespace_id} 内):"
    if echo "$SUDO_PASSWORD" | sudo -S ip netns exec "$namespace_id" ps aux | grep "socat.*${port}" | grep -v grep; then
        log_info "✓ Layer 2 转发进程运行中"
    else
        log_warn "✗ Layer 2 转发进程未运行"
    fi

    # 检查 Layer 1 进程
    echo ""
    log_info "Layer 1 转发状态 (在主机上):"
    if ps aux | grep "socat.*${vpeer_ip}:${port}" | grep -v grep; then
        log_info "✓ Layer 1 转发进程运行中"
    else
        log_warn "✗ Layer 1 转发进程未运行"
    fi

    # 测试端口连通性
    echo ""
    log_info "测试端口连通性..."

    # 查找 external port
    local external_port=$(ps aux | grep "socat.*${TAILSCALE_IP}.*${vpeer_ip}:${port}" | grep -v grep | awk '{for(i=1;i<=NF;i++) if($i ~ /TCP-LISTEN/) print $i}' | sed 's/.*://' | sed 's/,.*//')

    if [ -n "$external_port" ]; then
        log_info "External Port: ${external_port}"
        log_info "测试 URL: http://${TAILSCALE_IP}:${external_port}"

        if timeout 3 curl -s -o /dev/null -w "%{http_code}" "http://${TAILSCALE_IP}:${external_port}" > /dev/null 2>&1; then
            log_info "✓ 端口可访问"
        else
            log_warn "✗ 端口无法访问（可能服务未启动）"
        fi
    else
        log_warn "未找到 external port"
    fi
}

# 显示使用帮助
show_usage() {
    cat << EOF
E2B 双层端口转发设置工具

用途：为 E2B 沙箱设置完整的双层 TCP 端口转发

使用方法：
  $0 setup <sandbox_ip> <port> <external_port>
      设置双层端口转发

  $0 cleanup <sandbox_ip> <port> <external_port>
      清理端口转发

  $0 status <sandbox_ip> <port>
      查看端口转发状态

参数说明：
  sandbox_ip      沙箱的 IP 地址 (例如: 10.11.1.58)
  port            沙箱内应用监听的端口 (例如: 3000)
  external_port   外部访问端口 (例如: 31988)

环境变量：
  TAILSCALE_IP    Tailscale IP 地址 (默认: 100.64.0.23)
  SUDO_PASSWORD   sudo 密码 (默认: Primihub@2022.)

示例：
  # 设置转发
  $0 setup 10.11.1.58 3000 31988

  # 查看状态
  $0 status 10.11.1.58 3000

  # 清理转发
  $0 cleanup 10.11.1.58 3000 31988

网络架构：
  外部访问 → Tailscale IP:external_port
           ↓ Layer 1 (Host)
           → vpeerIP:port
           ↓ Layer 2 (Network Namespace)
           → VM Internal IP (169.254.0.21):port
           ↓
           Application in VM

EOF
}

# 主函数
main() {
    local command=$1

    case "$command" in
        setup)
            if [ $# -ne 4 ]; then
                log_error "参数错误"
                show_usage
                exit 1
            fi
            setup_forwarding "$2" "$3" "$4"
            ;;
        cleanup)
            if [ $# -ne 4 ]; then
                log_error "参数错误"
                show_usage
                exit 1
            fi
            cleanup_forwarding "$2" "$3" "$4"
            ;;
        status)
            if [ $# -ne 3 ]; then
                log_error "参数错误"
                show_usage
                exit 1
            fi
            status_forwarding "$2" "$3"
            ;;
        help|--help|-h)
            show_usage
            ;;
        *)
            log_error "未知命令: $command"
            show_usage
            exit 1
            ;;
    esac
}

# 执行主函数
main "$@"
