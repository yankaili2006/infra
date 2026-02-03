#!/bin/bash
#
# Firecracker Virtio MMIO 内核配置检查脚本
# 用于诊断 -22 (EINVAL) 错误
#

set -e

# 加载环境变量
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PCLOUD_HOME="$(cd "$SCRIPT_DIR/.." && pwd)"

# 尝试加载环境配置
if [ -f "$PCLOUD_HOME/config/env.sh" ]; then
    source "$PCLOUD_HOME/config/env.sh"
fi

# 设置默认值
PCLOUD_HOME="${PCLOUD_HOME:-/home/primihub/pcloud}"

echo "========================================="
echo "Firecracker Virtio MMIO 配置检查工具"
echo "========================================="
echo

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

KERNEL_DIR="$PCLOUD_HOME/infra/packages/fc-kernels"

echo "1. 检查可用的内核文件..."
echo "-----------------------------------"
ls -lh "$KERNEL_DIR"/ | grep "vmlinux"
echo

echo "2. 检查当前系统内核配置..."
echo "-----------------------------------"
if [ -f /proc/config.gz ]; then
    echo "✓ 找到 /proc/config.gz"
    echo
    echo "关键配置项检查："
    zcat /proc/config.gz | grep -E "CONFIG_VIRTIO|CONFIG_PCI" | grep -E "MMIO|BLK|NET|RING|PCI="
elif [ -f /boot/config-$(uname -r) ]; then
    echo "✓ 找到 /boot/config-$(uname -r)"
    echo
    echo "关键配置项检查："
    grep -E "CONFIG_VIRTIO|CONFIG_PCI" /boot/config-$(uname -r) | grep -E "MMIO|BLK|NET|RING|PCI="
else
    echo -e "${YELLOW}⚠ 无法找到系统内核配置文件${NC}"
    echo "  请检查 /proc/config.gz 或 /boot/config-<version>"
fi
echo

echo "3. 检查 Firecracker Guest 内核镜像..."
echo "-----------------------------------"

check_kernel() {
    local kernel_path="$1"
    local kernel_name=$(basename "$kernel_path")

    if [ ! -f "$kernel_path" ]; then
        echo -e "${RED}✗ $kernel_name 不存在${NC}"
        return 1
    fi

    echo -e "${GREEN}✓ $kernel_name 存在${NC}"

    # 检查文件类型
    file "$kernel_path"

    # 尝试从内核镜像中提取配置
    echo "  尝试提取嵌入的配置..."

    # 方法1: 使用 extract-ikconfig（如果存在）
    if command -v extract-ikconfig &> /dev/null; then
        config=$(extract-ikconfig "$kernel_path" 2>/dev/null)
        if [ -n "$config" ]; then
            echo "  ✓ 成功提取配置"
            echo "$config" > "/tmp/${kernel_name}.config"
            echo "  配置已保存到: /tmp/${kernel_name}.config"

            echo
            echo "  关键 Virtio MMIO 配置："
            echo "$config" | grep -E "CONFIG_VIRTIO.*MMIO|CONFIG_VIRTIO_BLK|CONFIG_VIRTIO_NET" || echo "    未找到 CONFIG_VIRTIO 配置"
            return 0
        fi
    fi

    # 方法2: 直接搜索 IKCFG 标记
    if strings "$kernel_path" 2>/dev/null | grep -q "IKCFG"; then
        echo "  ✓ 检测到嵌入的配置数据"
        # 提取并解压配置
        offset=$(grep -abo "IKCFG_ST" "$kernel_path" 2>/dev/null | head -1 | cut -d: -f1)
        if [ -n "$offset" ]; then
            dd if="$kernel_path" bs=1 skip=$((offset+8)) 2>/dev/null | zcat 2>/dev/null > "/tmp/${kernel_name}.config" || true
            if [ -s "/tmp/${kernel_name}.config" ]; then
                echo "  ✓ 配置已提取到: /tmp/${kernel_name}.config"
                echo
                echo "  关键 Virtio MMIO 配置："
                grep -E "CONFIG_VIRTIO.*MMIO|CONFIG_VIRTIO_BLK|CONFIG_VIRTIO_NET" "/tmp/${kernel_name}.config" || echo "    未找到 CONFIG_VIRTIO 配置"
                return 0
            fi
        fi
    fi

    echo -e "  ${YELLOW}⚠ 无法从内核镜像中提取配置${NC}"
    echo "    内核可能未启用 CONFIG_IKCONFIG"
    return 2
}

