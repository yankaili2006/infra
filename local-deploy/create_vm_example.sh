#!/bin/bash
# E2B 本地环境 - 创建虚拟机示例脚本

set -e

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "=========================================="
echo "E2B 虚拟机创建示例"
echo "=========================================="
echo ""

# API 配置
API_URL="http://localhost:3000"
API_KEY="e2b_53ae1fed82754c17ad8077fbc8bcdd90"

echo "1. 检查服务状态..."
echo "   API: $API_URL"
echo ""

# 检查 Orchestrator
if timeout 3 curl -s http://localhost:5008/health | grep -q "healthy"; then
    echo -e "${GREEN}✓${NC} Orchestrator 运行正常"
else
    echo -e "${RED}✗${NC} Orchestrator 未运行"
    exit 1
fi

# 检查 API
if timeout 3 curl -s http://localhost:3000/health > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} API 服务响应正常"
else
    echo -e "${YELLOW}⚠${NC} API 服务可能未完全就绪"
fi

echo ""
echo "2. 查看可用的环境模板..."
echo ""

# 列出所有模板 (envs)
TEMPLATES=$(docker exec local-dev-postgres-1 psql -U postgres -d postgres -t -c "SELECT id FROM envs;" 2>/dev/null | xargs)

if [ -z "$TEMPLATES" ]; then
    echo -e "${YELLOW}⚠${NC} 当前没有可用的环境模板"
    echo ""
    echo "要创建虚拟机，您需要："
    echo "  1. 首先创建一个环境模板（template/env）"
    echo "  2. 然后从该模板创建沙箱（sandbox）实例"
    echo ""
    echo "示例：使用 E2B SDK 创建模板"
    echo ""
    echo "Python 示例:"
    cat << 'EOF'
    from e2b import Sandbox

    # 设置环境变量
    export E2B_API_KEY="e2b_53ae1fed82754c17ad8077fbc8bcdd90"
    export E2B_API_URL="http://localhost:3000"

    # 创建沙箱
    sandbox = Sandbox(template="base")  # 需要先有 base 模板

    # 执行命令
    result = sandbox.run_code("print('Hello from E2B VM!')")
    print(result)

    # 关闭沙箱
    sandbox.close()
EOF
    echo ""
    echo "或者使用 curl 直接调用 API："
    echo ""
    echo "创建沙箱："
    cat << EOF
    curl -X POST http://localhost:3000/sandboxes \\
      -H "Content-Type: application/json" \\
      -H "X-API-Key: e2b_53ae1fed82754c17ad8077fbc8bcdd90" \\
      -d '{
        "templateID": "base",
        "timeout": 300
      }'
EOF
    echo ""
else
    echo -e "${GREEN}✓${NC} 找到 $(echo $TEMPLATES | wc -w) 个模板"
    echo "   模板 ID: $TEMPLATES"
    echo ""
    echo "3. 您可以使用以下命令创建虚拟机："
    echo ""
    for template_id in $TEMPLATES; do
        echo "   使用模板 '$template_id':"
        cat << EOF
    curl -X POST http://localhost:3000/sandboxes \\
      -H "Content-Type: application/json" \\
      -H "X-API-Key: e2b_53ae1fed82754c17ad8077fbc8bcdd90" \\
      -d '{
        "templateID": "$template_id",
        "timeout": 300
      }'
EOF
        echo ""
    done
fi

echo ""
echo "=========================================="
echo "服务访问地址"
echo "=========================================="
echo ""
echo "Nomad UI:      http://100.64.0.23:4646/ui"
echo "Consul UI:     http://100.64.0.23:8500/ui"
echo "API:           http://localhost:3000"
echo "Orchestrator:  http://localhost:5008"
echo "Client Proxy:  http://localhost:3002"
echo ""
echo "查看 Nomad Jobs:"
echo "  nomad job status"
echo ""
echo "查看虚拟机进程:"
echo "  ps aux | grep firecracker"
echo ""
