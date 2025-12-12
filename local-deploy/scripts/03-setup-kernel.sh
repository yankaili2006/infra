#!/bin/bash
set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=================================="
echo "E2B 本地部署 - 内核配置"
echo "=================================="
echo ""

# 检查是否为 root 用户
if [ "$EUID" -ne 0 ]; then
    echo -e "${YELLOW}⚠${NC} 此脚本需要 sudo 权限来配置内核"
    echo "请使用: sudo $0"
    exit 1
fi

# 1. 加载 KVM 模块
echo "1. 加载 KVM 内核模块..."

# 检测 CPU 虚拟化支持
if grep -qE 'vmx|svm' /proc/cpuinfo; then
    if grep -q 'vmx' /proc/cpuinfo; then
        KVM_MODULE="kvm_intel"
        echo "检测到 Intel CPU (VMX)"
    elif grep -q 'svm' /proc/cpuinfo; then
        KVM_MODULE="kvm_amd"
        echo "检测到 AMD CPU (SVM)"
    fi

    # 加载 kvm 基础模块
    if ! lsmod | grep -q "^kvm "; then
        modprobe kvm
        echo -e "${GREEN}✓${NC} kvm 模块已加载"
    else
        echo -e "${GREEN}✓${NC} kvm 模块已存在"
    fi

    # 加载特定 CPU 的 kvm 模块
    if ! lsmod | grep -q "^$KVM_MODULE "; then
        modprobe "$KVM_MODULE"
        echo -e "${GREEN}✓${NC} $KVM_MODULE 模块已加载"
    else
        echo -e "${GREEN}✓${NC} $KVM_MODULE 模块已存在"
    fi

    # 验证 /dev/kvm
    if [ -e /dev/kvm ]; then
        echo -e "${GREEN}✓${NC} /dev/kvm 设备已创建"

        # 设置 /dev/kvm 权限
        chmod 666 /dev/kvm
        echo -e "${GREEN}✓${NC} /dev/kvm 权限已设置"
    else
        echo -e "${RED}✗${NC} /dev/kvm 设备未创建"
        echo "请检查:"
        echo "  1. BIOS 中是否启用了虚拟化"
        echo "  2. 内核是否支持 KVM"
        exit 1
    fi
else
    echo -e "${RED}✗${NC} CPU 不支持硬件虚拟化"
    echo "请在 BIOS 中启用 Intel VT-x 或 AMD-V"
    exit 1
fi
echo ""

# 2. 加载 NBD 模块（Network Block Device）
echo "2. 加载 NBD 内核模块..."
if ! lsmod | grep -q "^nbd "; then
    modprobe nbd nbds_max=64
    echo -e "${GREEN}✓${NC} nbd 模块已加载 (最大设备数: 64)"
else
    echo -e "${GREEN}✓${NC} nbd 模块已存在"

    # 检查 nbds_max 参数
    NBD_MAX=$(cat /sys/module/nbd/parameters/nbds_max 2>/dev/null || echo "0")
    if [ "$NBD_MAX" -lt 64 ]; then
        echo -e "${YELLOW}⚠${NC} nbd nbds_max 参数较小: $NBD_MAX (推荐: >= 64)"
        echo "重新加载模块..."
        rmmod nbd
        modprobe nbd nbds_max=64
        echo -e "${GREEN}✓${NC} nbd 模块已重新加载"
    else
        echo "  nbds_max: $NBD_MAX"
    fi
fi
echo ""

# 3. 配置 Hugepages（可选但推荐）
echo "3. 配置 Hugepages..."
CURRENT_HUGEPAGES=$(cat /proc/sys/vm/nr_hugepages)
REQUIRED_HUGEPAGES=2048

echo "  当前 Hugepages: $CURRENT_HUGEPAGES"
echo "  推荐 Hugepages: $REQUIRED_HUGEPAGES"

