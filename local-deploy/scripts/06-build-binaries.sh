#!/bin/bash
set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=================================="
echo "E2B 本地部署 - 构建 Go 二进制文件"
echo "=================================="
echo ""

# 项目根目录
PROJECT_ROOT="/home/primihub/pcloud/infra"
cd "$PROJECT_ROOT"

echo "项目目录: $PROJECT_ROOT"
echo ""

# 检查 Go 是否已安装
if ! command -v go &> /dev/null; then
    echo -e "${RED}✗${NC} Go 未安装"
    echo "请先运行 02-install-deps.sh 安装 Go"
    exit 1
fi

GO_VERSION=$(go version)
echo "Go 版本: $GO_VERSION"
echo ""

# 检查 Make 是否已安装
if ! command -v make &> /dev/null; then
    echo -e "${RED}✗${NC} Make 未安装"
    echo "请先运行 02-install-deps.sh 安装 Make"
    exit 1
fi

echo "Make 版本: $(make --version | head -n1)"
echo ""

# 设置构建环境变量
export CGO_ENABLED=1
export GOOS=linux
export GOARCH=amd64

echo "构建配置:"
echo "  CGO_ENABLED: $CGO_ENABLED"
echo "  GOOS: $GOOS"
echo "  GOARCH: $GOARCH"
echo ""

# 定义需要构建的包
declare -A BUILD_TARGETS=(
    ["orchestrator"]="packages/orchestrator"
    ["envd"]="packages/envd"
)

# 1. 下载依赖
echo "1. 下载 Go 依赖..."
echo ""

# 使用 Go workspace 模式
if [ -f "go.work" ]; then
    echo "检测到 Go workspace: go.work"
    go work sync
    echo -e "${GREEN}✓${NC} Workspace 已同步"
else
    echo -e "${YELLOW}⚠${NC} 未找到 go.work，使用传统模式"
fi

# 为每个包下载依赖
for target in "${!BUILD_TARGETS[@]}"; do
    pkg_dir="${BUILD_TARGETS[$target]}"
    if [ -d "$pkg_dir" ]; then
        echo "下载 $target 依赖..."
        (cd "$pkg_dir" && go mod download)
        echo -e "${GREEN}✓${NC} $target 依赖已下载"
    fi
done

echo ""

# 2. 构建二进制文件
echo "2. 构建二进制文件..."
echo ""

BUILD_SUCCESS=0
BUILD_FAILED=0

for target in "${!BUILD_TARGETS[@]}"; do
    pkg_dir="${BUILD_TARGETS[$target]}"

    if [ ! -d "$pkg_dir" ]; then
        echo -e "${RED}✗${NC} 目录不存在: $pkg_dir"
        BUILD_FAILED=$((BUILD_FAILED + 1))
        continue
    fi

    echo "----------------------------------------"
    echo "构建: $target"
    echo "目录: $pkg_dir"
    echo ""

    # 切换到包目录
    cd "$PROJECT_ROOT/$pkg_dir"

    # 检查是否有 Makefile
    if [ -f "Makefile" ]; then
        echo "使用 Makefile 构建..."

        # 检查是否有 build 目标
        if make -n build &> /dev/null; then
            if make build; then
                echo -e "${GREEN}✓${NC} $target 构建成功"
                BUILD_SUCCESS=$((BUILD_SUCCESS + 1))
            else
                echo -e "${RED}✗${NC} $target 构建失败"
                BUILD_FAILED=$((BUILD_FAILED + 1))
                continue
            fi
        else
            echo -e "${YELLOW}⚠${NC} Makefile 不支持 build 目标，使用 go build..."
            if go build -o "bin/$target" .; then
                echo -e "${GREEN}✓${NC} $target 构建成功"
                BUILD_SUCCESS=$((BUILD_SUCCESS + 1))
            else
                echo -e "${RED}✗${NC} $target 构建失败"
                BUILD_FAILED=$((BUILD_FAILED + 1))
                continue
            fi
        fi
    else
        echo "直接使用 go build..."

        # 创建 bin 目录
        mkdir -p bin

        # 构建
        if go build -o "bin/$target" .; then
            echo -e "${GREEN}✓${NC} $target 构建成功"
            BUILD_SUCCESS=$((BUILD_SUCCESS + 1))
        else
            echo -e "${RED}✗${NC} $target 构建失败"
            BUILD_FAILED=$((BUILD_FAILED + 1))
            continue
        fi
    fi

    # 验证二进制文件
    BIN_PATH="bin/$target"
    if [ -f "$BIN_PATH" ]; then
        BIN_SIZE=$(du -h "$BIN_PATH" | cut -f1)
        echo "二进制文件: $BIN_PATH ($BIN_SIZE)"

        # 显示版本信息（如果支持）
        if "./$BIN_PATH" --version &> /dev/null; then
            VERSION=$("./$BIN_PATH" --version)
            echo "版本: $VERSION"
        fi
    else
        echo -e "${RED}✗${NC} 二进制文件不存在: $BIN_PATH"
        BUILD_FAILED=$((BUILD_FAILED + 1))
    fi

    echo ""
    cd "$PROJECT_ROOT"
