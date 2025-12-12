#!/bin/bash
set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=================================="
echo "E2B 本地部署 - 安装依赖"
echo "=================================="
echo ""

# 检查是否为 root 用户
if [ "$EUID" -ne 0 ]; then
    echo -e "${YELLOW}⚠${NC} 此脚本需要 sudo 权限来安装软件"
    echo "请使用: sudo $0"
    exit 1
fi

# 检测 Linux 发行版
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VER=$VERSION_ID
else
    echo -e "${RED}✗${NC} 无法检测 Linux 发行版"
    exit 1
fi

echo "检测到系统: $OS $VER"
echo ""

# 1. 更新包管理器
echo "1. 更新包管理器..."
case "$OS" in
    ubuntu|debian)
        apt-get update
        echo -e "${GREEN}✓${NC} APT 包索引已更新"
        ;;
    centos|rhel|fedora)
        yum update -y
        echo -e "${GREEN}✓${NC} YUM 包索引已更新"
        ;;
    *)
        echo -e "${YELLOW}⚠${NC} 未知的发行版，请手动安装依赖"
        exit 1
        ;;
esac
echo ""

# 2. 安装基础工具
echo "2. 安装基础工具..."
case "$OS" in
    ubuntu|debian)
        apt-get install -y \
            build-essential \
            curl \
            wget \
            git \
            jq \
            unzip \
            ca-certificates \
            gnupg \
            lsb-release \
            software-properties-common
        ;;
    centos|rhel|fedora)
        yum install -y \
            gcc \
            gcc-c++ \
            make \
            curl \
            wget \
            git \
            jq \
            unzip \
            ca-certificates
        ;;
esac
echo -e "${GREEN}✓${NC} 基础工具安装完成"
echo ""

# 3. 安装 Docker（如果未安装）
echo "3. 检查并安装 Docker..."
if ! command -v docker &> /dev/null; then
    echo "正在安装 Docker..."

    case "$OS" in
        ubuntu|debian)
            # 添加 Docker 官方 GPG 密钥
            install -m 0755 -d /etc/apt/keyrings
            curl -fsSL https://download.docker.com/linux/$OS/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            chmod a+r /etc/apt/keyrings/docker.gpg

            # 添加 Docker 仓库
            echo \
              "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$OS \
              $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

            # 安装 Docker Engine
            apt-get update
            apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            ;;
        centos|rhel)
            yum install -y yum-utils
            yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            ;;
        fedora)
            dnf -y install dnf-plugins-core
            dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
            dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            ;;
    esac

    # 启动 Docker
    systemctl start docker
    systemctl enable docker

    echo -e "${GREEN}✓${NC} Docker 安装完成"
else
    echo -e "${GREEN}✓${NC} Docker 已安装: $(docker --version)"
fi
echo ""

# 4. 安装 Docker Compose（独立版，如果需要）
echo "4. 检查 Docker Compose..."
if docker compose version &> /dev/null; then
    echo -e "${GREEN}✓${NC} Docker Compose (插件版本) 已安装: $(docker compose version)"
elif command -v docker-compose &> /dev/null; then
    echo -e "${GREEN}✓${NC} Docker Compose (独立版本) 已安装: $(docker-compose --version)"
else
    echo "正在安装 Docker Compose..."
    # 安装最新版 Docker Compose
    COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | jq -r .tag_name)
    curl -L "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    echo -e "${GREEN}✓${NC} Docker Compose 安装完成: $COMPOSE_VERSION"
fi
echo ""