if [ "$CURRENT_HUGEPAGES" -lt "$REQUIRED_HUGEPAGES" ]; then
    echo "设置 Hugepages 为 $REQUIRED_HUGEPAGES..."
    sysctl -w vm.nr_hugepages=$REQUIRED_HUGEPAGES
    echo -e "${GREEN}✓${NC} Hugepages 已配置"

    # 验证
    CURRENT_HUGEPAGES=$(cat /proc/sys/vm/nr_hugepages)
    if [ "$CURRENT_HUGEPAGES" -eq "$REQUIRED_HUGEPAGES" ]; then
        echo -e "${GREEN}✓${NC} Hugepages 配置成功: $CURRENT_HUGEPAGES"
    else
        echo -e "${YELLOW}⚠${NC} Hugepages 配置部分成功: $CURRENT_HUGEPAGES (目标: $REQUIRED_HUGEPAGES)"
        echo "可能是由于内存不足或内存碎片化"
    fi
else
    echo -e "${GREEN}✓${NC} Hugepages 已充足"
fi
echo ""

# 4. 配置网络参数
echo "4. 配置网络参数..."

# 启用 IP 转发
sysctl -w net.ipv4.ip_forward=1
echo -e "${GREEN}✓${NC} IPv4 转发已启用"

# 禁用 IPv6（可选，某些情况下可能需要）
# sysctl -w net.ipv6.conf.all.disable_ipv6=1
# echo -e "${GREEN}✓${NC} IPv6 已禁用"

# 配置 iptables 相关参数
sysctl -w net.bridge.bridge-nf-call-iptables=1 2>/dev/null || true
sysctl -w net.bridge.bridge-nf-call-ip6tables=1 2>/dev/null || true
echo -e "${GREEN}✓${NC} 网桥 iptables 调用已启用"

# 增加文件描述符限制
sysctl -w fs.file-max=65536
echo -e "${GREEN}✓${NC} 文件描述符限制已增加"

# 增加 inotify 监视限制
sysctl -w fs.inotify.max_user_watches=524288
sysctl -w fs.inotify.max_user_instances=512
echo -e "${GREEN}✓${NC} inotify 限制已增加"
echo ""

# 5. 持久化配置
echo "5. 持久化内核配置..."

SYSCTL_CONF="/etc/sysctl.d/99-e2b-local.conf"

cat > "$SYSCTL_CONF" <<EOF
# E2B 本地部署内核参数配置
# 自动生成于: $(date)

# Hugepages
vm.nr_hugepages = $REQUIRED_HUGEPAGES

# 网络配置
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1

# 文件系统限制
fs.file-max = 65536
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 512
EOF

echo -e "${GREEN}✓${NC} sysctl 配置已保存到: $SYSCTL_CONF"
echo ""

# 6. 持久化模块加载
echo "6. 持久化模块加载配置..."

MODULES_CONF="/etc/modules-load.d/e2b-local.conf"

cat > "$MODULES_CONF" <<EOF
# E2B 本地部署内核模块配置
# 自动生成于: $(date)

kvm
$KVM_MODULE
nbd
EOF

echo -e "${GREEN}✓${NC} 模块配置已保存到: $MODULES_CONF"
echo ""

# 7. 配置 NBD 模块参数
echo "7. 配置 NBD 模块参数..."

NBD_CONF="/etc/modprobe.d/nbd.conf"

cat > "$NBD_CONF" <<EOF
# E2B NBD 模块配置
# 自动生成于: $(date)

options nbd nbds_max=64
EOF

echo -e "${GREEN}✓${NC} NBD 配置已保存到: $NBD_CONF"
echo ""

# 8. 验证配置
echo "8. 验证配置..."

echo "已加载的内核模块:"
lsmod | grep -E "kvm|nbd"

echo ""
echo "Hugepages 状态:"
grep -i huge /proc/meminfo | head -n3

echo ""
echo "网络配置:"
sysctl net.ipv4.ip_forward net.bridge.bridge-nf-call-iptables 2>/dev/null || true
echo ""

# 9. 总结
echo "=================================="
echo "内核配置完成"
echo "=================================="
echo ""
echo -e "${GREEN}✓${NC} KVM 模块已加载并持久化"
echo -e "${GREEN}✓${NC} NBD 模块已加载并持久化"
echo -e "${GREEN}✓${NC} 网络参数已配置并持久化"
echo -e "${GREEN}✓${NC} Hugepages 已配置并持久化"
echo ""
echo "配置文件:"
echo "  - $SYSCTL_CONF"
echo "  - $MODULES_CONF"
echo "  - $NBD_CONF"
echo ""
echo "下一步: 运行 04-setup-sudo.sh 配置 sudo 权限"
echo ""