done

# 3. 下载 Firecracker 和内核（如果不存在）
echo "3. 检查 Firecracker 和内核文件..."
echo ""

FC_VERSIONS_DIR="$PROJECT_ROOT/packages/fc-versions/builds"
KERNELS_DIR="$PROJECT_ROOT/packages/fc-kernels"

# 创建目录
mkdir -p "$FC_VERSIONS_DIR"
mkdir -p "$KERNELS_DIR"

# 默认版本（与 .env.local 一致）
DEFAULT_FC_VERSION="v1.12.1_d990331"
DEFAULT_KERNEL_VERSION="vmlinux-6.1.158"

# 检查 Firecracker
FC_BIN="$FC_VERSIONS_DIR/$DEFAULT_FC_VERSION/firecracker"
if [ -f "$FC_BIN" ]; then
    echo -e "${GREEN}✓${NC} Firecracker 已存在: $FC_BIN"
else
    echo -e "${YELLOW}⚠${NC} Firecracker 不存在，需要下载或构建"
    echo "  运行: make copy-public-builds (需要 GCP 访问权限)"
    echo "  或从 https://github.com/firecracker-microvm/firecracker/releases 手动下载"
fi

# 检查内核
KERNEL_FILE="$KERNELS_DIR/$DEFAULT_KERNEL_VERSION"
if [ -f "$KERNEL_FILE" ]; then
    echo -e "${GREEN}✓${NC} 内核已存在: $KERNEL_FILE"
else
    echo -e "${YELLOW}⚠${NC} 内核不存在，需要下载或构建"
    echo "  运行: make copy-public-builds (需要 GCP 访问权限)"
    echo "  或参考文档手动构建"
fi

echo ""

# 4. 设置 Capabilities（如果之前选择了此选项）
if [ -f "/tmp/e2b-setup-capabilities.sh" ]; then
    echo "4. 检测到 capabilities 配置脚本"
    echo ""

    ORCHESTRATOR_BIN="$PROJECT_ROOT/packages/orchestrator/bin/orchestrator"
    if [ -f "$ORCHESTRATOR_BIN" ]; then
        echo "为 Orchestrator 设置 capabilities..."

        if [ "$EUID" -eq 0 ]; then
            # 以 root 运行，直接设置
            setcap cap_net_admin,cap_sys_admin,cap_net_raw+ep "$ORCHESTRATOR_BIN"
            echo -e "${GREEN}✓${NC} Capabilities 已设置"
            getcap "$ORCHESTRATOR_BIN"
        else
            # 非 root，提示使用 sudo
            echo "需要 sudo 权限设置 capabilities:"
            echo "sudo setcap cap_net_admin,cap_sys_admin,cap_net_raw+ep $ORCHESTRATOR_BIN"
            echo ""
            echo "或运行: sudo /tmp/e2b-setup-capabilities.sh"
        fi
    fi
    echo ""
fi

# 5. 总结
echo "=================================="
echo "Go 二进制构建完成"
echo "=================================="
echo ""

if [ "$BUILD_FAILED" -eq 0 ]; then
    echo -e "${GREEN}✓${NC} 所有包构建成功 ($BUILD_SUCCESS/$BUILD_SUCCESS)"
else
    echo -e "${YELLOW}⚠${NC} 部分包构建失败"
    echo "  成功: $BUILD_SUCCESS"
    echo "  失败: $BUILD_FAILED"
fi

echo ""
echo "构建产物:"
for target in "${!BUILD_TARGETS[@]}"; do
    pkg_dir="${BUILD_TARGETS[$target]}"
    bin_path="$PROJECT_ROOT/$pkg_dir/bin/$target"

    if [ -f "$bin_path" ]; then
        bin_size=$(du -h "$bin_path" | cut -f1)
        echo -e "  ${GREEN}✓${NC} $bin_path ($bin_size)"
    else
        echo -e "  ${RED}✗${NC} $bin_path (未找到)"
    fi
done

echo ""

if [ "$BUILD_FAILED" -eq 0 ]; then
    echo "下一步: 运行 07-build-images.sh 构建 Docker 镜像"
else
    echo "请先解决构建错误再继续"
    exit 1
fi

echo ""
