#!/bin/bash
# 从阿里云OSS恢复E2B模板文件

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

echo ""
echo "=========================================="
echo -e "${BOLD}从阿里云OSS恢复E2B模板${NC}"
echo "=========================================="
echo ""

# 加载OSS配置
if [ -f ~/pcloud/config/oss/oss_download_config.sh ]; then
    source ~/pcloud/config/oss/oss_download_config.sh
else
    echo -e "${YELLOW}⚠ OSS配置文件不存在，使用默认配置${NC}"
fi

# 配置
OSS_BUCKET="${OSS_BUCKET_NAME:-primihub}"
RESTORE_DIR="/home/primihub/e2b-storage/e2b-template-storage"

echo "OSS Bucket: ${OSS_BUCKET}"
echo "恢复目录: ${RESTORE_DIR}"
echo ""

# 检查ossutil是否安装
if ! command -v ossutil &> /dev/null && ! command -v ossutil64 &> /dev/null; then
    echo -e "${RED}✗ ossutil未安装${NC}"
    echo ""
    echo "请安装ossutil:"
    echo "  wget https://gosspublic.alicdn.com/ossutil/1.7.19/ossutil64 -O /usr/local/bin/ossutil64"
    echo "  chmod +x /usr/local/bin/ossutil64"
    exit 1
fi

# 使用ossutil或ossutil64
OSSUTIL_CMD="ossutil"
if command -v ossutil64 &> /dev/null; then
    OSSUTIL_CMD="ossutil64"
fi

echo -e "${GREEN}✓ ossutil已安装${NC}"
echo ""

# 1. 列出可用的模板备份
echo -e "${BLUE}[1/6] 列出可用的模板备份${NC}"
echo ""

OSS_TEMPLATE_PATH="e2b-templates"
echo "正在查询OSS路径: oss://${OSS_BUCKET}/${OSS_TEMPLATE_PATH}/"

BACKUPS=$(${OSSUTIL_CMD} ls "oss://${OSS_BUCKET}/${OSS_TEMPLATE_PATH}/" 2>/dev/null | grep "\.tar\.gz$" || true)

if [ -z "$BACKUPS" ]; then
    echo -e "${YELLOW}⚠ 未找到模板备份文件${NC}"
    echo ""
    echo "尝试列出所有可用路径:"
    ${OSSUTIL_CMD} ls "oss://${OSS_BUCKET}/" | head -20
    exit 1
fi

echo "找到以下备份:"
echo "$BACKUPS" | sort -r | nl
echo ""

# 2. 选择备份文件
echo -e "${BLUE}[2/6] 选择要恢复的备份${NC}"
echo ""
echo "1. 恢复最新的备份"
echo "2. 手动输入备份文件名"
read -p "请选择 (1/2): " choice

case $choice in
    1)
        LATEST_BACKUP=$(echo "$BACKUPS" | sort -r | head -1 | awk '{print $NF}')
        BACKUP_FILE=$(basename "${LATEST_BACKUP}")
        echo -e "${GREEN}选择最新的备份: ${BACKUP_FILE}${NC}"
        ;;
    2)
        read -p "请输入备份文件名 (例如: e2b_templates_20260201.tar.gz): " BACKUP_FILE
        ;;
    *)
        echo -e "${RED}✗ 无效的选择${NC}"
        exit 1
        ;;
esac

echo ""

# 3. 验证备份文件是否存在
echo -e "${BLUE}[3/6] 验证备份文件${NC}"
echo ""

OSS_PATH="${OSS_TEMPLATE_PATH}/${BACKUP_FILE}"
echo "检查: oss://${OSS_BUCKET}/${OSS_PATH}"

${OSSUTIL_CMD} stat "oss://${OSS_BUCKET}/${OSS_PATH}" > /dev/null 2>&1

if [ $? -ne 0 ]; then
    echo -e "${RED}✗ 备份文件不存在: ${BACKUP_FILE}${NC}"
    exit 1
