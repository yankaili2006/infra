#!/bin/bash
set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=================================="
echo "E2B 本地部署 - 安装 Nomad & Consul"
echo "=================================="
echo ""

# 检查是否为 root 用户
if [ "$EUID" -ne 0 ]; then
    echo -e "${YELLOW}⚠${NC} 此脚本需要 sudo 权限来安装软件"
    echo "请使用: sudo $0"
    exit 1
fi

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
    armv7l)
        ARCH="arm"
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

# 临时下载目录
TMP_DIR="/tmp/e2b-hashicorp-install"
mkdir -p "$TMP_DIR"

# 1. 安装 Nomad
echo "1. 检查并安装 Nomad..."
echo ""

if command -v nomad &> /dev/null; then
    INSTALLED_VERSION=$(nomad version | head -n1 | awk '{print $2}' | sed 's/v//')
    echo "Nomad 已安装: v$INSTALLED_VERSION"

    if [ "$INSTALLED_VERSION" == "$NOMAD_VERSION" ]; then
        echo -e "${GREEN}✓${NC} Nomad 版本正确"
    else
        echo -e "${YELLOW}⚠${NC} Nomad 版本不匹配 (已安装: $INSTALLED_VERSION, 目标: $NOMAD_VERSION)"
        read -p "是否重新安装? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "跳过 Nomad 安装"
            SKIP_NOMAD=true
        fi
    fi
fi

if [ -z "$SKIP_NOMAD" ]; then
    echo "下载 Nomad $NOMAD_VERSION..."

    NOMAD_ZIP="nomad_${NOMAD_VERSION}_linux_${ARCH}.zip"
    NOMAD_URL="https://releases.hashicorp.com/nomad/${NOMAD_VERSION}/${NOMAD_ZIP}"

    cd "$TMP_DIR"
    curl -LO "$NOMAD_URL"

    # 验证下载
    if [ ! -f "$NOMAD_ZIP" ]; then
        echo -e "${RED}✗${NC} Nomad 下载失败"
        exit 1
    fi

    echo "解压 Nomad..."
    unzip -o "$NOMAD_ZIP"

    # 安装到系统路径
    echo "安装 Nomad 到 /usr/local/bin..."
    mv nomad /usr/local/bin/
    chmod +x /usr/local/bin/nomad

    # 验证安装
    if command -v nomad &> /dev/null; then
        echo -e "${GREEN}✓${NC} Nomad 安装成功: $(nomad version | head -n1)"
    else
        echo -e "${RED}✗${NC} Nomad 安装失败"
        exit 1
    fi

    # 清理
    rm -f "$NOMAD_ZIP"
fi

echo ""

# 2. 安装 Consul
echo "2. 检查并安装 Consul..."
echo ""

if command -v consul &> /dev/null; then
    INSTALLED_VERSION=$(consul version | head -n1 | awk '{print $2}' | sed 's/v//')
    echo "Consul 已安装: v$INSTALLED_VERSION"

    if [ "$INSTALLED_VERSION" == "$CONSUL_VERSION" ]; then
        echo -e "${GREEN}✓${NC} Consul 版本正确"
    else
        echo -e "${YELLOW}⚠${NC} Consul 版本不匹配 (已安装: $INSTALLED_VERSION, 目标: $CONSUL_VERSION)"
        read -p "是否重新安装? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "跳过 Consul 安装"
            SKIP_CONSUL=true
        fi
    fi
fi

if [ -z "$SKIP_CONSUL" ]; then
    echo "下载 Consul $CONSUL_VERSION..."

    CONSUL_ZIP="consul_${CONSUL_VERSION}_linux_${ARCH}.zip"
    CONSUL_URL="https://releases.hashicorp.com/consul/${CONSUL_VERSION}/${CONSUL_ZIP}"

    cd "$TMP_DIR"
    curl -LO "$CONSUL_URL"

    # 验证下载
    if [ ! -f "$CONSUL_ZIP" ]; then
        echo -e "${RED}✗${NC} Consul 下载失败"
        exit 1
    fi

    echo "解压 Consul..."
    unzip -o "$CONSUL_ZIP"

    # 安装到系统路径
    echo "安装 Consul 到 /usr/local/bin..."
    mv consul /usr/local/bin/
    chmod +x /usr/local/bin/consul

    # 验证安装
    if command -v consul &> /dev/null; then
        echo -e "${GREEN}✓${NC} Consul 安装成功: $(consul version | head -n1)"
    else
        echo -e "${RED}✗${NC} Consul 安装失败"
        exit 1
    fi

    # 清理
    rm -f "$CONSUL_ZIP"
fi

echo ""

# 3. 配置自动补全（可选）
echo "3. 配置命令行自动补全..."

# Nomad 自动补全
if command -v nomad &> /dev/null; then
    nomad -autocomplete-install 2>/dev/null || true
    echo -e "${GREEN}✓${NC} Nomad 自动补全已配置"
