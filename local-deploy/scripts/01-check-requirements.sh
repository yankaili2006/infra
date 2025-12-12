#!/bin/bash
set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=================================="
echo "E2B 本地部署 - 系统要求检查"
echo "=================================="
echo ""

# 检查结果标记
ERRORS=0
WARNINGS=0

# 检查函数
check_command() {
    if command -v "$1" &> /dev/null; then
        echo -e "${GREEN}✓${NC} $1 已安装: $(command -v $1)"
        return 0
    else
        echo -e "${RED}✗${NC} $1 未安装"
        return 1
    fi
}

check_version() {
    local cmd=$1
    local required=$2
    local current=$3
    echo -e "${YELLOW}ℹ${NC} $cmd 版本: $current (要求: >= $required)"
}

# 1. 检查操作系统
echo "1. 检查操作系统..."
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    echo -e "${GREEN}✓${NC} 操作系统: Linux"

    # 检查发行版
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "  发行版: $NAME $VERSION"
    fi
else
    echo -e "${RED}✗${NC} 操作系统不支持: $OSTYPE"
    echo "  E2B 需要 Linux 系统（推荐 Ubuntu 20.04/22.04）"
    ERRORS=$((ERRORS + 1))
fi
echo ""

# 2. 检查内核版本
echo "2. 检查内核版本..."
KERNEL_VERSION=$(uname -r)
KERNEL_MAJOR=$(echo $KERNEL_VERSION | cut -d. -f1)
KERNEL_MINOR=$(echo $KERNEL_VERSION | cut -d. -f2)
echo "  当前内核: $KERNEL_VERSION"

# 检查：主版本 > 4，或者主版本 == 4 且次版本 >= 14
if [ "$KERNEL_MAJOR" -gt 4 ] || ([ "$KERNEL_MAJOR" -eq 4 ] && [ "$KERNEL_MINOR" -ge 14 ]); then
    echo -e "${GREEN}✓${NC} 内核版本符合要求 (>= 4.14)"
else
    echo -e "${RED}✗${NC} 内核版本过低 (要求 >= 4.14)"
    ERRORS=$((ERRORS + 1))
fi
echo ""

# 3. 检查 KVM 支持
echo "3. 检查 KVM 虚拟化支持..."
if [ -e /dev/kvm ]; then
    echo -e "${GREEN}✓${NC} /dev/kvm 存在"

    # 检查当前用户是否在 kvm 组
    if groups | grep -q kvm; then
        echo -e "${GREEN}✓${NC} 当前用户已在 kvm 组"
    else
        echo -e "${YELLOW}⚠${NC} 当前用户不在 kvm 组"
        echo "  运行: sudo usermod -aG kvm $USER"
        echo "  然后重新登录"
        WARNINGS=$((WARNINGS + 1))
    fi
else
    echo -e "${RED}✗${NC} /dev/kvm 不存在"
    echo "  请确保:"
    echo "  1. CPU 支持虚拟化（Intel VT-x 或 AMD-V）"
    echo "  2. BIOS 中已启用虚拟化"
    echo "  3. 已加载 kvm 内核模块: sudo modprobe kvm kvm_intel"
    ERRORS=$((ERRORS + 1))
fi
echo ""

# 4. 检查必需的内核模块
echo "4. 检查内核模块..."
declare -a REQUIRED_MODULES=("kvm" "nbd")

for module in "${REQUIRED_MODULES[@]}"; do
    if lsmod | grep -q "^$module "; then
        echo -e "${GREEN}✓${NC} $module 模块已加载"
    else
        echo -e "${YELLOW}⚠${NC} $module 模块未加载"
        echo "  运行: sudo modprobe $module"
        WARNINGS=$((WARNINGS + 1))
    fi
done
echo ""

# 5. 检查 CPU 核心数
echo "5. 检查系统资源..."
CPU_CORES=$(nproc)
echo "  CPU 核心数: $CPU_CORES"
if [ "$CPU_CORES" -ge 4 ]; then
    echo -e "${GREEN}✓${NC} CPU 核心数充足 (>= 4)"
else
    echo -e "${YELLOW}⚠${NC} CPU 核心数较少 (推荐 >= 4)"
    WARNINGS=$((WARNINGS + 1))
fi

# 检查内存
TOTAL_MEM=$(free -g | awk '/^Mem:/{print $2}')
echo "  总内存: ${TOTAL_MEM}GB"
if [ "$TOTAL_MEM" -ge 16 ]; then
    echo -e "${GREEN}✓${NC} 内存充足 (>= 16GB)"
elif [ "$TOTAL_MEM" -ge 8 ]; then
    echo -e "${YELLOW}⚠${NC} 内存较少 (推荐 >= 16GB, 最低 8GB)"
    WARNINGS=$((WARNINGS + 1))
else
    echo -e "${RED}✗${NC} 内存不足 (最低 8GB)"
    ERRORS=$((ERRORS + 1))
