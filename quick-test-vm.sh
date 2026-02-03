#!/bin/bash
# Firecracker VM 快速测试脚本

set -e

# 加载环境变量配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PCLOUD_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
if [ -f "$PCLOUD_ROOT/config/env.sh" ]; then
    source "$PCLOUD_ROOT/config/env.sh"
fi

# 设置路径（使用环境变量或默认值）
PCLOUD_HOME="${PCLOUD_HOME:-/home/primihub/pcloud}"

echo "=== Firecracker VM 快速测试 ==="
echo

# 1. 检查内核
echo "1. 检查内核文件..."
KERNEL="$PCLOUD_HOME/infra/packages/fc-kernels/vmlinux-5.10.223/vmlinux.bin"
if [ ! -f "$KERNEL" ]; then
    echo "✗ 内核文件不存在: $KERNEL"
    exit 1
fi
echo "  文件类型:"
file "$KERNEL" | sed 's/^/    /'
echo "  文件大小:"
ls -lh "$KERNEL" | sed 's/^/    /'
echo

# 2. 检查服务
echo "2. 检查服务状态..."
echo "  Consul:"
if consul members 2>&1 | grep -q "alive"; then
    echo "    ✓ Consul 运行中"
else
    echo "    ✗ Consul 未运行"
fi

echo "  Nomad:"
if nomad node status 2>&1 | grep -q "ready"; then
    echo "    ✓ Nomad 运行中"
else
    echo "    ✗ Nomad 未运行"
fi

echo "  API:"
if curl -s --max-time 2 http://localhost:3000/health 2>&1 | grep -q "ok"; then
    echo "    ✓ API 响应正常"
else
    echo "    ✗ API 未响应"
fi

echo "  Orchestrator:"
if curl -s --max-time 2 http://localhost:5008/health 2>&1 | grep -q "ok"; then
    echo "    ✓ Orchestrator 响应正常"
else
    echo "    ✗ Orchestrator 未响应"
fi
echo

# 3. 测试 VM 创建
echo "3. 测试 VM 创建..."
RESPONSE=$(curl -s --max-time 30 -X POST http://localhost:3000/sandboxes \
  -H "Content-Type: application/json" \
  -H "X-API-Key: e2b_53ae1fed82754c17ad8077fbc8bcdd90" \
  -d '{"templateID": "base-template-000-0000-0000-000000000001", "timeout": 300}' 2>&1)

echo "  API 响应:"
if command -v jq &> /dev/null; then
    echo "$RESPONSE" | jq . 2>/dev/null | sed 's/^/    /' || echo "$RESPONSE" | sed 's/^/    /'
else
    echo "$RESPONSE" | sed 's/^/    /'
fi
echo

# 4. 检查结果
echo "4. 分析结果..."
if echo "$RESPONSE" | grep -q "sandboxID"; then
    echo "  ✓ VM 创建成功！"

    if command -v jq &> /dev/null; then
        SANDBOX_ID=$(echo "$RESPONSE" | jq -r '.sandboxID' 2>/dev/null)
        echo "    Sandbox ID: $SANDBOX_ID"
    fi

    echo
    echo "  Firecracker 进程:"
    if ps aux | grep firecracker | grep -v grep; then
        echo "    ✓ Firecracker 进程运行中"
    else
        echo "    ⚠ 未找到 Firecracker 进程（可能已退出）"
    fi

    echo
    echo "  ✅ 内核修复成功！Virtio MMIO 设备探测正常。"

elif echo "$RESPONSE" | grep -qi "error\|500"; then
    echo "  ✗ VM 创建失败"
    echo
    echo "  可能的原因："
    echo "    1. 内核仍缺少 CONFIG_VIRTIO_MMIO_CMDLINE_DEVICES"
    echo "    2. 内核文件损坏或格式不正确"
    echo "    3. 模板文件缺失或损坏"
    echo
    echo "  建议操作："
    echo "    - 查看 Orchestrator 日志以获取详细错误"
    echo "    - 检查是否出现 'virtio_mmio: probe failed with error -22'"
    echo "    - 考虑使用官方 Firecracker 内核"
else
    echo "  ? 未知响应类型"
    echo "    请手动检查服务状态和日志"
fi

echo
echo "=== 测试完成 ==="
echo
echo "如需查看详细日志："
echo "  - Orchestrator: nomad alloc logs <alloc-id> orchestrator"
echo "  - API: nomad alloc logs <alloc-id> api"
echo "  - 或查看: tail -f ${E2B_STORAGE_PATH:-$PCLOUD_HOME/../e2b-storage}/logs/*.log"
