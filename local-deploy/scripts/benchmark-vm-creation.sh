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
echo -e "${BOLD}E2B VM 创建性能基准测试${NC}"
echo "=========================================="
echo ""

# 配置
API_URL="http://localhost:3000"
API_KEY="${E2B_API_KEY:-e2b_53ae1fed82754c17ad8077fbc8bcdd90}"
TEMPLATE_ID="${TEMPLATE_ID:-base}"
ITERATIONS="${ITERATIONS:-10}"

echo "测试配置:"
echo "  API URL: $API_URL"
echo "  模板: $TEMPLATE_ID"
echo "  迭代次数: $ITERATIONS"
echo ""

# 检查 API 健康
echo "检查 API 健康状态..."
if ! curl -s "$API_URL/health" > /dev/null; then
    echo -e "${RED}✗ API 不可用${NC}"
    exit 1
fi
echo -e "${GREEN}✓ API 健康${NC}"
echo ""

# 测试 VM 创建
echo "开始测试 VM 创建性能..."
echo ""

TOTAL_TIME=0
SUCCESS_COUNT=0
FAILED_COUNT=0
SANDBOX_IDS=()

for i in $(seq 1 $ITERATIONS); do
    echo -n "迭代 $i/$ITERATIONS: "

    START=$(date +%s.%N)

    RESPONSE=$(curl -s -X POST "$API_URL/sandboxes" \
      -H "Content-Type: application/json" \
      -H "X-API-Key: $API_KEY" \
      -d "{\"templateID\": \"$TEMPLATE_ID\", \"timeout\": 300}")

    END=$(date +%s.%N)
    DURATION=$(echo "$END - $START" | bc)

    # 检查是否成功
    SANDBOX_ID=$(echo "$RESPONSE" | jq -r '.sandboxID // empty')

    if [ -n "$SANDBOX_ID" ] && [ "$SANDBOX_ID" != "null" ]; then
        TOTAL_TIME=$(echo "$TOTAL_TIME + $DURATION" | bc)
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        SANDBOX_IDS+=("$SANDBOX_ID")
        echo -e "${GREEN}✓${NC} ${DURATION}s (Sandbox: $SANDBOX_ID)"
    else
        FAILED_COUNT=$((FAILED_COUNT + 1))
        ERROR=$(echo "$RESPONSE" | jq -r '.message // "Unknown error"')
        echo -e "${RED}✗${NC} 失败 - $ERROR"
    fi

    sleep 1
done

echo ""
echo "=========================================="
echo -e "${BOLD}测试结果${NC}"
echo "=========================================="
echo ""

if [ $SUCCESS_COUNT -gt 0 ]; then
    AVG_TIME=$(echo "scale=3; $TOTAL_TIME / $SUCCESS_COUNT" | bc)
    echo -e "${GREEN}成功: $SUCCESS_COUNT/$ITERATIONS${NC}"
    echo -e "${BLUE}平均创建时间: ${AVG_TIME}s${NC}"
    echo ""

    # 性能评估
    if (( $(echo "$AVG_TIME < 2.0" | bc -l) )); then
        echo -e "${GREEN}✓ 性能优秀 (< 2s)${NC}"
    elif (( $(echo "$AVG_TIME < 5.0" | bc -l) )); then
        echo -e "${YELLOW}⚠ 性能良好 (2-5s)${NC}"
    else
        echo -e "${RED}✗ 性能需要优化 (> 5s)${NC}"
    fi
else
    echo -e "${RED}所有测试失败${NC}"
fi

if [ $FAILED_COUNT -gt 0 ]; then
    echo -e "${RED}失败: $FAILED_COUNT/$ITERATIONS${NC}"
fi

echo ""

# 清理创建的 sandbox
if [ ${#SANDBOX_IDS[@]} -gt 0 ]; then
    echo "清理测试 sandbox..."
    for SANDBOX_ID in "${SANDBOX_IDS[@]}"; do
        curl -s -X DELETE "$API_URL/sandboxes/$SANDBOX_ID" \
          -H "X-API-Key: $API_KEY" > /dev/null
        echo "  已删除: $SANDBOX_ID"
    done
    echo -e "${GREEN}✓ 清理完成${NC}"
fi

echo ""
