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
echo -e "${BOLD}E2B 系统资源分析${NC}"
echo "=========================================="
echo ""

# 1. 系统总体资源
echo -e "${BLUE}[1/6] 系统总体资源${NC}"
echo ""
echo "CPU 信息:"
lscpu | grep -E "^CPU\(s\)|^Model name|^CPU MHz"
echo ""
echo "内存信息:"
free -h
echo ""
echo "磁盘使用:"
df -h | grep -E "Filesystem|/dev/sd|/dev/nvme"
echo ""

# 2. Docker 容器资源使用
echo -e "${BLUE}[2/6] Docker 容器资源${NC}"
echo ""
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.NetIO}}\t{{.BlockIO}}"
echo ""

# 3. Nomad Jobs 资源使用
echo -e "${BLUE}[3/6] Nomad Jobs 资源${NC}"
echo ""
if command -v nomad &> /dev/null && nomad node status &> /dev/null 2>&1; then
    echo "Nomad Jobs 状态:"
    nomad job status 2>/dev/null | head -20
    echo ""

    echo "API Job 资源分配:"
    nomad job status api 2>/dev/null | grep -A 5 "Allocations"
    echo ""

    echo "Orchestrator Job 资源分配:"
    nomad job status orchestrator 2>/dev/null | grep -A 5 "Allocations"
    echo ""
else
    echo -e "${YELLOW}⚠${NC} Nomad 未运行或不可用"
fi
echo ""

# 4. 进程级资源分析
echo -e "${BLUE}[4/6] 关键进程资源使用${NC}"
echo ""
echo "Firecracker 进程:"
ps aux | grep firecracker | grep -v grep | awk '{printf "PID: %-8s CPU: %-6s MEM: %-6s CMD: %s\n", $2, $3"%", $4"%", $11}' | head -10
echo ""

echo "Consul 进程:"
ps aux | grep consul | grep -v grep | awk '{printf "PID: %-8s CPU: %-6s MEM: %-6s\n", $2, $3"%", $4"%"}'
echo ""

echo "Nomad 进程:"
ps aux | grep nomad | grep -v grep | awk '{printf "PID: %-8s CPU: %-6s MEM: %-6s\n", $2, $3"%", $4"%"}'
echo ""

echo "Node.js 进程 (Fragments/Surf):"
ps aux | grep "node.*next" | grep -v grep | awk '{printf "PID: %-8s CPU: %-6s MEM: %-6s CMD: %s\n", $2, $3"%", $4"%", $11" "$12}' | head -5
echo ""

# 5. 网络使用情况
echo -e "${BLUE}[5/6] 网络资源${NC}"
echo ""
echo "网络接口统计:"
ip -s link show | grep -E "^[0-9]+:|RX:|TX:" | head -20
echo ""

echo "活跃网络连接 (前10):"
netstat -tunap 2>/dev/null | grep ESTABLISHED | awk '{print $4, $5, $7}' | sort | uniq -c | sort -rn | head -10
echo ""

echo "监听端口:"
netstat -tlnp 2>/dev/null | grep LISTEN | awk '{printf "%-25s %-20s %s\n", $4, $7, $1}' | sort -u | head -15
echo ""

# 6. 资源使用建议
echo -e "${BLUE}[6/6] 资源优化建议${NC}"
echo ""

# 检查内存使用率
MEM_USAGE=$(free | grep Mem | awk '{printf "%.0f", $3/$2 * 100}')
if [ "$MEM_USAGE" -gt 80 ]; then
    echo -e "${RED}⚠ 内存使用率过高: ${MEM_USAGE}%${NC}"
    echo "  建议: 考虑增加系统内存或限制 VM 数量"
else
    echo -e "${GREEN}✓ 内存使用正常: ${MEM_USAGE}%${NC}"
fi
echo ""

# 检查 Firecracker VM 数量
VM_COUNT=$(ps aux | grep firecracker | grep -v grep | wc -l)
echo "当前运行的 VM 数量: $VM_COUNT"
if [ "$VM_COUNT" -gt 10 ]; then
    echo -e "${YELLOW}⚠ VM 数量较多，可能影响性能${NC}"
    echo "  建议: 清理不使用的 sandbox"
fi
echo ""

# 检查磁盘使用
DISK_USAGE=$(df -h / | tail -1 | awk '{print $5}' | sed 's/%//')
if [ "$DISK_USAGE" -gt 80 ]; then
    echo -e "${RED}⚠ 磁盘使用率过高: ${DISK_USAGE}%${NC}"
    echo "  建议: 清理模板缓存或日志文件"
else
    echo -e "${GREEN}✓ 磁盘使用正常: ${DISK_USAGE}%${NC}"
fi
echo ""

# 检查 Docker 容器数量
CONTAINER_COUNT=$(docker ps -q 2>/dev/null | wc -l)
echo "运行中的 Docker 容器: $CONTAINER_COUNT"
echo ""

echo "==========================================="
echo -e "${BOLD}优化建议总结${NC}"
echo "==========================================="
echo ""
echo "1. 定期清理不使用的 sandbox:"
echo "   curl -X GET http://localhost:3000/sandboxes -H 'X-API-Key: ...' | jq"
echo ""
echo "2. 清理模板缓存 (如果磁盘空间不足):"
echo "   sudo rm -rf /home/primihub/e2b-storage/e2b-template-cache/*"
echo ""
echo "3. 监控日志文件大小:"
echo "   du -sh /home/primihub/e2b-storage/nomad-local/alloc/*/alloc/logs/"
echo ""
echo "4. 查看详细资源监控:"
echo "   http://localhost:9090 (Prometheus)"
echo "   http://localhost:53000 (Grafana)"
echo ""
