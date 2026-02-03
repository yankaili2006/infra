#!/bin/bash
# E2B 模板信息查询工具
# 使用 E2B API 获取和显示模板信息

set -e

E2B_API_KEY="${E2B_API_KEY:-e2b_53ae1fed82754c17ad8077fbc8bcdd90}"
E2B_API_URL="${E2B_API_URL:-http://localhost:3000}"

# 颜色定义
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo "=========================================="
echo "  E2B 模板信息查询"
echo "=========================================="
echo ""

# 检查 API 连接
echo "1. 检查 E2B API 连接..."
HEALTH=$(curl -s "${E2B_API_URL}/health")

if [ -z "$HEALTH" ]; then
  echo -e "${RED}❌ E2B API 不可访问${NC}"
  exit 1
fi

echo -e "${GREEN}✓ E2B API 连接正常${NC}"
echo ""

# 获取模板列表
echo "2. 获取模板列表..."
echo ""

TEMPLATES=$(curl -s "${E2B_API_URL}/templates" -H "X-API-Key: ${E2B_API_KEY}")

if [ -z "$TEMPLATES" ]; then
  echo -e "${RED}❌ 无法获取模板列表${NC}"
  exit 1
fi

# 解析并显示模板信息
echo -e "${BLUE}可用模板:${NC}"
echo "------------------------------------------"

echo "$TEMPLATES" | jq -r '.[] | @json' | while read -r template; do
  TEMPLATE_ID=$(echo "$template" | jq -r '.templateID')
  ALIAS=$(echo "$template" | jq -r '.aliases[0] // "无"')
  CPU=$(echo "$template" | jq -r '.cpuCount // "N/A"')
  MEMORY=$(echo "$template" | jq -r '.memoryMB // "N/A"')
  PUBLIC=$(echo "$template" | jq -r '.public // "未知"')
  BUILD_ID=$(echo "$template" | jq -r '.builds[0].id // "无"')

  PUBLIC_STATUS="私有"
  if [ "$PUBLIC" = "true" ]; then
    PUBLIC_STATUS="公有"
  fi

  echo -e "${GREEN}模板 ID:${NC} $TEMPLATE_ID"
  echo -e "  ${BLUE}别名:${NC}     $ALIAS"
  echo -e "  ${BLUE}状态:${NC}     $PUBLIC_STATUS"
  echo -e "  ${BLUE}CPU:${NC}      $CPU 核心"
  echo -e "  ${BLUE}内存:${NC}     $MEMORY MB"
  echo -e "  ${BLUE}Build ID:${NC} $BUILD_ID"
  echo ""
done

# 按 ID 检查特定模板
if [ -n "$1" ]; then
  echo "=========================================="
  echo -e "${YELLOW}详细信息: $1${YELLOW}"
  echo "=========================================="
  echo ""

  TEMPLATE_DETAIL=$(curl -s "${E2B_API_URL}/templates/$1" -H "X-API-Key: ${E2B_API_KEY}")

  if [ -z "$TEMPLATE_DETAIL" ] || echo "$TEMPLATE_DETAIL" | grep -q "error"; then
    echo -e "${RED}❌ 模板 $1 不存在${NC}"
    exit 1
  fi

  echo "$TEMPLATE_DETAIL" | jq '.'
fi

# 显示 Fragments 模板映射
echo "=========================================="
echo -e "${YELLOW}Fragments 模板映射${YELLOW}"
echo "=========================================="
echo ""

PCLOUD_HOME="${PCLOUD_HOME:-/home/primihub/pcloud}"
FRAGMENTS_ROUTE="$PCLOUD_HOME/infra/fragments/app/api/sandbox/route.ts"

if [ -f "$FRAGMENTS_ROUTE" ]; then
  echo "文件: $FRAGMENTS_ROUTE"
  echo ""
  grep -A 5 "const templateMap" "$FRAGMENTS_ROUTE" | sed 's/^/  /'
  echo ""
fi

# 显示当前运行中的沙箱
echo "=========================================="
echo -e "${YELLOW}当前运行中的沙箱${YELLOW}"
echo "=========================================="
echo ""

SANDBOXES=$(curl -s "${E2B_API_URL}/sandboxes" -H "X-API-Key: ${E2B_API_KEY}")

if [ "$SANDBOXES" = "[]" ] || [ -z "$SANDBOXES" ]; then
  echo -e "${YELLOW}没有运行中的沙箱${NC}"
else
  echo "$SANDBOXES" | jq -r '.[] | @json' | while read -r sandbox; do
    SBX_ID=$(echo "$sandbox" | jq -r '.sandboxID')
    TEMPLATE_ID=$(echo "$sandbox" | jq -r '.templateID')
    ALIAS=$(echo "$sandbox" | jq -r '.alias // "无"')
    CPU=$(echo "$sandbox" | jq -r '.cpuCount // "N/A"')
    MEMORY=$(echo "$sandbox" | jq -r '.memoryMB // "N/A"')
    STARTED=$(echo "$sandbox" | jq -r '.startedAt // "未知"')
    ENDS=$(echo "$sandbox" | jq -r '.endAt // "未知"')

    echo -e "${GREEN}沙箱 ID:${NC} $SBX_ID"
    echo -e "  ${BLUE}模板:${NC}   $TEMPLATE_ID ($ALIAS)"
    echo -e "  ${BLUE}资源:${NC}   ${CPU} CPU, ${MEMORY} MB"
    echo -e "  ${BLUE}启动:${NC}   $STARTED"
    echo -e "  ${BLUE}结束:${NC}   $ENDS"
    echo ""
  done
fi

echo "=========================================="
echo -e "${GREEN}查询完成${NC}"
echo "=========================================="
echo ""
echo "用法:"
echo "  $0                     # 查看所有模板"
echo "  $0 <template_id>       # 查看特定模板详情"
echo ""
