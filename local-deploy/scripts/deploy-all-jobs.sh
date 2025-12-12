#!/bin/bash
set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "=========================================="
echo "E2B 本地部署 - 部署 Nomad Jobs"
echo "=========================================="
echo ""

# Job 文件目录
JOBS_DIR="/home/primihub/pcloud/infra/local-deploy/jobs"

if [ ! -d "$JOBS_DIR" ]; then
    echo -e "${RED}✗${NC} Jobs 目录不存在: $JOBS_DIR"
    exit 1
fi

# 检查 Nomad 是否运行
if ! nomad node status &> /dev/null; then
    echo -e "${RED}✗${NC} Nomad 未运行"
    echo "请先运行: bash start-nomad.sh"
    exit 1
fi

# 定义 Job 部署顺序（有依赖关系）
declare -a JOBS=(
    "orchestrator.hcl"
    "template-manager.hcl"
    "api.hcl"
    "client-proxy.hcl"
)

echo "将部署以下 Jobs:"
for job in "${JOBS[@]}"; do
    echo "  - $job"
done
echo ""

# 部署统计
DEPLOYED=0
FAILED=0

# 部署每个 Job
for job_file in "${JOBS[@]}"; do
    JOB_PATH="$JOBS_DIR/$job_file"
    JOB_NAME="${job_file%.hcl}"

    echo "=========================================="
    echo -e "${BLUE}部署: $JOB_NAME${NC}"
    echo "=========================================="
    echo ""

    if [ ! -f "$JOB_PATH" ]; then
        echo -e "${RED}✗${NC} Job 文件不存在: $JOB_PATH"
        FAILED=$((FAILED + 1))
        echo ""
        continue
    fi

    # 验证 Job 配置
    echo "验证 Job 配置..."
    if ! nomad job validate "$JOB_PATH"; then
        echo -e "${RED}✗${NC} Job 配置无效"
        FAILED=$((FAILED + 1))
        echo ""
        continue
    fi
    echo -e "${GREEN}✓${NC} 配置有效"
    echo ""

    # 检查 Job 是否已存在
    if nomad job status "$JOB_NAME" &> /dev/null; then
        echo -e "${YELLOW}⚠${NC} Job 已存在: $JOB_NAME"
        read -p "是否重新部署? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "跳过 $JOB_NAME"
            echo ""
            continue
        fi
    fi

    # 运行 Job
    echo "运行 Job..."
    if nomad job run "$JOB_PATH"; then
        echo -e "${GREEN}✓${NC} $JOB_NAME 已部署"
        DEPLOYED=$((DEPLOYED + 1))

        # 等待 Job 启动
        echo -n "等待 allocations"
        MAX_WAIT=30
        COUNT=0
        while [ $COUNT -lt $MAX_WAIT ]; do
            ALLOCS=$(nomad job status "$JOB_NAME" 2>/dev/null | grep -c "running" || echo "0")
            if [ "$ALLOCS" -gt 0 ]; then
                echo -e " ${GREEN}✓${NC}"
                break
            fi
            echo -n "."
            sleep 2
            COUNT=$((COUNT + 2))
        done

        if [ $COUNT -ge $MAX_WAIT ]; then
            echo -e " ${YELLOW}⚠ 超时（Job 可能仍在启动中）${NC}"
        fi

        # 显示 Job 状态
        echo ""
        nomad job status "$JOB_NAME" | head -n 20
    else
        echo -e "${RED}✗${NC} $JOB_NAME 部署失败"
        FAILED=$((FAILED + 1))
    fi

    echo ""
done

# 显示所有 Jobs 状态
echo "=========================================="
echo "所有 Jobs 状态"
echo "=========================================="
echo ""
nomad job status

echo ""

# 显示所有 allocations
echo "=========================================="
echo "Allocations 状态"
echo "=========================================="
echo ""
nomad alloc status || true

echo ""

# 总结
echo "=========================================="
echo "部署总结"
echo "=========================================="
echo ""

TOTAL=${#JOBS[@]}
echo "总计: $TOTAL"
echo "成功: $DEPLOYED"
echo "失败: $FAILED"
echo ""

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ 所有 Jobs 部署成功${NC}"
else
    echo -e "${YELLOW}⚠ 部分 Jobs 部署失败${NC}"
    echo ""
    echo "查看失败的 Job:"
    echo "  nomad job status <job-name>"
    echo "  nomad alloc logs <alloc-id>"
fi

echo ""
echo "常用命令:"
echo "  nomad job status            # 查看所有 Jobs"
echo "  nomad job status <name>     # 查看特定 Job"
echo "  nomad alloc logs -f <id>    # 查看日志"
echo "  nomad job stop <name>       # 停止 Job"
echo ""
