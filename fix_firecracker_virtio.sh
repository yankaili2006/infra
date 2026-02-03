#!/bin/bash
#
# Firecracker Virtio MMIO 问题快速修复脚本
# 使用 Firecracker 官方内核替换当前内核
#

set -e

# 加载环境变量配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PCLOUD_HOME="$(cd "$SCRIPT_DIR/.." && pwd)"
if [ -f "$PCLOUD_HOME/config/env.sh" ]; then
    source "$PCLOUD_HOME/config/env.sh"
else
    PCLOUD_HOME="${PCLOUD_HOME:-/home/primihub/pcloud}"
fi

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置
KERNEL_VERSION="5.10"
FIRECRACKER_VERSION="v1.12.1"
DOWNLOAD_URL="https://github.com/firecracker-microvm/firecracker/releases/download/${FIRECRACKER_VERSION}/vmlinux-${KERNEL_VERSION}.bin"
TARGET_DIR="$PCLOUD_HOME/infra/packages/fc-kernels/vmlinux-5.10.223"
TARGET_FILE="${TARGET_DIR}/vmlinux.bin"
BACKUP_FILE="${TARGET_FILE}.backup-$(date +%Y%m%d-%H%M%S)"
TMP_DOWNLOAD="/tmp/vmlinux-${KERNEL_VERSION}-official.bin"

echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}Firecracker Virtio MMIO 快速修复工具${NC}"
echo -e "${BLUE}=========================================${NC}"
echo

# 1. 检查当前状态
echo -e "${YELLOW}步骤 1/6: 检查当前内核状态${NC}"
echo "-----------------------------------"
if [ -f "$TARGET_FILE" ]; then
    echo -e "${GREEN}✓ 找到当前内核: $TARGET_FILE${NC}"
    ls -lh "$TARGET_FILE"
    file "$TARGET_FILE"
else
    echo -e "${RED}✗ 未找到内核文件: $TARGET_FILE${NC}"
    exit 1
fi
echo

# 2. 下载官方内核
echo -e "${YELLOW}步骤 2/6: 下载 Firecracker 官方内核${NC}"
echo "-----------------------------------"
echo "下载地址: $DOWNLOAD_URL"

if [ -f "$TMP_DOWNLOAD" ]; then
    echo "临时文件已存在，跳过下载"
else
    if curl -L --fail --progress-bar -o "$TMP_DOWNLOAD" "$DOWNLOAD_URL"; then
        echo -e "${GREEN}✓ 下载成功${NC}"
    else
        echo -e "${RED}✗ 下载失败${NC}"
        echo "请检查网络连接或代理设置"
        exit 1
    fi
fi

# 验证下载
echo "验证下载的文件..."
if file "$TMP_DOWNLOAD" | grep -q "ELF 64-bit"; then
    echo -e "${GREEN}✓ 文件格式验证成功${NC}"
    file "$TMP_DOWNLOAD"
else
    echo -e "${RED}✗ 下载的文件格式不正确${NC}"
    file "$TMP_DOWNLOAD"
    rm -f "$TMP_DOWNLOAD"
    exit 1
fi
echo

# 3. 备份当前内核
echo -e "${YELLOW}步骤 3/6: 备份当前内核${NC}"
echo "-----------------------------------"
if sudo cp "$TARGET_FILE" "$BACKUP_FILE"; then
    echo -e "${GREEN}✓ 备份成功: $BACKUP_FILE${NC}"
else
    echo -e "${RED}✗ 备份失败${NC}"
    exit 1
fi
echo

# 4. 部署新内核
echo -e "${YELLOW}步骤 4/6: 部署新内核${NC}"
echo "-----------------------------------"
if sudo cp "$TMP_DOWNLOAD" "$TARGET_FILE"; then
    echo -e "${GREEN}✓ 部署成功${NC}"
else
    echo -e "${RED}✗ 部署失败${NC}"
    echo "正在恢复备份..."
    sudo cp "$BACKUP_FILE" "$TARGET_FILE"
    exit 1
fi

# 设置权限
if sudo chown primihub:primihub "$TARGET_FILE"; then
    echo -e "${GREEN}✓ 权限设置成功${NC}"
else
    echo -e "${YELLOW}⚠ 权限设置失败，但可能不影响使用${NC}"
fi

echo
ls -lh "$TARGET_FILE"
file "$TARGET_FILE"
echo

# 5. 重启 Orchestrator 服务
echo -e "${YELLOW}步骤 5/6: 重启 Orchestrator 服务${NC}"
echo "-----------------------------------"
if command -v nomad &> /dev/null; then
    echo "检查 Orchestrator 服务状态..."
    if nomad job status orchestrator &> /dev/null; then
        echo "重启 Orchestrator..."
        if nomad job restart orchestrator; then
            echo -e "${GREEN}✓ Orchestrator 重启成功${NC}"
            sleep 3

            # 检查服务状态
            echo "检查服务健康状态..."
            nomad job status orchestrator | head -20
        else
            echo -e "${YELLOW}⚠ Orchestrator 重启失败，请手动重启${NC}"
        fi
    else
        echo -e "${YELLOW}⚠ Orchestrator 服务未运行，请手动启动${NC}"
    fi
else
    echo -e "${YELLOW}⚠ nomad 命令不可用，请手动重启 Orchestrator${NC}"
fi
echo

# 6. 验证修复
echo -e "${YELLOW}步骤 6/6: 验证修复${NC}"
echo "-----------------------------------"
echo "执行以下命令测试 VM 创建："
echo
echo -e "${BLUE}curl -X POST http://localhost:3000/sandboxes \\${NC}"
echo -e "${BLUE}  -H \"Content-Type: application/json\" \\${NC}"
echo -e "${BLUE}  -H \"X-API-Key: e2b_53ae1fed82754c17ad8077fbc8bcdd90\" \\${NC}"
echo -e "${BLUE}  -d '{\"templateID\": \"base-template-000-0000-0000-000000000001\", \"timeout\": 300}'${NC}"
echo
echo "如果返回 sandbox ID（而非 500 错误），说明修复成功！"
echo

# 7. 总结
echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}修复完成总结${NC}"
echo -e "${BLUE}=========================================${NC}"
echo
echo -e "${GREEN}✓ 新内核已部署: $TARGET_FILE${NC}"
echo -e "${GREEN}✓ 备份已保存: $BACKUP_FILE${NC}"
echo
echo "如果遇到问题，可以恢复备份："
echo -e "${YELLOW}sudo cp $BACKUP_FILE $TARGET_FILE${NC}"
echo -e "${YELLOW}nomad job restart orchestrator${NC}"
echo
echo "详细诊断报告: $PCLOUD_HOME/infra/FIRECRACKER_VIRTIO_EINVAL_DIAGNOSIS.md"
echo

# 清理临时文件（可选）
read -p "是否删除临时下载文件? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    rm -f "$TMP_DOWNLOAD"
    echo -e "${GREEN}✓ 临时文件已删除${NC}"
fi

echo
echo -e "${GREEN}修复流程完成！${NC}"
