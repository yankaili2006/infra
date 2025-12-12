#!/bin/bash
set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=================================="
echo "E2B 本地部署 - 构建 Docker 镜像"
echo "=================================="
echo ""

# 项目根目录
PROJECT_ROOT="/home/primihub/pcloud/infra"
cd "$PROJECT_ROOT"

echo "项目目录: $PROJECT_ROOT"
echo ""

# 检查 Docker 是否运行
if ! docker info &> /dev/null; then
    echo -e "${RED}✗${NC} Docker 守护进程未运行"
    echo "请启动 Docker: sudo systemctl start docker"
    exit 1
fi

echo "Docker 版本: $(docker --version)"
echo ""

# 定义需要构建的镜像
# 格式: [镜像名]="Dockerfile路径:构建上下文"
declare -A IMAGES=(
    ["e2b-api:local"]="packages/api/Dockerfile:packages"
    ["e2b-client-proxy:local"]="packages/client-proxy/Dockerfile:packages"
    ["e2b-db-migrator:local"]="packages/db/Dockerfile:packages"
)

# 构建统计
BUILD_SUCCESS=0
BUILD_FAILED=0
declare -a FAILED_IMAGES

echo "将构建以下镜像:"
for image in "${!IMAGES[@]}"; do
    echo "  - $image"
done
echo ""

# 构建每个镜像
for image in "${!IMAGES[@]}"; do
    IFS=':' read -r dockerfile context <<< "${IMAGES[$image]}"

    echo "========================================"
    echo "构建镜像: $image"
    echo "========================================"
    echo "Dockerfile: $dockerfile"
    echo "上下文: $context"
    echo ""

    # 检查 Dockerfile 是否存在
    if [ ! -f "$PROJECT_ROOT/$dockerfile" ]; then
        echo -e "${RED}✗${NC} Dockerfile 不存在: $dockerfile"
        BUILD_FAILED=$((BUILD_FAILED + 1))
        FAILED_IMAGES+=("$image (Dockerfile 不存在)")
        echo ""
        continue
    fi

    # 检查上下文目录是否存在
    if [ ! -d "$PROJECT_ROOT/$context" ]; then
        echo -e "${RED}✗${NC} 构建上下文不存在: $context"
        BUILD_FAILED=$((BUILD_FAILED + 1))
        FAILED_IMAGES+=("$image (上下文不存在)")
        echo ""
        continue
    fi

    # 构建镜像
    echo "开始构建..."
    BUILD_START=$(date +%s)

    # 获取Docker网桥网关IP (用于容器访问宿主机代理)
    # 不能使用 ip route 的默认网关，那是宿主机的外网网关
    # 容器需要通过Docker网桥网关访问宿主机
    HOST_IP=$(docker network inspect bridge -f '{{range .IPAM.Config}}{{.Gateway}}{{end}}' 2>/dev/null)
    if [ -z "$HOST_IP" ]; then
        HOST_IP="172.17.0.1"  # Docker默认网关IP
    fi

    # Go proxy domains should bypass HTTP proxy to avoid checksum mismatch
    # GOPROXY already provides the proxy functionality, no need to double-proxy
    NO_PROXY_DOMAINS="localhost,127.0.0.1,goproxy.io,proxy.golang.org,sum.golang.org"

    if docker build \
        -t "$image" \
        --build-arg HTTP_PROXY="http://${HOST_IP}:7890" \
        --build-arg HTTPS_PROXY="http://${HOST_IP}:7890" \
        --build-arg NO_PROXY="${NO_PROXY_DOMAINS}" \
        --build-arg GOPROXY="https://goproxy.io,https://proxy.golang.org,direct" \
        -f "$PROJECT_ROOT/$dockerfile" \
        "$PROJECT_ROOT/$context"; then

        BUILD_END=$(date +%s)
        BUILD_TIME=$((BUILD_END - BUILD_START))

        echo ""
        echo -e "${GREEN}✓${NC} $image 构建成功 (耗时: ${BUILD_TIME}s)"

        # 显示镜像信息
        IMAGE_SIZE=$(docker images "$image" --format "{{.Size}}" | head -n1)
        IMAGE_ID=$(docker images "$image" --format "{{.ID}}" | head -n1)
        echo "  镜像 ID: $IMAGE_ID"
        echo "  大小: $IMAGE_SIZE"

        BUILD_SUCCESS=$((BUILD_SUCCESS + 1))
    else
        echo ""
        echo -e "${RED}✗${NC} $image 构建失败"
        BUILD_FAILED=$((BUILD_FAILED + 1))
        FAILED_IMAGES+=("$image")
    fi

    echo ""
done

# 清理悬空镜像
echo "清理悬空镜像..."
DANGLING=$(docker images -f "dangling=true" -q)
if [ -n "$DANGLING" ]; then
    docker rmi $DANGLING 2>/dev/null || true
    echo -e "${GREEN}✓${NC} 悬空镜像已清理"
else
    echo "没有悬空镜像"
fi
echo ""

# 显示所有 E2B 镜像
echo "E2B 镜像列表:"
docker images | grep -E "^e2b-|REPOSITORY" || true
echo ""

# 总结
echo "=================================="
echo "Docker 镜像构建完成"
echo "=================================="
echo ""

TOTAL=$((BUILD_SUCCESS + BUILD_FAILED))
echo "构建统计:"
echo "  总计: $TOTAL"
echo "  成功: $BUILD_SUCCESS"
echo "  失败: $BUILD_FAILED"
echo ""

if [ "$BUILD_FAILED" -gt 0 ]; then
    echo -e "${RED}失败的镜像:${NC}"
    for failed in "${FAILED_IMAGES[@]}"; do
        echo "  - $failed"
    done
    echo ""
fi

# 镜像详情
echo "镜像详情:"
for image in "${!IMAGES[@]}"; do
    if docker images "$image" --format "table {{.Repository}}:{{.Tag}}\t{{.ID}}\t{{.Size}}\t{{.CreatedAt}}" | grep -v REPOSITORY &> /dev/null; then
        echo -e "${GREEN}✓${NC} $image"
        docker images "$image" --format "    ID: {{.ID}}, 大小: {{.Size}}, 创建: {{.CreatedSince}}"
    else
        echo -e "${RED}✗${NC} $image (未找到)"
    fi
done
echo ""

# 验证必需的镜像
echo "验证必需镜像..."
REQUIRED_IMAGES=(
    "e2b-api:local"
    "e2b-client-proxy:local"
    "e2b-db-migrator:local"
)

MISSING=0
for req_image in "${REQUIRED_IMAGES[@]}"; do
    if docker images "$req_image" --format "{{.Repository}}:{{.Tag}}" | grep -q "$req_image"; then
        echo -e "${GREEN}✓${NC} $req_image"
    else
        echo -e "${RED}✗${NC} $req_image (缺失)"
        MISSING=$((MISSING + 1))
    fi
done
echo ""

if [ "$MISSING" -gt 0 ]; then
    echo -e "${RED}✗ 缺少 $MISSING 个必需镜像${NC}"
    echo "请先解决构建错误"
    exit 1
fi

if [ "$BUILD_FAILED" -gt 0 ]; then
    echo -e "${YELLOW}⚠ 部分镜像构建失败，但必需镜像已就绪${NC}"
    echo ""
    echo "可以继续下一步，但建议修复失败的镜像"
else
    echo -e "${GREEN}✓ 所有镜像构建成功${NC}"
fi

echo ""
echo "下一步: 运行 08-install-nomad-consul.sh 安装 Nomad 和 Consul"
echo ""
