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
echo -e "${BOLD}E2B 代码执行性能基准测试${NC}"
echo "=========================================="
echo ""

# 获取 API 端口
API_PORT=$(nomad alloc status $(nomad job allocs api 2>/dev/null | grep running | awk '{print $1}') 2>/dev/null | grep -A 10 "Port Label" | grep "http" | awk '{print $3}')

if [ -z "$API_PORT" ]; then
    echo -e "${RED}✗ 无法获取 API 端口${NC}"
    exit 1
fi

API_URL="http://localhost:${API_PORT}"
API_KEY="test-api-key"

echo "API URL: $API_URL"
echo ""

# 测试配置
ITERATIONS=10
TEMPLATE="code-interpreter-v5"

# 结果数组
declare -a CREATE_TIMES
declare -a EXEC_TIMES
declare -a DELETE_TIMES
declare -a TOTAL_TIMES

echo -e "${BLUE}[1/4] 运行 $ITERATIONS 次完整测试${NC}"
echo ""

for i in $(seq 1 $ITERATIONS); do
    echo -n "  测试 $i/$ITERATIONS: "

    # 记录开始时间
    START_TOTAL=$(date +%s%N)

    # 1. 创建沙箱
    START_CREATE=$(date +%s%N)
    RESPONSE=$(curl -s -X POST "$API_URL/v1/sandboxes" \
      -H "Content-Type: application/json" \
      -H "X-API-Key: $API_KEY" \
      -d "{\"template\": \"$TEMPLATE\"}")
    END_CREATE=$(date +%s%N)

    SANDBOX_ID=$(echo "$RESPONSE" | jq -r '.sandboxId // .id // empty')

    if [ -z "$SANDBOX_ID" ]; then
        echo -e "${RED}✗ 创建失败${NC}"
        continue
    fi

    # 2. 执行代码
    START_EXEC=$(date +%s%N)
    EXEC_RESPONSE=$(curl -s -X POST "$API_URL/v1/sandboxes/$SANDBOX_ID/execute" \
      -H "Content-Type: application/json" \
      -H "X-API-Key: $API_KEY" \
      -d '{"code": "print(sum(range(1000000)))"}')
    END_EXEC=$(date +%s%N)

    # 3. 删除沙箱
    START_DELETE=$(date +%s%N)
    curl -s -X DELETE "$API_URL/v1/sandboxes/$SANDBOX_ID" \
      -H "X-API-Key: $API_KEY" > /dev/null
    END_DELETE=$(date +%s%N)

    END_TOTAL=$(date +%s%N)

    # 计算时间（毫秒）
    CREATE_TIME=$(( (END_CREATE - START_CREATE) / 1000000 ))
    EXEC_TIME=$(( (END_EXEC - START_EXEC) / 1000000 ))
    DELETE_TIME=$(( (END_DELETE - START_DELETE) / 1000000 ))
    TOTAL_TIME=$(( (END_TOTAL - START_TOTAL) / 1000000 ))

    CREATE_TIMES+=($CREATE_TIME)
    EXEC_TIMES+=($EXEC_TIME)
    DELETE_TIMES+=($DELETE_TIME)
    TOTAL_TIMES+=($TOTAL_TIME)

    echo -e "${GREEN}✓${NC} 总计: ${TOTAL_TIME}ms (创建: ${CREATE_TIME}ms, 执行: ${EXEC_TIME}ms, 删除: ${DELETE_TIME}ms)"

    # 短暂延迟避免过载
    sleep 1
done

echo ""

