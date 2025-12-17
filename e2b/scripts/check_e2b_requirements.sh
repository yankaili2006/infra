#!/bin/bash
# E2B部署资源检查脚本

echo "=========================================="
echo "E2B完整部署资源检查"
echo "=========================================="

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo ""
echo "📊 当前系统资源:"
echo "----------------"

# 内存检查
total_mem=$(free -g | awk '/^Mem:/{print $2}')
available_mem=$(free -g | awk '/^Mem:/{print $7}')
echo -n "内存: ${total_mem}GB "
if [ "$total_mem" -ge 16 ]; then
    echo -e "${GREEN}✓ 满足要求 (16GB+)${NC}"
elif [ "$total_mem" -ge 8 ]; then
    echo -e "${YELLOW}⚠ 基本满足 (8GB)${NC}"
else
    echo -e "${RED}✗ 不足 (需要8GB+)${NC}"
fi

# CPU检查
cpu_cores=$(nproc)
echo -n "CPU核心: ${cpu_cores} "
if [ "$cpu_cores" -ge 8 ]; then
    echo -e "${GREEN}✓ 优秀 (8+核心)${NC}"
elif [ "$cpu_cores" -ge 4 ]; then
    echo -e "${YELLOW}⚠ 基本满足 (4核心)${NC}"
else
    echo -e "${RED}✗ 不足 (需要4+核心)${NC}"
fi

# 存储检查
df -h / | awk 'NR==2{printf "存储: %s/%s ", $3, $2}'
free_gb=$(df -BG / | awk 'NR==2{print $4}' | sed 's/G//')
if [ "$free_gb" -ge 100 ]; then
    echo -e "${GREEN}✓ 充足 (100GB+)${NC}"
elif [ "$free_gb" -ge 50 ]; then
    echo -e "${YELLOW}⚠ 基本满足 (50GB)${NC}"
else
    echo -e "${RED}✗ 不足 (需要50GB+)${NC}"
fi

# KVM检查
echo -n "KVM虚拟化: "
if [ -e /dev/kvm ]; then
    echo -e "${GREEN}✓ 已启用${NC}"
else
    echo -e "${RED}✗ 未启用${NC}"
fi

echo ""
echo "🔧 软件依赖检查:"
echo "----------------"

# Docker检查
if command -v docker &> /dev/null; then
    docker_version=$(docker --version | awk '{print $3}' | sed 's/,//')
    echo -e "${GREEN}✓ Docker: ${docker_version}${NC}"
else
    echo -e "${RED}✗ Docker: 未安装${NC}"
fi

# Docker Compose检查
if command -v docker-compose &> /dev/null; then
    echo -e "${GREEN}✓ Docker Compose: 已安装${NC}"
else
    echo -e "${RED}✗ Docker Compose: 未安装${NC}"
fi

# Go检查
if command -v go &> /dev/null; then
    go_version=$(go version | awk '{print $3}')
    echo -e "${GREEN}✓ Go: ${go_version}${NC}"
else
    echo -e "${RED}✗ Go: 未安装${NC}"
fi

echo ""
echo "📈 资源升级建议:"
echo "----------------"

if [ "$total_mem" -lt 16 ]; then
    echo -e "${BLUE}1. 内存升级:${NC}"
    echo "   当前: ${total_mem}GB"
    echo "   建议: 升级到16GB或32GB"
    echo "   影响: 可同时运行更多VM，提高性能"
fi

if [ "$cpu_cores" -lt 8 ]; then
    echo -e "${BLUE}2. CPU升级:${NC}"
    echo "   当前: ${cpu_cores}核心"
    echo "   建议: 升级到8核心或更多"
    echo "   影响: 提高VM创建速度和并发能力"
fi

if [ "$free_gb" -lt 100 ]; then
    echo -e "${BLUE}3. 存储升级:${NC}"
    echo "   当前可用: ${free_gb}GB"
    echo "   建议: 使用SSD/NVMe，至少100GB可用空间"
    echo "   影响: 存储更多VM模板和缓存"
fi

echo ""
echo "🚀 快速升级方案:"
echo "----------------"
echo "1. 云服务器升级方案:"
echo "   - AWS: t3.xlarge (16GB) → t3.2xlarge (32GB)"
echo "   - GCP: n2-standard-8 (32GB) → n2-standard-16 (64GB)"
echo "   - Azure: D4s_v3 (16GB) → D8s_v3 (32GB)"
echo ""
echo "2. 物理服务器建议:"
echo "   - 内存: 32GB DDR4 ECC"
echo "   - CPU: Intel Xeon E-2288G 或 AMD EPYC 7302"
echo "   - 存储: 512GB NVMe SSD"
echo "   - 网络: 10G以太网"

echo ""
echo "⚡ 立即部署选项:"
echo "----------------"
echo "A. 完整部署 (推荐16GB+内存):"
echo "   bash /root/pcloud/e2b_complete_deployment_guide.md"
echo ""
echo "B. 轻量级部署 (8GB内存):"
echo "   使用现有的Docker容器方案"
echo ""
echo "C. 测试部署:"
echo "   继续使用当前简化方案"

echo ""
echo "📋 检查完成"
echo "=========================================="