fi

echo -e "${GREEN}✓ 备份文件存在${NC}"
echo ""

# 4. 下载备份文件
echo -e "${BLUE}[4/6] 下载备份文件${NC}"
echo ""

LOCAL_BACKUP="/tmp/${BACKUP_FILE}"
echo "下载到: ${LOCAL_BACKUP}"

${OSSUTIL_CMD} cp "oss://${OSS_BUCKET}/${OSS_PATH}" "${LOCAL_BACKUP}" --progress

if [ $? -eq 0 ]; then
    BACKUP_SIZE=$(du -h "${LOCAL_BACKUP}" | cut -f1)
    echo -e "${GREEN}✓ 下载成功 (${BACKUP_SIZE})${NC}"
else
    echo -e "${RED}✗ 下载失败${NC}"
    exit 1
fi

echo ""

# 5. 解压备份文件
echo -e "${BLUE}[5/6] 解压备份文件${NC}"
echo ""

# 创建恢复目录
mkdir -p "${RESTORE_DIR}"

echo "解压到: ${RESTORE_DIR}"
tar -xzf "${LOCAL_BACKUP}" -C "${RESTORE_DIR}"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ 解压成功${NC}"
else
    echo -e "${RED}✗ 解压失败${NC}"
    rm -f "${LOCAL_BACKUP}"
    exit 1
fi

echo ""

# 6. 验证恢复
echo -e "${BLUE}[6/6] 验证恢复结果${NC}"
echo ""

# 统计模板数量
TEMPLATE_COUNT=$(find "${RESTORE_DIR}" -mindepth 1 -maxdepth 1 -type d | wc -l)
echo "模板目录数量: ${TEMPLATE_COUNT}"

# 统计rootfs文件
ROOTFS_COUNT=$(find "${RESTORE_DIR}" -name "rootfs.ext4" | wc -l)
echo "rootfs.ext4 文件数量: ${ROOTFS_COUNT}"

# 统计总大小
TOTAL_SIZE=$(du -sh "${RESTORE_DIR}" | cut -f1)
echo "总大小: ${TOTAL_SIZE}"

echo ""

# 列出恢复的模板
if [ $TEMPLATE_COUNT -gt 0 ]; then
    echo "恢复的模板:"
    for template_dir in "${RESTORE_DIR}"/*; do
        if [ -d "$template_dir" ]; then
            template_id=$(basename "$template_dir")
            if [ -f "$template_dir/metadata.json" ]; then
                template_name=$(jq -r '.templateID // "unknown"' "$template_dir/metadata.json" 2>/dev/null || echo "unknown")
                rootfs_size=$(du -h "$template_dir/rootfs.ext4" 2>/dev/null | cut -f1 || echo "N/A")
                echo "  - $template_id ($template_name) - rootfs: $rootfs_size"
            else
                echo "  - $template_id (无metadata.json)"
            fi
        fi
    done
fi

echo ""

# 清理临时文件
echo "清理临时文件..."
rm -f "${LOCAL_BACKUP}"

echo ""
echo "=========================================="
echo -e "${GREEN}${BOLD}✓ 恢复完成${NC}"
echo "=========================================="
echo ""
echo "恢复目录: ${RESTORE_DIR}"
echo "模板数量: ${TEMPLATE_COUNT}"
echo "rootfs文件: ${ROOTFS_COUNT}"
echo "总大小: ${TOTAL_SIZE}"
echo ""
echo "下一步:"
echo "  1. 清理模板缓存: sudo rm -rf /home/primihub/e2b-storage/e2b-template-cache/*"
echo "  2. 重启orchestrator: nomad job restart orchestrator"
echo "  3. 测试模板: curl -X POST http://localhost:3000/sandboxes -H 'Content-Type: application/json' -H 'X-API-Key: ...' -d '{\"templateID\": \"base\", \"timeout\": 300}'"
echo ""
