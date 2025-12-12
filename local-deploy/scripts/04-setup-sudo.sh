#!/bin/bash
set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=================================="
echo "E2B 本地部署 - Sudo 权限配置"
echo "=================================="
echo ""

# 检查是否为 root 用户
if [ "$EUID" -ne 0 ]; then
    echo -e "${YELLOW}⚠${NC} 此脚本需要 sudo 权限"
    echo "请使用: sudo $0"
    exit 1
fi

# 获取实际用户
if [ -n "$SUDO_USER" ]; then
    ACTUAL_USER="$SUDO_USER"
else
    echo -e "${RED}✗${NC} 无法检测实际用户"
    echo "请使用 sudo 运行此脚本，而不是直接以 root 用户运行"
    exit 1
fi

echo "配置用户: $ACTUAL_USER"
echo ""

# Orchestrator 二进制文件路径
ORCHESTRATOR_BIN="/home/primihub/pcloud/infra/packages/orchestrator/bin/orchestrator"

echo "Orchestrator 路径: $ORCHESTRATOR_BIN"
echo ""
echo "Firecracker 需要特权来:"
echo "  - 创建和管理 TAP 网络设备"
echo "  - 配置 iptables 规则"
echo "  - 挂载和管理 NBD (Network Block Device)"
echo "  - 配置虚拟机内存和 CPU"
echo ""
echo "有两种方式授予这些权限:"
echo ""
echo "选项 A: 使用 Linux Capabilities (推荐，更安全)"
echo "  优点: 只授予必需的权限，无需 sudo"
echo "  缺点: 需要二进制文件已构建"
echo ""
echo "选项 B: 配置 sudo 免密码"
echo "  优点: 简单，适合开发环境"
echo "  缺点: 授予完整 sudo 权限，安全性较低"
echo ""

# 检查 orchestrator 二进制是否存在
if [ -f "$ORCHESTRATOR_BIN" ]; then
    BINARY_EXISTS=true
    echo -e "${GREEN}✓${NC} Orchestrator 二进制文件存在"
else
    BINARY_EXISTS=false
    echo -e "${YELLOW}⚠${NC} Orchestrator 二进制文件不存在（将在后续步骤构建）"
fi
echo ""

# 询问用户选择
read -p "选择配置方式 [A/B，默认 A]: " CHOICE
CHOICE=${CHOICE:-A}

case "$CHOICE" in
    [Aa]*)
        echo ""
        echo "选择: 选项 A - 使用 Linux Capabilities"
        echo ""

        if [ "$BINARY_EXISTS" = true ]; then
            # 设置 capabilities
            echo "为 Orchestrator 设置 capabilities..."

            # 需要的 capabilities:
            # - CAP_NET_ADMIN: 网络管理（TAP 设备，iptables）
            # - CAP_SYS_ADMIN: 系统管理（NBD，挂载）
            # - CAP_NET_RAW: 原始网络访问
            setcap cap_net_admin,cap_sys_admin,cap_net_raw+ep "$ORCHESTRATOR_BIN"

            echo -e "${GREEN}✓${NC} Capabilities 已设置"
            echo ""

            # 验证
            echo "验证 capabilities:"
            getcap "$ORCHESTRATOR_BIN"
            echo ""

            echo -e "${GREEN}✓${NC} 配置完成"
            echo ""
            echo "Orchestrator 现在可以以普通用户身份运行，无需 sudo"

        else
            echo -e "${YELLOW}⚠${NC} Orchestrator 二进制文件不存在"
            echo ""
            echo "将在构建二进制文件后自动设置 capabilities"
            echo "创建配置文件以便后续使用..."

            # 创建配置文件供后续使用
            CONFIG_FILE="/tmp/e2b-setup-capabilities.sh"
            cat > "$CONFIG_FILE" <<'CAPSCRIPT'
#!/bin/bash
ORCHESTRATOR_BIN="/home/primihub/pcloud/infra/packages/orchestrator/bin/orchestrator"
if [ -f "$ORCHESTRATOR_BIN" ]; then
    sudo setcap cap_net_admin,cap_sys_admin,cap_net_raw+ep "$ORCHESTRATOR_BIN"
    echo "✓ Capabilities 已设置"
    getcap "$ORCHESTRATOR_BIN"
else
    echo "✗ Orchestrator 二进制文件不存在: $ORCHESTRATOR_BIN"
    exit 1
