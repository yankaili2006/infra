#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

echo ""
echo "=========================================="
echo -e "${BOLD}E2B 模板验证${NC}"
echo "=========================================="
echo ""

# 脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PCLOUD_HOME="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# 加载环境变量
if [ -f "$PCLOUD_HOME/config/env.sh" ]; then
    source "$PCLOUD_HOME/config/env.sh"
fi

# 设置默认值（使用实际存储路径）
E2B_STORAGE_PATH="${E2B_STORAGE_PATH:-/mnt/sdb/e2b-storage}"
TEMPLATE_STORAGE="$E2B_STORAGE_PATH/e2b-template-storage"

echo -e "${BLUE}[1/3] 检查模板存储目录${NC}"
echo ""

if [ ! -d "$TEMPLATE_STORAGE" ]; then
    echo -e "${RED}✗ 模板存储目录不存在: $TEMPLATE_STORAGE${NC}"
    exit 1
fi

echo -e "${GREEN}✓ 模板存储目录存在${NC}"
echo "  路径: $TEMPLATE_STORAGE"
echo ""

# 统计模板
TEMPLATE_COUNT=$(find "$TEMPLATE_STORAGE" -mindepth 1 -maxdepth 1 -type d | wc -l)
echo "  找到 $TEMPLATE_COUNT 个模板"
echo ""

echo -e "${BLUE}[2/3] 验证模板完整性${NC}"
echo ""

VALID_TEMPLATES=0
INVALID_TEMPLATES=0

for template_dir in "$TEMPLATE_STORAGE"/*; do
    if [ ! -d "$template_dir" ]; then
        continue
    fi

    template_id=$(basename "$template_dir")
    echo "模板: $template_id"

    # 检查 rootfs.ext4
    if [ -f "$template_dir/rootfs.ext4" ]; then
        rootfs_size=$(du -h "$template_dir/rootfs.ext4" | cut -f1)
        echo -e "  ${GREEN}✓${NC} rootfs.ext4 存在 ($rootfs_size)"
  else
        echo -e "  ${RED}✗${NC} rootfs.ext4 缺失"
        INVALID_TEMPLATES=$((INVALID_TEMPLATES + 1))
        continue
    fi

    # 检查 metadata.json
    if [ -f "$template_dir/metadata.json" ]; then
        echo -e "  ${GREEN}✓${NC} metadata.json 存在"

        # 验证 JSON 格式
        if jq empty "$template_dir/metadata.json" 2>/dev/null; then
            echo -e "  ${GREEN}✓${NC} metadata.json 格式有效"

            # 显示模板信息
            template_name=$(jq -r '.templateID // "unknown"' "$template_dir/metadata.json")
            echo "  模板名称: $template_name"
        else
            echo -e "  ${YELLOW}⚠${NC} metadata.json 格式无效"
        fi
    else
        echo -e "  ${YELLOW}⚠${NC} metadata.json 缺失"
    fi

    VALID_TEMPLATES=$((VALID_TEMPLATES + 1))
    echo ""
done

echo -e "${BLUE}[3/3] 测试 API 模板列表${NC}"
echo ""

# 获取 API 端口
if command -v nomad &> /dev/null && nomad node status &> /dev/null 2>&1; then
    API_ALLOC=$(nomad job allocs api 2>/dev/null | grep running | awk '{print $1}' | head -1)
    if [ -n "$API_ALLOC" ]; then
        API_PORT=$(nomad alloc status "$API_ALLOC" 2>/dev/null | grep -A 10 "Port Label" | grep "http" | awk '{print $3}')

        if [ -n "$API_PORT" ]; then
            echo "API 端口: $API_PORT"
            echo ""

            # 测试模板列表 API
            echo "测试 GET /v1/templates..."
            RESPONSE=$(curl -s -w "\n%{http_code}" "http://localhost:$API_PORT/v1/templates" \
                -H "X-API-Key: test-api-key")

            HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
            BODY=$(echo "$RESPONSE" | head -n-1)

            if [ "$HTTP_CODE" = "200" ]; then
                echo -e "${GREEN}✓ API 响应成功${NC}"
                echo ""
                echo "可用模板:"
                echo "$BODY" | jq -r '.[] | "  - \(.templateID) (\(.alias // "no alias"))"' 2>/dev/null || echo "$BODY"
            else
                echo -e "${YELLOW}⚠ API 响应码: $HTTP_CODE${NC}"
                echo "响应: $BODY"
            fi
        else
            echo -e "${YELLOW}⚠ 无法获取 API 端口${NC}"
        fi
    else
        echo -e "${YELLOW}⚠ API 服务未运行${NC}"
    fi
else
    echo -e "${YELLOW}⚠ Nomad 未运行${NC}"
fi

echo ""
echo "=========================================="
echo -e "${BOLD}验证结果${NC}"
echo "=========================================="
echo ""
echo "有效模板: ${GREEN}$VALID_TEMPLATES${NC}"
echo "无效模板: ${RED}$INVALID_TEMPLATES${NC}"
echo ""

if [ $VALID_TEMPLATES -gt 0 ] && [ $INVALID_TEMPLATES -eq 0 ]; then
    echo -e "${GREEN}${BOLD}✓ 所有模板验证通过${NC}"
    exit 0
elif [ $VALID_TEMPLATES -gt 0 ]; then
    echo -e "${YELLOW}${BOLD}⚠ 部分模板验证通过${NC}"
    exit 0
else
    echo -e "${RED}${BOLD}✗ 没有有效的模板${NC}"
    exit 1
fi
