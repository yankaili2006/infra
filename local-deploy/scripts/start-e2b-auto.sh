#!/bin/bash
set -e

# 加载环境变量
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PCLOUD_HOME="$(cd "$SCRIPT_DIR/../../.." && pwd)"
if [ -f "$PCLOUD_HOME/config/env.sh" ]; then
    source "$PCLOUD_HOME/config/env.sh"
fi

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

echo ""
echo "=========================================="
echo -e "${BOLD}E2B 本地部署 - 自动启动${NC}"
echo "=========================================="
echo ""

# 目标版本
NOMAD_VERSION="1.8.4"
CONSUL_VERSION="1.19.2"

# 步骤 1: 检查 Consul 和 Nomad
echo -e "${BLUE}[1/4]${NC} 检查 Consul 和 Nomad..."
echo ""

NEED_INSTALL=false

# 检查 Consul
if command -v consul &> /dev/null; then
    CONSUL_INSTALLED=$(consul version | head -n1 | awk '{print $2}' | sed 's/v//')
    echo -e "Consul: ${GREEN}已安装${NC} (v$CONSUL_INSTALLED)"
    if [ "$CONSUL_INSTALLED" != "$CONSUL_VERSION" ]; then
        echo -e "  ${YELLOW}⚠${NC} 版本不匹配 (目标: v$CONSUL_VERSION)"
        NEED_INSTALL=true
    fi
else
    echo -e "Consul: ${RED}未安装${NC}"
    NEED_INSTALL=true
fi

# 检查 Nomad
if command -v nomad &> /dev/null; then
    NOMAD_INSTALLED=$(nomad version | head -n1 | awk '{print $2}' | sed 's/v//')
    echo -e "Nomad: ${GREEN}已安装${NC} (v$NOMAD_INSTALLED)"
    if [ "$NOMAD_INSTALLED" != "$NOMAD_VERSION" ]; then
        echo -e "  ${YELLOW}⚠${NC} 版本不匹配 (目标: v$NOMAD_VERSION)"
        NEED_INSTALL=true
    fi
else
    echo -e "Nomad: ${RED}未安装${NC}"
    NEED_INSTALL=true
fi

echo ""
# 步骤 2: 安装 Consul 和 Nomad (如果需要)
if [ "$NEED_INSTALL" = true ]; then
    echo -e "${BLUE}[2/4]${NC} 安装 Consul 和 Nomad..."
    echo ""
    
    # 检查是否有 sudo 权限
    if [ "$EUID" -ne 0 ]; then
        echo -e "${YELLOW}⚠${NC} 需要 sudo 权限来安装软件"
        echo "正在使用 sudo 运行安装脚本..."
        sudo bash "$SCRIPT_DIR/08-install-nomad-consul.sh"
    else
        bash "$SCRIPT_DIR/08-install-nomad-consul.sh"
    fi
    
    echo -e "${GREEN}✓${NC} Consul 和 Nomad 安装完成"
    echo ""
else
    echo -e "${GREEN}✓${NC} Consul 和 Nomad 版本正确，跳过安装"
    echo ""
fi

# 步骤 3: 启动 Consul
echo -e "${BLUE}[3/4]${NC} 启动 Consul..."
echo ""

if bash "$SCRIPT_DIR/start-consul.sh"; then
    echo -e "${GREEN}✓${NC} Consul 已启动"
else
    echo -e "${RED}✗${NC} Consul 启动失败"
    exit 1
fi
echo ""

# 步骤 4: 启动 Nomad
echo -e "${BLUE}[4/4]${NC} 启动 Nomad..."
echo ""

if bash "$SCRIPT_DIR/start-nomad.sh"; then
    echo -e "${GREEN}✓${NC} Nomad 已启动"
else
    echo -e "${RED}✗${NC} Nomad 启动失败"
    exit 1
fi
echo ""

# 显示最终状态
echo ""
echo "=========================================="
echo -e "${GREEN}${BOLD}✓ E2B 服务启动完成${NC}"
echo "=========================================="
echo ""

echo "服务状态:"
echo "  Consul: $(consul version 2>/dev/null | head -n1 || echo '未运行')"
echo "  Nomad:  $(nomad version 2>/dev/null | head -n1 || echo '未运行')"
echo ""

echo "访问地址:"
echo "  Consul UI: http://localhost:8500"
echo "  Nomad UI:  http://localhost:4646"
echo ""

echo "下一步:"
echo "  1. 部署 E2B Jobs:"
echo "     bash $SCRIPT_DIR/deploy-all-jobs.sh"
echo ""
echo "  2. 验证部署:"
echo "     bash $SCRIPT_DIR/verify-deployment.sh"
echo ""

echo -e "${GREEN}🎉 准备就绪！${NC}"
echo ""
