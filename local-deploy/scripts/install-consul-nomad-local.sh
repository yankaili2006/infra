#!/bin/bash
set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "=========================================="
echo "安装 Consul 和 Nomad (用户目录)"
echo "=========================================="
echo ""

# 版本配置
NOMAD_VERSION="1.8.4"
CONSUL_VERSION="1.19.2"

# 检测架构
ARCH=$(uname -m)
case "$ARCH" in
    x86_64)
        ARCH="amd64"
        ;;
    aarch64)
        ARCH="arm64"
        ;;
    *)
        echo -e "${RED}✗${NC} 不支持的架构: $ARCH"
        exit 1
        ;;
esac

echo "系统架构: $ARCH"
echo "Nomad 版本: $NOMAD_VERSION"
echo "Consul 版本: $CONSUL_VERSION"
echo ""

# 安装目录（用户目录，无需 sudo）
INSTALL_DIR="$HOME/.local/bin"
TMP_DIR="/tmp/e2b-hashicorp-install"

mkdir -p "$INSTALL_DIR"
mkdir -p "$TMP_DIR"

echo "安装目录: $INSTALL_DIR"
echo ""
# 1. 安装 Consul
echo "1. 安装 Consul..."
echo ""

if command -v consul &> /dev/null && [ -f "$INSTALL_DIR/consul" ]; then
    INSTALLED_VERSION=$(consul version | head -n1 | awk '{print $2}' | sed 's/v//')
    echo "Consul 已安装: v$INSTALLED_VERSION"
    
    if [ "$INSTALLED_VERSION" == "$CONSUL_VERSION" ]; then
        echo -e "${GREEN}✓${NC} Consul 版本正确，跳过安装"
        SKIP_CONSUL=true
    fi
fi

if [ -z "$SKIP_CONSUL" ]; then
    echo "下载 Consul $CONSUL_VERSION..."
    
    CONSUL_ZIP="consul_${CONSUL_VERSION}_linux_${ARCH}.zip"
    CONSUL_URL="https://releases.hashicorp.com/consul/${CONSUL_VERSION}/${CONSUL_ZIP}"
    
    cd "$TMP_DIR"
    curl -LO "$CONSUL_URL"
    
    if [ ! -f "$CONSUL_ZIP" ]; then
        echo -e "${RED}✗${NC} Consul 下载失败"
        exit 1
    fi
    
    echo "解压 Consul..."
    unzip -o "$CONSUL_ZIP"
    
    echo "安装 Consul 到 $INSTALL_DIR..."
    mv consul "$INSTALL_DIR/"
    chmod +x "$INSTALL_DIR/consul"
    
    if [ -f "$INSTALL_DIR/consul" ]; then
        echo -e "${GREEN}✓${NC} Consul 安装成功: $($INSTALL_DIR/consul version | head -n1)"
    else
        echo -e "${RED}✗${NC} Consul 安装失败"
        exit 1
    fi
fi

echo ""

# 2. 安装 Nomad
echo "2. 安装 Nomad..."
echo ""

if command -v nomad &> /dev/null && [ -f "$INSTALL_DIR/nomad" ]; then
    INSTALLED_VERSION=$(nomad version | head -n1 | awk '{print $2}' | sed 's/v//')
    echo "Nomad 已安装: v$INSTALLED_VERSION"
    
    if [ "$INSTALLED_VERSION" == "$NOMAD_VERSION" ]; then
        echo -e "${GREEN}✓${NC} Nomad 版本正确，跳过安装"
        SKIP_NOMAD=true
    fi
fi

if [ -z "$SKIP_NOMAD" ]; then
    echo "下载 Nomad $NOMAD_VERSION..."
    
    NOMAD_ZIP="nomad_${NOMAD_VERSION}_linux_${ARCH}.zip"
    NOMAD_URL="https://releases.hashicorp.com/nomad/${NOMAD_VERSION}/${NOMAD_ZIP}"
    
    cd "$TMP_DIR"
    curl -LO "$NOMAD_URL"
    
    if [ ! -f "$NOMAD_ZIP" ]; then
        echo -e "${RED}✗${NC} Nomad 下载失败"
        exit 1
    fi
    
    echo "解压 Nomad..."
    unzip -o "$NOMAD_ZIP"
    
    echo "安装 Nomad 到 $INSTALL_DIR..."
    mv nomad "$INSTALL_DIR/"
    chmod +x "$INSTALL_DIR/nomad"
    
    if [ -f "$INSTALL_DIR/nomad" ]; then
        echo -e "${GREEN}✓${NC} Nomad 安装成功: $($INSTALL_DIR/nomad version | head -n1)"
    else
        echo -e "${RED}✗${NC} Nomad 安装失败"
        exit 1
    fi
fi

echo ""

# 3. 配置 PATH
echo "3. 配置 PATH..."
echo ""

# 检查 PATH 中是否包含 ~/.local/bin
if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
    echo -e "${YELLOW}⚠${NC} $HOME/.local/bin 不在 PATH 中"
    echo ""
    echo "请将以下内容添加到 ~/.bashrc 或 ~/.zshrc:"
    echo ""
    echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
    echo ""
    echo "然后运行: source ~/.bashrc"
    echo ""
else
    echo -e "${GREEN}✓${NC} PATH 已正确配置"
fi

echo ""

# 4. 验证安装
echo "4. 验证安装..."
echo ""

# 临时添加到当前 PATH
export PATH="$INSTALL_DIR:$PATH"

if command -v consul &> /dev/null; then
    echo -e "${GREEN}✓${NC} Consul: $(consul version | head -n1)"
else
    echo -e "${RED}✗${NC} Consul 未找到"
fi

if command -v nomad &> /dev/null; then
    echo -e "${GREEN}✓${NC} Nomad: $(nomad version | head -n1)"
else
    echo -e "${RED}✗${NC} Nomad 未找到"
fi

echo ""
echo "=========================================="
echo -e "${GREEN}✓ 安装完成${NC}"
echo "=========================================="
echo ""
echo "安装位置: $INSTALL_DIR"
echo ""
echo "如果命令未找到，请运行:"
echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
echo ""