fi
CAPSCRIPT

            chmod +x "$CONFIG_FILE"
            echo -e "${GREEN}✓${NC} 配置脚本已创建: $CONFIG_FILE"
            echo "在构建 Orchestrator 后运行此脚本"
        fi
        ;;

    [Bb]*)
        echo ""
        echo "选择: 选项 B - 配置 sudo 免密码"
        echo ""

        # 创建 sudoers 配置文件
        SUDOERS_FILE="/etc/sudoers.d/e2b-local"

        echo "创建 sudoers 配置..."
        cat > "$SUDOERS_FILE" <<EOF
# E2B 本地部署 sudo 配置
# 自动生成于: $(date)
# 用户: $ACTUAL_USER

# 允许用户免密码运行 orchestrator
$ACTUAL_USER ALL=(ALL) NOPASSWD: $ORCHESTRATOR_BIN

# 允许用户管理网络（可选）
$ACTUAL_USER ALL=(ALL) NOPASSWD: /sbin/iptables
$ACTUAL_USER ALL=(ALL) NOPASSWD: /sbin/ip
$ACTUAL_USER ALL=(ALL) NOPASSWD: /sbin/brctl

# 允许用户管理 NBD 设备（可选）
$ACTUAL_USER ALL=(ALL) NOPASSWD: /sbin/modprobe nbd
$ACTUAL_USER ALL=(ALL) NOPASSWD: /usr/bin/nbd-client
EOF

        # 验证 sudoers 文件语法
        if visudo -c -f "$SUDOERS_FILE" > /dev/null 2>&1; then
            # 设置正确的权限
            chmod 440 "$SUDOERS_FILE"
            chown root:root "$SUDOERS_FILE"

            echo -e "${GREEN}✓${NC} Sudoers 配置已创建: $SUDOERS_FILE"
            echo ""

            # 显示配置内容
            echo "配置内容:"
            cat "$SUDOERS_FILE"
            echo ""

            echo -e "${GREEN}✓${NC} 配置完成"
            echo ""
            echo "用户 $ACTUAL_USER 现在可以免密码运行 Orchestrator"
            echo ""
            echo -e "${YELLOW}⚠${NC} 安全提示:"
            echo "  此配置仅适用于本地开发环境"
            echo "  生产环境应使用 Capabilities (选项 A)"
        else
            echo -e "${RED}✗${NC} Sudoers 文件语法错误"
            rm -f "$SUDOERS_FILE"
            exit 1
        fi
        ;;

    *)
        echo -e "${RED}✗${NC} 无效选择"
        exit 1
        ;;
esac

echo ""

# 额外配置：允许用户访问 /dev/kvm
echo "配置 /dev/kvm 访问权限..."
if [ -e /dev/kvm ]; then
    # 创建 udev 规则以自动设置 /dev/kvm 权限
    UDEV_RULE="/etc/udev/rules.d/99-kvm.rules"
    cat > "$UDEV_RULE" <<EOF
# E2B KVM 设备权限配置
# 自动生成于: $(date)

KERNEL=="kvm", GROUP="kvm", MODE="0666"
EOF

    echo -e "${GREEN}✓${NC} udev 规则已创建: $UDEV_RULE"

    # 重新加载 udev 规则
    udevadm control --reload-rules
    udevadm trigger

    # 立即设置当前权限
    chmod 666 /dev/kvm

    echo -e "${GREEN}✓${NC} /dev/kvm 权限已配置"
else
    echo -e "${YELLOW}⚠${NC} /dev/kvm 不存在，跳过权限配置"
fi
echo ""

# 总结
echo "=================================="
echo "Sudo 权限配置完成"
echo "=================================="
echo ""

if [ "$CHOICE" = "A" ] || [ "$CHOICE" = "a" ]; then
    if [ "$BINARY_EXISTS" = true ]; then
        echo -e "${GREEN}✓${NC} Orchestrator 已配置 capabilities"
        echo "运行方式: $ORCHESTRATOR_BIN (无需 sudo)"
    else
        echo -e "${YELLOW}⚠${NC} 需要在构建后设置 capabilities"
        echo "运行: /tmp/e2b-setup-capabilities.sh"
    fi
else
    echo -e "${GREEN}✓${NC} Sudo 免密码已配置"
    echo "运行方式: sudo $ORCHESTRATOR_BIN"
fi
echo ""
echo "下一步: 运行 05-setup-storage.sh 创建存储目录"
echo ""