# 检查各个内核版本
for kernel in vmlinux-5.10.223 vmlinux-5.10.225 vmlinux-6.1.158 vmlinux-6.1.102; do
    kernel_path="$KERNEL_DIR/$kernel"
    if [ -d "$kernel_path" ]; then
        # 如果是目录，查找 .bin 文件
        kernel_path="$kernel_path/vmlinux.bin"
    fi

    if [ -f "$kernel_path" ]; then
        echo
        check_kernel "$kernel_path"
        echo "-----------------------------------"
    fi
done

echo
echo "4. Firecracker 已知行为说明"
echo "-----------------------------------"
echo "根据 Firecracker 官方文档和源代码："
echo
echo -e "${GREEN}✓ Firecracker 会自动在内核命令行末尾添加 virtio_mmio.device 参数${NC}"
echo "  示例: virtio_mmio.device=4K@0xd0000000:5"
echo
echo -e "${YELLOW}⚠ 这要求 Guest 内核必须启用以下配置：${NC}"
echo "  CONFIG_VIRTIO_MMIO=y              # Virtio MMIO 传输层支持"
echo "  CONFIG_VIRTIO_MMIO_CMDLINE_DEVICES=y  # ★ 关键配置 ★"
echo "  CONFIG_VIRTIO_BLK=y               # 块设备驱动"
echo "  CONFIG_VIRTIO_NET=y               # 网络设备驱动"
echo "  CONFIG_VIRTIO_RING=y              # Virtio ring 支持"
echo
echo -e "${RED}✗ 如果缺少 CONFIG_VIRTIO_MMIO_CMDLINE_DEVICES=y：${NC}"
echo "  - 内核将忽略命令行中的 virtio_mmio.device 参数"
echo "  - virtio_mmio_probe() 会返回 -22 (EINVAL)"
echo "  - 所有 Virtio 设备(网络、磁盘)都无法使用"
echo

echo "5. E2B 当前配置分析"
echo "-----------------------------------"
echo "当前 E2B 的内核启动参数配置 (infra/packages/orchestrator/internal/sandbox/fc/process.go):"
echo "  pci=off                    # 禁用 PCI 总线，强制使用 MMIO"
echo "  (Firecracker 自动添加)     # virtio_mmio.device=..."
echo
echo "E2B 依赖 Firecracker 自动注入 virtio_mmio.device 参数"
echo "因此 Guest 内核 MUST 启用 CONFIG_VIRTIO_MMIO_CMDLINE_DEVICES"
echo

echo "6. 建议的解决方案"
echo "-----------------------------------"
echo -e "${GREEN}方案 A: 使用 Firecracker 官方推荐的内核${NC}"
echo "  1. 下载官方内核："
echo "     wget https://github.com/firecracker-microvm/firecracker/releases/download/v1.12.1/vmlinux-5.10.bin"
echo "  2. 替换当前内核："
echo "     cp vmlinux-5.10.bin $KERNEL_DIR/vmlinux-5.10.223/vmlinux.bin"
echo
echo -e "${GREEN}方案 B: 重新编译内核并确保启用必要配置${NC}"
echo "  1. 获取 Firecracker 官方配置模板："
echo "     wget https://raw.githubusercontent.com/firecracker-microvm/firecracker/main/resources/guest_configs/microvm-kernel-x86_64-5.10.config"
echo "  2. 重点检查以下配置必须为 'y'："
echo "     CONFIG_VIRTIO_MMIO=y"
echo "     CONFIG_VIRTIO_MMIO_CMDLINE_DEVICES=y"
echo "     CONFIG_VIRTIO_BLK=y"
echo "     CONFIG_VIRTIO_NET=y"
echo "  3. 编译并替换内核"
echo
echo -e "${GREEN}方案 C: 临时测试 - 使用 5.10.225 内核${NC}"
echo "  如果 vmlinux-5.10.225 已经配置正确："
echo "     cd $KERNEL_DIR"
echo "     ln -sf vmlinux-5.10.225 vmlinux-5.10.223"
echo

echo "7. 验证步骤"
echo "-----------------------------------"
echo "修复后，请执行以下验证："
echo "  1. 重启 Firecracker VM 创建测试"
echo "  2. 检查日志中的 virtio_mmio 探测信息"
echo "  3. 确认没有 -22 (EINVAL) 错误"
echo

echo "========================================="
echo "检查完成"
echo "========================================="
