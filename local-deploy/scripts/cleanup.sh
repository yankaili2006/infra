#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=========================================="
echo "E2B 本地部署 - 清理临时数据"
echo "=========================================="
echo ""

echo -e "${RED}警告: 此操作将删除以下数据:${NC}"
echo "  - 沙箱缓存"
echo "  - 快照缓存"
echo "  - 模板缓存"
echo "  - Chunk 缓存"
echo "  - Nomad 数据"
echo "  - Consul 数据"
echo "  - 日志文件"
echo ""
echo -e "${YELLOW}注意: 模板存储和数据库数据不会被删除${NC}"
echo ""

read -p "确定要继续吗? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "已取消"
    exit 0
fi

echo ""

# 确保服务已停止
echo "检查服务状态..."
if pgrep -x "nomad\|consul" > /dev/null; then
    echo -e "${YELLOW}⚠${NC} 检测到运行中的服务"
    echo "建议先停止服务: bash stop-all.sh"
    read -p "是否继续清理? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "已取消"
        exit 0
    fi
fi
echo ""

# 定义要清理的目录
declare -a CACHE_DIRS=(
    "/mnt/sdb/e2b-storage/e2b-sandbox-cache"
    "/mnt/sdb/e2b-storage/e2b-snapshot-cache"
    "/mnt/sdb/e2b-storage/e2b-template-cache"
    "/mnt/sdb/e2b-storage/e2b-chunk-cache"
    "/mnt/sdb/e2b-storage/nomad-local"
    "/mnt/sdb/e2b-storage/consul-local"
    "/mnt/sdb/e2b-storage/logs"
    "/mnt/sdb/e2b-storage/e2b-fc-vm"
    "/mnt/sdb/e2b-storage/e2b-orchestrator"
)

# 清理缓存目录
echo "清理缓存目录..."
echo ""

for dir in "${CACHE_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        SIZE=$(du -sh "$dir" 2>/dev/null | cut -f1)
        echo -n "  清理 $dir ($SIZE)..."

        rm -rf "$dir"/*
        echo -e " ${GREEN}✓${NC}"
    else
        echo "  跳过 $dir (不存在)"
    fi
done

echo ""

# 清理 Docker 资源（可选）
echo "清理 Docker 资源..."
read -p "是否清理 Docker 未使用的资源? [y/N] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo "清理 Docker 镜像、容器、卷..."
    docker system prune -f || true
    echo -e "${GREEN}✓${NC} Docker 资源已清理"
fi
echo ""

# 清理构建缓存（可选）
echo "清理构建缓存..."
read -p "是否清理构建缓存? (不会删除模板存储) [y/N] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    if [ -d "/mnt/sdb/e2b-storage/e2b-build-cache" ]; then
        SIZE=$(du -sh "/mnt/sdb/e2b-storage/e2b-build-cache" 2>/dev/null | cut -f1)
        echo "  清理 /mnt/sdb/e2b-storage/e2b-build-cache ($SIZE)..."
        rm -rf /mnt/sdb/e2b-storage/e2b-build-cache/*
        echo -e "${GREEN}✓${NC} 构建缓存已清理"
    else
        echo "  构建缓存目录不存在"
    fi
fi
echo ""

# 完全重置（可选）
echo -e "${RED}完全重置 (包括模板和数据库)${NC}"
read -p "是否执行完全重置? 这将删除所有数据! [y/N] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    read -p "再次确认: 这将删除模板存储和数据库! [yes/NO] " -r
    if [[ $REPLY == "yes" ]]; then
        echo ""
        echo "执行完全重置..."

        # 停止 Docker 服务
        PROJECT_ROOT="/mnt/sdb/pcloud/infra"
        COMPOSE_DIR="$PROJECT_ROOT/packages/local-dev"

        if [ -f "$COMPOSE_DIR/docker-compose.yaml" ]; then
            cd "$COMPOSE_DIR"
            echo "  停止并删除 Docker 容器和卷..."
            docker compose down -v || true
            echo -e "${GREEN}✓${NC} Docker 服务和数据已删除"
        fi

        # 删除模板存储
        if [ -d "/mnt/sdb/e2b-storage/e2b-template-storage" ]; then
            SIZE=$(du -sh "/mnt/sdb/e2b-storage/e2b-template-storage" 2>/dev/null | cut -f1)
            echo "  删除模板存储 ($SIZE)..."
            rm -rf /mnt/sdb/e2b-storage/e2b-template-storage/*
            echo -e "${GREEN}✓${NC} 模板存储已清空"
        fi

        echo -e "${GREEN}✓${NC} 完全重置完成"
        echo ""
        echo "重新初始化:"
        echo "  bash 09-init-database.sh  # 重新初始化数据库"
    else
        echo "已取消完全重置"
    fi
fi
echo ""

# 显示清理后的磁盘空间
echo "=========================================="
echo "清理后的磁盘空间"
echo "=========================================="
echo ""

for dir in "${CACHE_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        SIZE=$(du -sh "$dir" 2>/dev/null | cut -f1)
        echo "  $dir: $SIZE"
    fi
done

echo ""
df -h /tmp | grep -E "Filesystem|/tmp"

echo ""
echo -e "${GREEN}✓ 清理完成${NC}"
echo ""

echo "提示:"
echo "  - 重新启动服务: bash start-all.sh"
echo "  - 查看磁盘使用: du -h --max-depth=1 /mnt/sdb/e2b-storage/e2b-*"
echo ""