# 计算统计数据
calculate_stats() {
    local arr=("$@")
    local sum=0
    local min=${arr[0]}
    local max=${arr[0]}

    for val in "${arr[@]}"; do
        sum=$((sum + val))
        if [ $val -lt $min ]; then min=$val; fi
        if [ $val -gt $max ]; then max=$val; fi
    done

    local avg=$((sum / ${#arr[@]}))

    # 计算中位数
    IFS=$'\n' sorted=($(sort -n <<<"${arr[*]}"))
    unset IFS
    local mid=$((${#sorted[@]} / 2))
    local median=${sorted[$mid]}

    echo "$avg $min $max $median"
}

echo -e "${BLUE}[2/4] 创建沙箱性能统计${NC}"
echo ""
read avg min max median <<< $(calculate_stats "${CREATE_TIMES[@]}")
echo "  平均时间: ${avg}ms"
echo "  最小时间: ${min}ms"
echo "  最大时间: ${max}ms"
echo "  中位数:   ${median}ms"
echo ""

echo -e "${BLUE}[3/4] 代码执行性能统计${NC}"
echo ""
read avg min max median <<< $(calculate_stats "${EXEC_TIMES[@]}")
echo "  平均时间: ${avg}ms"
echo "  最小时间: ${min}ms"
echo "  最大时间: ${max}ms"
echo "  中位数:   ${median}ms"
echo ""

echo -e "${BLUE}[4/4] 总体性能统计${NC}"
echo ""
read avg min max median <<< $(calculate_stats "${TOTAL_TIMES[@]}")
echo "  平均时间: ${avg}ms"
echo "  最小时间: ${min}ms"
echo "  最大时间: ${max}ms"
echo "  中位数:   ${median}ms"
echo ""

# 性能评估
echo "=========================================="
echo -e "${BOLD}性能评估${NC}"
echo "=========================================="
echo ""

read create_avg _ _ _ <<< $(calculate_stats "${CREATE_TIMES[@]}")
read exec_avg _ _ _ <<< $(calculate_stats "${EXEC_TIMES[@]}")
read total_avg _ _ _ <<< $(calculate_stats "${TOTAL_TIMES[@]}")

if [ $create_avg -lt 2000 ]; then
    echo -e "  沙箱创建: ${GREEN}优秀${NC} (<2s)"
elif [ $create_avg -lt 5000 ]; then
    echo -e "  沙箱创建: ${YELLOW}良好${NC} (2-5s)"
else
    echo -e "  沙箱创建: ${RED}需要优化${NC} (>5s)"
fi

if [ $exec_avg -lt 500 ]; then
    echo -e "  代码执行: ${GREEN}优秀${NC} (<500ms)"
elif [ $exec_avg -lt 1000 ]; then
    echo -e "  代码执行: ${YELLOW}良好${NC} (500ms-1s)"
else
    echo -e "  代码执行: ${RED}需要优化${NC} (>1s)"
fi

if [ $total_avg -lt 3000 ]; then
    echo -e "  总体性能: ${GREEN}优秀${NC} (<3s)"
elif [ $total_avg -lt 6000 ]; then echo -e "  总体性能: ${YELLOW}良好${NC} (3-6s)"
else
    echo -e "  总体性能: ${RED}需要优化${NC} (>6s)"
fi

echo ""

# 保存结果
REPORT_FILE="/tmp/e2b-benchmark-$(date +%Y%m%d-%H%M%S).txt"
{
    echo "E2B 代码执行性能基准测试报告"
    echo "=============================="
    echo ""
    echo "测试时间: $(date)"
    echo "测试次数: $ITERATIONS"
    echo "模板: $TEMPLATE"
    echo ""
    echo "创建沙箱性能:"
    echo "  平均: ${create_avg}ms"
    echo ""
    echo "代码执行性能:"
    echo "  平均: ${exec_avg}ms"
    echo ""
    echo "总体性能:"
    echo "  平均: ${total_avg}ms"
    echo ""
    echo "详细数据:"
    echo "  创建时间: ${CREATE_TIMES[*]}"
    echo "  执行时间: ${EXEC_TIMES[*]}"
    echo "  总计时间: ${TOTAL_TIMES[*]}"
} > "$REPORT_FILE"

echo "详细报告已保存到: $REPORT_FILE"
echo ""
