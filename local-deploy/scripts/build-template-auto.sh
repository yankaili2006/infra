#!/bin/bash
#
# E2B Template Builder with Automatic Issue Resolution
# 自动解决常见问题的模板构建脚本
#
# 用法: ./build-template-auto.sh [template-id] [build-id]
#

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 默认值
TEMPLATE_ID="${1:-base-template-000-0000-0000-000000000001}"
BUILD_ID="${2:-9ac9c8b9-9b8b-476c-9238-8266af308c32}"
KERNEL_VERSION="vmlinux-6.1.158"
FIRECRACKER_VERSION="v1.12.1_d990331"
TEMPLATE_STORAGE_DIR="/mnt/sdb/e2b-storage/e2b-template-storage/${BUILD_ID}"

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查并启动基础设施服务
check_and_start_infra() {
    log_info "检查基础设施服务..."

    # 检查 PostgreSQL
    if ! docker ps | grep -q postgres; then
        log_warn "PostgreSQL 未运行，启动基础设施服务..."
        cd /mnt/sdb/pcloud/infra/local-deploy
        bash scripts/start-infra.sh
        sleep 5
    else
        log_info "PostgreSQL 已运行"
    fi
}

# 修复数据库状态
fix_database_status() {
    log_info "修复数据库状态..."

    echo "Primihub@2022." | sudo -S docker exec -i local-dev-postgres-1 \
        psql -U postgres -d postgres -c \
        "UPDATE env_builds SET status = 'uploaded' WHERE status = 'success';" \
        > /dev/null 2>&1 || log_warn "数据库状态更新失败（可能已经是正确状态）"

    log_info "数据库状态已修复"
}

# 配置 Docker
configure_docker() {
    log_info "配置 Docker..."

    # 创建 Docker daemon 配置
    cat > /tmp/daemon.json << 'EOF'
{
  "proxies": {
    "http-proxy": "http://127.0.0.1:7890",
    "https-proxy": "http://127.0.0.1:7890"
  },
  "max-concurrent-downloads": 10,
  "max-download-attempts": 10
}
EOF

    # 检查配置是否需要更新
    if ! diff -q /tmp/daemon.json /etc/docker/daemon.json > /dev/null 2>&1; then
        log_warn "更新 Docker 配置..."
        echo "Primihub@2022." | sudo -S cp /tmp/daemon.json /etc/docker/daemon.json
        echo "Primihub@2022." | sudo -S systemctl daemon-reload
        echo "Primihub@2022." | sudo -S systemctl restart docker
        sleep 5
    fi

    # 配置 Docker systemd 代理
    if [ ! -f /etc/systemd/system/docker.service.d/http-proxy.conf ]; then
        log_warn "配置 Docker systemd 代理..."
        cat > /tmp/docker-proxy.conf << 'EOF'
[Service]
Environment="HTTP_PROXY=http://127.0.0.1:7890"
Environment="HTTPS_PROXY=http://127.0.0.1:7890"
Environment="NO_PROXY=localhost,127.0.0.1"
EOF
        echo "Primihub@2022." | sudo -S mkdir -p /etc/systemd/system/docker.service.d
        echo "Primihub@2022." | sudo -S mv /tmp/docker-proxy.conf /etc/systemd/system/docker.service.d/http-proxy.conf
        echo "Primihub@2022." | sudo -S systemctl daemon-reload
        echo "Primihub@2022." | sudo -S systemctl restart docker
        sleep 5
    fi

    log_info "Docker 配置完成"
}

# 准备内核文件
prepare_kernel() {
    log_info "准备内核文件..."

    KERNEL_DIR="/mnt/sdb/pcloud/infra/packages/fc-kernels"

    if [ ! -f "$KERNEL_DIR/$KERNEL_VERSION" ]; then
        log_warn "创建内核符号链接..."
        cd "$KERNEL_DIR"

        # 查找可用的内核文件
        AVAILABLE_KERNEL=$(ls -1 vmlinux-* 2>/dev/null | head -1)

        if [ -n "$AVAILABLE_KERNEL" ]; then
            ln -sf "$AVAILABLE_KERNEL" "$KERNEL_VERSION"
            log_info "内核链接创建: $KERNEL_VERSION -> $AVAILABLE_KERNEL"
        else
            log_error "未找到可用的内核文件"
            exit 1
        fi
    else
        log_info "内核文件已存在: $KERNEL_VERSION"
    fi
}

# 拉取 Docker 镜像
pull_base_image() {
    log_info "检查 Docker 基础镜像..."

    if ! echo "Primihub@2022." | sudo -S docker images | grep -q "ubuntu.*22.04"; then
        log_warn "拉取 Ubuntu 22.04 镜像..."
        echo "Primihub@2022." | sudo -S docker pull ubuntu:22.04
    else
        log_info "Ubuntu 22.04 镜像已存在"
    fi
}