# 5. 安装 Go
echo "5. 检查并安装 Go..."
if ! command -v go &> /dev/null; then
    echo "正在安装 Go..."

    GO_VERSION="1.25.4"
    GO_ARCH=$(uname -m)
    case "$GO_ARCH" in
        x86_64) GO_ARCH="amd64" ;;
        aarch64) GO_ARCH="arm64" ;;
        armv7l) GO_ARCH="armv6l" ;;
    esac

    wget "https://go.dev/dl/go${GO_VERSION}.linux-${GO_ARCH}.tar.gz" -O /tmp/go.tar.gz
    rm -rf /usr/local/go
    tar -C /usr/local -xzf /tmp/go.tar.gz
    rm /tmp/go.tar.gz

    # 添加到 PATH（如果还没有）
    if ! grep -q "/usr/local/go/bin" /etc/profile; then
        echo 'export PATH=$PATH:/usr/local/go/bin' >> /etc/profile
    fi

    echo -e "${GREEN}✓${NC} Go ${GO_VERSION} 安装完成"
    echo "请运行: source /etc/profile 或重新登录以更新 PATH"
else
    echo -e "${GREEN}✓${NC} Go 已安装: $(go version)"
fi
echo ""

# 6. 安装 Make
echo "6. 检查 Make..."
if ! command -v make &> /dev/null; then
    echo "正在安装 Make..."
    case "$OS" in
        ubuntu|debian)
            apt-get install -y make
            ;;
        centos|rhel|fedora)
            yum install -y make
            ;;
    esac
    echo -e "${GREEN}✓${NC} Make 安装完成"
else
    echo -e "${GREEN}✓${NC} Make 已安装: $(make --version | head -n1)"
fi
echo ""

# 7. 安装 KVM 相关包
echo "7. 安装 KVM 虚拟化支持..."
case "$OS" in
    ubuntu|debian)
        apt-get install -y \
            qemu-kvm \
            libvirt-daemon-system \
            libvirt-clients \
            bridge-utils \
            cpu-checker
        ;;
    centos|rhel|fedora)
        yum install -y \
            qemu-kvm \
            libvirt \
            libvirt-client \
            bridge-utils
        ;;
esac
echo -e "${GREEN}✓${NC} KVM 相关包安装完成"
echo ""

# 8. 安装网络工具
echo "8. 安装网络工具..."
case "$OS" in
    ubuntu|debian)
        apt-get install -y \
            iptables \
            iproute2 \
            net-tools \
            dnsmasq \
            iputils-ping
        ;;
    centos|rhel|fedora)
        yum install -y \
            iptables \
            iproute \
            net-tools \
            dnsmasq \
            iputils
        ;;
esac
echo -e "${GREEN}✓${NC} 网络工具安装完成"
echo ""

# 9. 将当前用户添加到相关组（如果提供了 SUDO_USER）
if [ -n "$SUDO_USER" ]; then
    echo "9. 配置用户权限..."

    # 添加到 docker 组
    if getent group docker > /dev/null; then
        usermod -aG docker "$SUDO_USER"
        echo -e "${GREEN}✓${NC} 用户 $SUDO_USER 已添加到 docker 组"
    fi

    # 添加到 kvm 组
    if getent group kvm > /dev/null; then
        usermod -aG kvm "$SUDO_USER"
        echo -e "${GREEN}✓${NC} 用户 $SUDO_USER 已添加到 kvm 组"
    fi

    # 添加到 libvirt 组
    if getent group libvirt > /dev/null; then
        usermod -aG libvirt "$SUDO_USER"
        echo -e "${GREEN}✓${NC} 用户 $SUDO_USER 已添加到 libvirt 组"
    fi

    echo ""
    echo -e "${YELLOW}⚠${NC} 请重新登录以使组权限生效"
else
    echo "9. 跳过用户权限配置（无法检测 SUDO_USER）"
fi
echo ""

# 10. 总结
echo "=================================="
echo "依赖安装完成"
echo "=================================="
echo ""
echo -e "${GREEN}✓${NC} 所有依赖已安装"
echo ""
echo "下一步:"
echo "1. 重新登录以使组权限生效"
echo "2. 运行: source /etc/profile (如果安装了 Go)"
echo "3. 运行: 03-setup-kernel.sh 配置内核"
echo ""
