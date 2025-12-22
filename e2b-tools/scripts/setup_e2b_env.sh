#!/bin/bash
# E2B环境快速设置脚本

set -e

echo "============================================================"
echo "🔧 E2B Python环境设置"
echo "============================================================"
echo ""

# 创建虚拟环境
if [ ! -d ~/e2b-env ]; then
    echo "1️⃣ 创建Python虚拟环境..."
    python3 -m venv ~/e2b-env
    echo "   ✅ 虚拟环境已创建: ~/e2b-env"
else
    echo "1️⃣ ✅ 虚拟环境已存在: ~/e2b-env"
fi
echo ""

# 激活虚拟环境
echo "2️⃣ 激活虚拟环境..."
source ~/e2b-env/bin/activate
echo "   ✅ 虚拟环境已激活"
echo ""

# 安装/升级pip
echo "3️⃣ 安装pip..."
if ! python3 -m pip --version > /dev/null 2>&1; then
    echo "   下载get-pip.py..."
    curl -sS https://bootstrap.pypa.io/get-pip.py -o /tmp/get-pip.py
    python3 /tmp/get-pip.py
fi
echo "   ✅ pip已就绪"
echo ""

# 安装E2B SDK
echo "4️⃣ 安装E2B SDK和依赖..."
pip install -q e2b requests grpcio grpcio-tools
echo "   ✅ SDK已安装"
echo ""

# 设置环境变量
echo "5️⃣ 设置环境变量..."
export E2B_API_KEY="e2b_53ae1fed82754c17ad8077fbc8bcdd90"
export E2B_API_URL="http://localhost:3000"
echo "   ✅ 环境变量已设置"
echo ""

# 测试SDK
echo "6️⃣ 测试E2B SDK..."
python3 -c "from e2b import Sandbox; print('   ✅ E2B SDK导入成功!')"
echo ""

echo "============================================================"
echo "🎉 环境设置完成!"
echo "============================================================"
echo ""
echo "📝 下一步:"
echo "   1. 激活环境: source ~/e2b-env/bin/activate"
echo "   2. 运行测试: python3 /tmp/test_e2b_complete.py"
echo ""
echo "💡 提示:"
echo "   - 每次新终端需要激活: source ~/e2b-env/bin/activate"
echo "   - 退出环境: deactivate"
echo ""