fi

# 检查磁盘空间
DISK_SPACE=$(df -BG /tmp | awk 'NR==2 {print $4}' | sed 's/G//')
echo "  /tmp 可用空间: ${DISK_SPACE}GB"
if [ "$DISK_SPACE" -ge 50 ]; then
    echo -e "${GREEN}✓${NC} 磁盘空间充足 (>= 50GB)"
else
    echo -e "${YELLOW}⚠${NC} /tmp 空间较少，推荐 >= 50GB"
    echo "  考虑修改 .env.local 中的存储路径到其他分区"
    WARNINGS=$((WARNINGS + 1))
fi
echo ""

# 6. 检查必需的命令行工具
echo "6. 检查必需的命令行工具..."
declare -a REQUIRED_COMMANDS=("docker" "git" "make" "curl" "jq")

for cmd in "${REQUIRED_COMMANDS[@]}"; do
    if ! check_command "$cmd"; then
        ERRORS=$((ERRORS + 1))
    fi
done
echo ""

# 7. 检查 Docker
echo "7. 检查 Docker 配置..."
if command -v docker &> /dev/null; then
    # 检查 Docker 版本
    DOCKER_VERSION=$(docker --version | awk '{print $3}' | sed 's/,//')
    check_version "Docker" "20.10" "$DOCKER_VERSION"

    # 检查 Docker 守护进程
    if docker info &> /dev/null; then
        echo -e "${GREEN}✓${NC} Docker 守护进程运行正常"

        # 检查当前用户是否在 docker 组
        if groups | grep -q docker; then
            echo -e "${GREEN}✓${NC} 当前用户已在 docker 组"
        else
            echo -e "${YELLOW}⚠${NC} 当前用户不在 docker 组"
            echo "  运行: sudo usermod -aG docker $USER"
            echo "  然后重新登录"
            WARNINGS=$((WARNINGS + 1))
        fi
    else
        echo -e "${RED}✗${NC} Docker 守护进程未运行"
        echo "  运行: sudo systemctl start docker"
        ERRORS=$((ERRORS + 1))
    fi
else
    echo -e "${RED}✗${NC} Docker 未安装"
    ERRORS=$((ERRORS + 1))
fi
echo ""

# 8. 检查可选工具
echo "8. 检查可选工具..."
declare -a OPTIONAL_COMMANDS=("go" "nomad" "consul")

for cmd in "${OPTIONAL_COMMANDS[@]}"; do
    if check_command "$cmd"; then
        case "$cmd" in
            go)
                GO_VERSION=$(go version | awk '{print $3}' | sed 's/go//')
                check_version "Go" "1.21" "$GO_VERSION"
                ;;
            nomad)
                NOMAD_VERSION=$(nomad version | head -n1 | awk '{print $2}')
                check_version "Nomad" "1.6" "$NOMAD_VERSION"
                ;;
            consul)
                CONSUL_VERSION=$(consul version | head -n1 | awk '{print $2}')
                check_version "Consul" "1.16" "$CONSUL_VERSION"
                ;;
        esac
    else
        echo -e "${YELLOW}ℹ${NC} $cmd 未安装（将在后续步骤中安装）"
    fi
done
echo ""

# 9. 检查端口占用
echo "9. 检查端口占用..."
declare -a REQUIRED_PORTS=(80 3000 3002 4646 4647 4648 5007 5008 5009 8500 9000 5432 6379 53000)

for port in "${REQUIRED_PORTS[@]}"; do
    if lsof -Pi :$port -sTCP:LISTEN -t >/dev/null 2>&1; then
        echo -e "${YELLOW}⚠${NC} 端口 $port 已被占用"
        lsof -Pi :$port -sTCP:LISTEN | head -n2
        WARNINGS=$((WARNINGS + 1))
    fi
done

if [ "$WARNINGS" -eq 0 ]; then
    echo -e "${GREEN}✓${NC} 所有端口可用"
fi
echo ""

# 10. 总结
echo "=================================="
echo "检查完成"
echo "=================================="
echo ""

if [ "$ERRORS" -eq 0 ] && [ "$WARNINGS" -eq 0 ]; then
    echo -e "${GREEN}✓ 所有检查通过！${NC}"
    echo ""
    echo "下一步: 运行 02-install-deps.sh 安装依赖"
    exit 0
elif [ "$ERRORS" -eq 0 ]; then
    echo -e "${YELLOW}⚠ 发现 $WARNINGS 个警告${NC}"
    echo ""
    echo "可以继续部署，但建议解决警告项"
    echo "下一步: 运行 02-install-deps.sh 安装依赖"
    exit 0
else
    echo -e "${RED}✗ 发现 $ERRORS 个错误和 $WARNINGS 个警告${NC}"
    echo ""
    echo "请先解决上述错误再继续"
    exit 1
fi
