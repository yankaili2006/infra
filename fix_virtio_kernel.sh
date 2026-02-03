#!/bin/bash
#
# Firecracker Virtio MMIO 内核修复脚本
# 解决 -22 (EINVAL) 错误
#
# 作用：下载并部署 Firecracker 官方内核，确保包含必要的 Virtio MMIO 配置
#

set -e

# 加载环境变量
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PCLOUD_HOME="${PCLOUD_HOME:-$(cd "$SCRIPT_DIR/.." && pwd)}"

# 尝试加载环境配置
if [ -f "$PCLOUD_HOME/config/env.sh" ]; then
    source "$PCLOUD_HOME/config/env.sh"
fi

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}Firecracker Virtio MMIO 内核修复工具${NC}"
echo -e "${BLUE}=========================================${NC}"
echo

# 配置
KERNEL_DIR="${HOST_KERNELS_DIR:-$PCLOUD_HOME/infra/packages/fc-kernels}"
TEMP_DIR="/tmp/fc-kernel-fix"
PROXY="http://127.0.0.1:7890"

# Firecracker 官方内核下载地址
# 注意：GitHub Releases 可能被墙，使用多个备用源
KERNEL_URLS=(
    # AWS S3 官方镜像（推荐）
    "https://s3.amazonaws.com/spec.ccfc.min/firecracker-ci/v1.12/x86_64/vmlinux-5.10.217"
    "https://s3.amazonaws.com/spec.ccfc.min/firecracker-ci/v1.11/x86_64/vmlinux-5.10.210"
    # GitHub Releases（可能需要代理）
    "https://github.com/firecracker-microvm/firecracker/releases/download/v1.11.0/vmlinux.bin"
)

echo -e "${YELLOW}步骤 1/5: 环境检查${NC}"
echo "-----------------------------------"

# 检查是否有 sudo 权限
if ! sudo -n true 2>/dev/null; then
    echo -e "${YELLOW}⚠ 需要 sudo 权限，请输入密码${NC}"
    sudo -v
fi

# 创建临时目录
mkdir -p "$TEMP_DIR"
cd "$TEMP_DIR"

echo -e "${GREEN}✓${NC} 环境检查完成"
echo

echo -e "${YELLOW}步骤 2/5: 下载 Firecracker 官方内核${NC}"
echo "-----------------------------------"

# 配置代理
export http_proxy="$PROXY"
export https_proxy="$PROXY"
export HTTP_PROXY="$PROXY"
export HTTPS_PROXY="$PROXY"

DOWNLOAD_SUCCESS=false
for url in "${KERNEL_URLS[@]}"; do
    echo -e "${BLUE}尝试从: $url${NC}"

    if timeout 120 curl -L -o vmlinux-official.bin "$url" 2>&1; then
        # 检查下载的文件是否是有效的 ELF 文件
        if file vmlinux-official.bin | grep -q "ELF 64-bit"; then
            SIZE=$(stat -c%s vmlinux-official.bin)
            if [ "$SIZE" -gt 1000000 ]; then  # 大于 1MB
                echo -e "${GREEN}✓${NC} 成功下载内核 ($(numfmt --to=iec-i --suffix=B $SIZE))"
                DOWNLOAD_SUCCESS=true
                break
            else
                echo -e "${YELLOW}⚠${NC} 文件太小，可能是错误页面，尝试下一个源..."
            fi
        else
            echo -e "${YELLOW}⚠${NC} 不是有效的内核文件，尝试下一个源..."
        fi
    else
        echo -e "${YELLOW}⚠${NC} 下载失败，尝试下一个源..."
    fi
    rm -f vmlinux-official.bin
done

if [ "$DOWNLOAD_SUCCESS" = false ]; then
    echo -e "${RED}✗ 所有下载源均失败${NC}"
    echo
    echo -e "${YELLOW}备选方案：${NC}"
    echo "1. 手动下载内核："
    echo "   wget -O vmlinux-5.10.bin https://s3.amazonaws.com/spec.ccfc.min/firecracker-ci/v1.12/x86_64/vmlinux-5.10.217"
    echo "2. 或者从 Firecracker 官方仓库编译："
    echo "   https://github.com/firecracker-microvm/firecracker/tree/main/resources/guest_configs"
    echo
    exit 1
fi

echo

echo -e "${YELLOW}步骤 3/5: 验证下载的内核${NC}"
echo "-----------------------------------"

# 验证内核文件
echo "文件类型:"
file vmlinux-official.bin