fi

# Consul 自动补全
if command -v consul &> /dev/null; then
    consul -autocomplete-install 2>/dev/null || true
    echo -e "${GREEN}✓${NC} Consul 自动补全已配置"
fi

echo ""

# 4. 创建数据目录
echo "4. 创建数据目录..."

NOMAD_DATA_DIR="/tmp/nomad-local"
CONSUL_DATA_DIR="/tmp/consul-local"

mkdir -p "$NOMAD_DATA_DIR"
mkdir -p "$CONSUL_DATA_DIR"

# 如果以 sudo 运行，设置正确的所有者
if [ -n "$SUDO_USER" ]; then
    chown -R "$SUDO_USER:$SUDO_USER" "$NOMAD_DATA_DIR"
    chown -R "$SUDO_USER:$SUDO_USER" "$CONSUL_DATA_DIR"
fi

echo -e "${GREEN}✓${NC} Nomad 数据目录: $NOMAD_DATA_DIR"
echo -e "${GREEN}✓${NC} Consul 数据目录: $CONSUL_DATA_DIR"
echo ""

# 5. 验证配置文件
echo "5. 验证配置文件..."

NOMAD_CONFIG="/home/primihub/pcloud/infra/local-deploy/nomad-dev.hcl"

if [ -f "$NOMAD_CONFIG" ]; then
    echo "验证 Nomad 配置: $NOMAD_CONFIG"
    if nomad config validate "$NOMAD_CONFIG"; then
        echo -e "${GREEN}✓${NC} Nomad 配置有效"
    else
        echo -e "${RED}✗${NC} Nomad 配置无效"
        exit 1
    fi
else
    echo -e "${RED}✗${NC} Nomad 配置文件不存在: $NOMAD_CONFIG"
    exit 1
fi

echo ""

# 6. 创建 systemd 服务文件（可选）
echo "6. 创建 systemd 服务..."

# Consul 服务
cat > /etc/systemd/system/consul-local.service <<EOF
[Unit]
Description=Consul (Local Dev Mode)
Documentation=https://www.consul.io/docs
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${SUDO_USER:-root}
Group=${SUDO_USER:-root}
ExecStart=/usr/local/bin/consul agent -dev -data-dir=$CONSUL_DATA_DIR
ExecReload=/bin/kill -HUP \$MAINPID
KillMode=process
KillSignal=SIGTERM
Restart=on-failure
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

# Nomad 服务
cat > /etc/systemd/system/nomad-local.service <<EOF
[Unit]
Description=Nomad (Local Dev Mode)
Documentation=https://www.nomadproject.io/docs
After=network-online.target consul-local.service
Wants=network-online.target

[Service]
Type=simple
User=${SUDO_USER:-root}
Group=${SUDO_USER:-root}
ExecStart=/usr/local/bin/nomad agent -config=$NOMAD_CONFIG
ExecReload=/bin/kill -HUP \$MAINPID
KillMode=process
KillSignal=SIGINT
Restart=on-failure
RestartSec=2
LimitNOFILE=65536
LimitNPROC=infinity

[Install]
WantedBy=multi-user.target
EOF

# 重新加载 systemd
systemctl daemon-reload

echo -e "${GREEN}✓${NC} Systemd 服务已创建"
echo "  - consul-local.service"
echo "  - nomad-local.service"
echo ""

# 7. 清理临时文件
echo "7. 清理临时文件..."
rm -rf "$TMP_DIR"
echo -e "${GREEN}✓${NC} 临时文件已清理"
echo ""

# 8. 总结
echo "=================================="
echo "Nomad & Consul 安装完成"
echo "=================================="
echo ""

echo "已安装的组件:"
if command -v nomad &> /dev/null; then
    echo -e "${GREEN}✓${NC} Nomad: $(nomad version | head -n1)"
else
    echo -e "${RED}✗${NC} Nomad 未安装"
fi

if command -v consul &> /dev/null; then
    echo -e "${GREEN}✓${NC} Consul: $(consul version | head -n1)"
else
    echo -e "${RED}✗${NC} Consul 未安装"
fi

echo ""
echo "配置文件:"
echo "  Nomad: $NOMAD_CONFIG"
echo ""

echo "数据目录:"
echo "  Nomad: $NOMAD_DATA_DIR"
echo "  Consul: $CONSUL_DATA_DIR"
echo ""

echo "Systemd 服务:"
echo "  启动 Consul: sudo systemctl start consul-local"
echo "  启动 Nomad:  sudo systemctl start nomad-local"
echo "  查看状态:    sudo systemctl status consul-local nomad-local"
echo "  开机自启:    sudo systemctl enable consul-local nomad-local"
echo ""

echo "访问地址:"
echo "  Consul UI: http://localhost:8500/ui"
echo "  Nomad UI:  http://localhost:4646/ui"
echo ""

echo "下一步: 运行 09-init-database.sh 初始化数据库"
echo ""