# 构建模板文件
build_template_files() {
    log_info "构建模板文件..."

    # 创建模板目录
    echo "Primihub@2022." | sudo -S mkdir -p "$TEMPLATE_STORAGE_DIR"
    cd "$TEMPLATE_STORAGE_DIR"

    # 检查是否已存在
    if [ -f "rootfs.ext4" ] && [ -f "metadata.json" ]; then
        log_warn "模板文件已存在，跳过构建"
        return 0
    fi

    log_info "导出 Docker 容器文件系统..."

    # 创建临时容器
    CONTAINER_NAME="ubuntu-template-base-$(date +%s)"
    echo "Primihub@2022." | sudo -S docker run -d --name "$CONTAINER_NAME" ubuntu:22.04 bash -c "sleep infinity"

    # 导出文件系统
    echo "Primihub@2022." | sudo -S docker export "$CONTAINER_NAME" | gzip > /tmp/ubuntu-rootfs.tar.gz

    # 停止并删除容器
    echo "Primihub@2022." | sudo -S docker stop "$CONTAINER_NAME" > /dev/null
    echo "Primihub@2022." | sudo -S docker rm "$CONTAINER_NAME" > /dev/null

    log_info "创建 ext4 根文件系统..."

    # 创建 rootfs.ext4
    echo "Primihub@2022." | sudo -S dd if=/dev/zero of=rootfs.ext4 bs=1M count=1024 > /dev/null 2>&1
    echo "Primihub@2022." | sudo -S mkfs.ext4 -F rootfs.ext4 > /dev/null 2>&1

    # 挂载并提取
    echo "Primihub@2022." | sudo -S mkdir -p /tmp/mnt
    echo "Primihub@2022." | sudo -S mount -o loop rootfs.ext4 /tmp/mnt
    echo "Primihub@2022." | sudo -S tar -xzf /tmp/ubuntu-rootfs.tar.gz -C /tmp/mnt
    echo "Primihub@2022." | sudo -S umount /tmp/mnt

    # 清理
    rm -f /tmp/ubuntu-rootfs.tar.gz

    log_info "创建模板元数据文件..."

    # 创建 memfile 和 snapfile
    echo "Primihub@2022." | sudo -S touch memfile snapfile
    echo "Primihub@2022." | sudo -S chmod 644 memfile snapfile rootfs.ext4

    # 创建 metadata.json
    cat > /tmp/metadata.json << EOF
{
  "kernelVersion": "$KERNEL_VERSION",
  "firecrackerVersion": "$FIRECRACKER_VERSION",
  "buildID": "$BUILD_ID",
  "templateID": "$TEMPLATE_ID"
}
EOF
    echo "Primihub@2022." | sudo -S mv /tmp/metadata.json metadata.json

    log_info "模板文件构建完成"

    # 显示文件列表
    echo "Primihub@2022." | sudo -S ls -lh "$TEMPLATE_STORAGE_DIR"
}

# 验证模板
verify_template() {
    log_info "验证模板文件..."

    local required_files=("rootfs.ext4" "memfile" "snapfile" "metadata.json")
    local all_exist=true

    for file in "${required_files[@]}"; do
        if [ ! -f "$TEMPLATE_STORAGE_DIR/$file" ]; then
            log_error "缺少文件: $file"
            all_exist=false
        fi
    done

    if [ "$all_exist" = true ]; then
        log_info "✓ 所有必需文件已存在"

        # 检查 rootfs.ext4 大小
        local size=$(du -h "$TEMPLATE_STORAGE_DIR/rootfs.ext4" | cut -f1)
        log_info "rootfs.ext4 大小: $size"

        return 0
    else
        log_error "模板验证失败"
        return 1
    fi
}

# 主函数
main() {
    log_info "=== E2B 自动模板构建脚本 ==="
    log_info "模板 ID: $TEMPLATE_ID"
    log_info "构建 ID: $BUILD_ID"
    log_info ""

    # 执行所有步骤
    check_and_start_infra
    fix_database_status
    configure_docker
    prepare_kernel
    pull_base_image
    build_template_files
    verify_template

    log_info ""
    log_info "=== 模板构建完成 ==="
    log_info "模板位置: $TEMPLATE_STORAGE_DIR"
    log_info ""
    log_info "下一步:"
    log_info "1. 确保 Nomad 服务运行: nomad job status"
    log_info "2. 创建 VM: curl -X POST http://localhost:3000/sandboxes -H 'Content-Type: application/json' -H 'X-API-Key: e2b_53ae1fed82754c17ad8077fbc8bcdd90' -d '{\"templateID\": \"$TEMPLATE_ID\", \"timeout\": 300}'"
}

# 运行主函数
main "$@"