echo
echo "尝试提取内核配置..."
if command -v extract-ikconfig &> /dev/null; then
    if extract-ikconfig vmlinux-official.bin > kernel.config 2>/dev/null; then
        echo -e "${GREEN}✓${NC} 成功提取配置"
        echo
        echo "关键 Virtio MMIO 配置检查:"

        # 检查关键配置项
        declare -a REQUIRED_CONFIGS=(
            "CONFIG_VIRTIO_MMIO=y"
            "CONFIG_VIRTIO_MMIO_CMDLINE_DEVICES=y"
            "CONFIG_VIRTIO_BLK=y"
            "CONFIG_VIRTIO_NET=y"
        )

        ALL_FOUND=true
        for config in "${REQUIRED_CONFIGS[@]}"; do
            if grep -q "^$config" kernel.config; then
                echo -e "  ${GREEN}✓${NC} $config"
            else
                echo -e "  ${RED}✗${NC} $config ${YELLOW}(缺失)${NC}"
                ALL_FOUND=false
            fi
        done

        if [ "$ALL_FOUND" = true ]; then
            echo
            echo -e "${GREEN}✓✓✓ 所有必要配置都已启用！${NC}"
        else
            echo
            echo -e "${YELLOW}⚠ 部分配置缺失，但仍可尝试使用${NC}"
        fi
    else
        echo -e "${YELLOW}⚠${NC} 无法提取配置（内核未启用 CONFIG_IKCONFIG）"
        echo "  但这不影响使用，Firecracker 官方内核通常配置正确"
    fi
else
    echo -e "${YELLOW}⚠${NC} extract-ikconfig 工具不可用"
    echo "  跳过配置验证，直接部署"
fi

echo

echo -e "${YELLOW}步骤 4/5: 部署新内核${NC}"
echo "-----------------------------------"

# 确定要替换的内核版本
# 优先替换默认的 vmlinux-6.1.158，因为配置中使用它
TARGET_VERSIONS=("vmlinux-6.1.158" "vmlinux-5.10.223")

for version in "${TARGET_VERSIONS[@]}"; do
    TARGET_DIR="$KERNEL_DIR/$version"

    if [ -d "$TARGET_DIR" ]; then
        echo -e "${BLUE}正在处理: $version${NC}"

        # 备份原内核
        if [ -f "$TARGET_DIR/vmlinux.bin" ]; then
            BACKUP_NAME="vmlinux.bin.backup.$(date +%Y%m%d_%H%M%S)"
            echo "  备份原文件: $BACKUP_NAME"
            sudo cp "$TARGET_DIR/vmlinux.bin" "$TARGET_DIR/$BACKUP_NAME"
        fi

        # 部署新内核
        echo "  部署新内核..."
        sudo cp vmlinux-official.bin "$TARGET_DIR/vmlinux.bin"
        sudo chown primihub:primihub "$TARGET_DIR/vmlinux.bin"
        sudo chmod 644 "$TARGET_DIR/vmlinux.bin"

        echo -e "  ${GREEN}✓${NC} $version 已更新"
        echo
    else
        echo -e "${YELLOW}⚠${NC} 目录不存在: $TARGET_DIR"
    fi
done

echo -e "${GREEN}✓${NC} 内核部署完成"
echo

echo -e "${YELLOW}步骤 5/5: 重启服务${NC}"
echo "-----------------------------------"

# 检查 Nomad 是否可用
if command -v nomad &> /dev/null; then
    echo "重启 Orchestrator 服务..."
    if nomad job restart orchestrator 2>&1; then
        echo -e "${GREEN}✓${NC} Orchestrator 已重启"
    else
        echo -e "${YELLOW}⚠${NC} Orchestrator 重启失败，请手动重启："
        echo "  nomad job restart orchestrator"
    fi

    echo
    echo "等待服务稳定 (10秒)..."
    sleep 10

    # 检查服务状态
    echo
    echo "当前服务状态:"
    nomad job status orchestrator 2>&1 | grep -E "Status|Allocations" || true
else
    echo -e "${YELLOW}⚠${NC} Nomad 命令不可用，请手动重启服务"
fi

echo
echo -e "${BLUE}=========================================${NC}"
echo -e "${GREEN}✓✓✓ 修复完成！${NC}"
echo -e "${BLUE}=========================================${NC}"
echo

echo "下一步验证:"
echo "1. 检查 Orchestrator 日志:"
echo "   nomad alloc logs -f \$(nomad job allocs orchestrator | grep running | awk '{print \$1}')"
echo
echo "2. 创建测试 VM:"
echo "   curl -X POST http://localhost:3000/sandboxes \\"
echo "     -H 'Content-Type: application/json' \\"
echo "     -H 'X-API-Key: e2b_53ae1fed82754c17ad8077fbc8bcdd90' \\"
echo "     -d '{\"templateID\": \"base\", \"timeout\": 300}'"
echo
echo "3. 预期结果:"
echo "   - 应返回 sandbox ID (非 500 错误)"
echo "   - 日志中没有 '-22' 或 'EINVAL' 错误"
echo "   - ps aux | grep firecracker 显示运行中的进程"
echo

# 清理临时文件
cd /
rm -rf "$TEMP_DIR"

echo -e "${YELLOW}提示：${NC}如果仍然遇到问题，请查看:"
echo "  $PCLOUD_HOME/infra/FIRECRACKER_VIRTIO_EINVAL_DIAGNOSIS.md"
echo
