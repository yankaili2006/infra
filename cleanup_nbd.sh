#!/bin/bash
set -e

# ==========================================
# NBD 清理与优化脚本
# 描述: 将 NBD 设备数量从默认的 4096 减少到 128，并清理日志
# ==========================================

TARGET_NBD_COUNT=128
CONF_FILE="/etc/modprobe.d/nbd.conf"

echo "=========================================="
echo "NBD Cleanup & Optimization"
echo "=========================================="

# 1. 停止相关服务
echo "1. Stopping Orchestrator if running..."
if pgrep -f "orchestrator" > /dev/null; then
    sudo pkill -f "orchestrator" || true
    echo "   - Orchestrator stopped"
else
    echo "   - Orchestrator not running"
fi

# 2. 卸载 NBD 模块
echo "2. Reloading NBD module..."
# 尝试卸载，如果失败（如在使用中），则警告
if lsmod | grep -q "^nbd"; then
    if sudo modprobe -r nbd; then
        echo "   - NBD module unloaded"
    else
        echo "   - Warning: Could not unload NBD module (devices in use?)"
        echo "   - Forcing disconnect of all NBD devices..."
        sudo pkill -f qemu-nbd || true
        sudo modprobe -r nbd || { echo "   - Failed to unload NBD module. Exiting."; exit 1; }
    fi
else
    echo "   - NBD module was not loaded"
fi

# 3. 配置持久化参数
echo "3. Configuring persistent limits..."
# 创建 modprobe 配置
echo "options nbd nbds_max=$TARGET_NBD_COUNT" | sudo tee "$CONF_FILE" > /dev/null
echo "   - $CONF_FILE updated (nbds_max=$TARGET_NBD_COUNT)"

# 4. 重新加载模块
echo "4. Loading NBD module..."
sudo modprobe nbd
echo "   - NBD module loaded"

# 5. 验证
COUNT=$(ls -1d /dev/nbd* 2>/dev/null | grep -v 'p[0-9]\+$' | wc -l)
echo "   - Current NBD device count: $COUNT"

# 6. 清理临时日志
echo "5. Cleaning up temporary logs..."
sudo rm -f /tmp/orchestrator*.log /tmp/client.log
echo "   - Temporary logs removed"

echo ""
echo "✅ Cleanup Complete! NBDs reduced to $TARGET_NBD_COUNT."
