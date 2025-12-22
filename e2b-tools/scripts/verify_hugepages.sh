#!/bin/bash
echo "=========================================="
echo "E2B Orchestrator Hugepages 配置验证"
echo "=========================================="
echo ""
echo "1. 系统 Hugepages 配置:"
echo "   总页数: $(cat /proc/sys/vm/nr_hugepages) ($(( $(cat /proc/sys/vm/nr_hugepages) * 2 ))MB)"
echo "   空闲页数: $(grep HugePages_Free /proc/meminfo | awk '{print $2}')"
echo ""
echo "2. Orchestrator 服务状态:"
if ps aux | grep -q "bin/orchestrator" | grep -v grep; then
    echo "   ✓ 运行中 (PID: $(pgrep -f bin/orchestrator))"
else
    echo "   ✗ 未运行"
fi
echo ""
echo "3. Orchestrator Hugepages 环境变量:"
cat /proc/$(pgrep -f bin/orchestrator)/environ | tr '\0' '\n' | grep HUGE | while read line; do
    echo "   ✓ $line"
done
echo ""
echo "4. 服务列表:"
echo "   - Consul: $(ps aux | grep -c "bin/consul" | grep -v grep)x 进程"
echo "   - Nomad: $(ps aux | grep -c "bin/nomad" | grep -v grep)x 进程"
echo "   - Redis: $(docker ps | grep -c redis) 容器"
echo "   - PostgreSQL: $(docker ps | grep -c postgres) 容器"
echo ""
echo "=========================================="
echo "配置验证完成"
echo "=========================================="
echo ""
echo "下一步: 测试 VM 创建"
echo ""
echo "测试命令示例:"
echo "  # 需要先部署 API 服务"
echo "  nomad job run local-deploy/jobs/api.hcl"
echo ""
echo "  # 然后创建测试 VM"
echo '  curl -X POST http://localhost:3000/sandboxes \'
echo '    -H "Content-Type: application/json" \'
echo '    -H "X-API-Key: <your-api-key>" \'
echo '    -d '"'"'{"templateID": "base", "timeout": 300}'"'"
echo ""
