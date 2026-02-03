#!/bin/bash
#
# E2B 完整备份与恢复工具
# 支持增量备份，可在新服务器快速恢复完整 E2B 环境
#
# 用法:
#   ./backup-e2b.sh              # 增量备份
#   ./backup-e2b.sh --full       # 完整备份
#   ./backup-e2b.sh --list       # 列出备份
#   ./backup-e2b.sh --restore    # 恢复到新服务器
#   ./backup-e2b.sh --restore-latest  # 自动恢复最新备份（无交互）
#

set -e

# 配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PCLOUD_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
PACKAGES_DIR="$PCLOUD_DIR/infra/packages"
JOBS_DIR="$SCRIPT_DIR/jobs"

# 存储路径 (支持符号链接)
E2B_STORAGE_BASE="/home/primihub/e2b-storage"
TEMPLATE_STORAGE="$E2B_STORAGE_BASE/e2b-template-storage"
TEMPLATE_CACHE="$E2B_STORAGE_BASE/e2b-template-cache"
CHUNK_CACHE="$E2B_STORAGE_BASE/e2b-chunk-cache"
BUILD_CACHE="$E2B_STORAGE_BASE/e2b-build-cache"

# 备份目录
BACKUP_DIR="/tmp/e2b-backup-$$"
OSS_BUCKET="oss://primihub"
OSS_PATH="backup/e2b"
HOSTNAME=$(hostname)
DATE=$(date +%Y%m%d_%H%M%S)
MARKER_FILE="$SCRIPT_DIR/.last_e2b_backup"

# 数据库
DB_HOST="127.0.0.1"
DB_USER="postgres"
DB_NAME="e2b"
export PGPASSWORD="postgres"

# 颜色
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[E2B]${NC} $1"; }
warn() { echo -e "${YELLOW}[E2B]${NC} $1"; }
err() { echo -e "${RED}[E2B]${NC} $1"; }
info() { echo -e "${BLUE}[E2B]${NC} $1"; }

# 检查文件是否需要备份 (增量)
need_backup() {
    local file="$1"
    [ ! -f "$MARKER_FILE" ] && return 0
    [ ! -f "$file" ] && return 1
    [ "$file" -nt "$MARKER_FILE" ] && return 0
    return 1
}

# 备份数据库 (完整备份，包含所有表)
backup_db() {
    log "备份数据库..."
    mkdir -p "$BACKUP_DIR/db"

    # 完整数据库备份
    pg_dump -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -F c -f "$BACKUP_DIR/db/e2b.dump" 2>/dev/null || {
        warn "数据库 e2b 不存在，尝试备份 postgres 数据库"
        pg_dump -h "$DB_HOST" -U "$DB_USER" -d "postgres" -F c -f "$BACKUP_DIR/db/postgres.dump" 2>/dev/null || true
    }

    # 导出关键表为 SQL (便于查看和手动恢复)
    for table in envs env_builds teams api_keys; do
        pg_dump -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -t "$table" --data-only -f "$BACKUP_DIR/db/${table}.sql" 2>/dev/null || true
    done

    # 导出数据库 schema
    pg_dump -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" --schema-only -f "$BACKUP_DIR/db/schema.sql" 2>/dev/null || true

    local db_size=$(du -sh "$BACKUP_DIR/db" 2>/dev/null | cut -f1)
    log "  数据库备份: $db_size"
}

# 备份配置文件
backup_config() {
    log "备份配置文件..."
    mkdir -p "$BACKUP_DIR/config/jobs"
    mkdir -p "$BACKUP_DIR/config/scripts"

    # 环境配置
    [ -f "$SCRIPT_DIR/.env.local" ] && cp "$SCRIPT_DIR/.env.local" "$BACKUP_DIR/config/"
    [ -f "$SCRIPT_DIR/nomad-dev.hcl" ] && cp "$SCRIPT_DIR/nomad-dev.hcl" "$BACKUP_DIR/config/"

    # Nomad jobs (重要!)
    for hcl in "$JOBS_DIR"/*.hcl; do
        [ -f "$hcl" ] && cp "$hcl" "$BACKUP_DIR/config/jobs/"
    done

    # 启动脚本
    for script in "$SCRIPT_DIR/scripts"/*.sh; do
        [ -f "$script" ] && cp "$script" "$BACKUP_DIR/config/scripts/"
    done

    log "  配置文件: $(ls "$BACKUP_DIR/config/jobs/"*.hcl 2>/dev/null | wc -l) 个 Nomad jobs"
}

# 备份二进制文件 (增量)
backup_binaries() {
    log "备份二进制文件..."
    mkdir -p "$BACKUP_DIR/bin"

    local bins=(
        "api/bin/api"
        "client-proxy/bin/client-proxy"
        "envd/bin/envd"
        "orchestrator/bin/orchestrator"
        "orchestrator/bin/build-template"
    )

    local count=0
    for bin in "${bins[@]}"; do
        local src="$PACKAGES_DIR/$bin"
        if [ -f "$src" ]; then
            if [ "$FORCE_FULL" = "true" ] || need_backup "$src"; then
                local name=$(basename "$bin")
                cp "$src" "$BACKUP_DIR/bin/$name"
                log "  + $name ($(du -h "$src" | cut -f1))"
                count=$((count + 1))
            fi
        fi
    done

    [ $count -eq 0 ] && log "  (无变更)" || true
}

# 备份 Firecracker 版本
backup_firecracker() {
    log "备份 Firecracker..."
    mkdir -p "$BACKUP_DIR/fc"

    local fc_dir="$PACKAGES_DIR/fc-versions/builds"
    if [ -d "$fc_dir" ]; then
        for ver in "$fc_dir"/*/; do
            [ -d "$ver" ] || continue
            local name=$(basename "$ver")
            if [ -f "$ver/firecracker" ]; then
                if [ "$FORCE_FULL" = "true" ] || need_backup "$ver/firecracker"; then
                    mkdir -p "$BACKUP_DIR/fc/$name"
                    cp "$ver/firecracker" "$BACKUP_DIR/fc/$name/"
                    [ -f "$ver/jailer" ] && cp "$ver/jailer" "$BACKUP_DIR/fc/$name/"
                    log "  + firecracker $name"
                fi
            fi
        done
    fi
}

# 备份内核
backup_kernels() {
    log "备份内核..."
    mkdir -p "$BACKUP_DIR/kernels"

    local kernel_dir="$PACKAGES_DIR/fc-kernels"
    for kdir in "$kernel_dir"/vmlinux-*/; do
        [ -d "$kdir" ] || continue
        local name=$(basename "$kdir")
        [[ "$name" == *".bak"* ]] && continue

        local vmlinux=$(find "$kdir" -name "vmlinux*.bin" -o -name "vmlinux-*" -type f 2>/dev/null | head -1)
        if [ -n "$vmlinux" ] && [ -f "$vmlinux" ]; then
            if [ "$FORCE_FULL" = "true" ] || need_backup "$vmlinux"; then
                mkdir -p "$BACKUP_DIR/kernels/$name"
                cp "$vmlinux" "$BACKUP_DIR/kernels/$name/"
                log "  + $name ($(du -h "$vmlinux" | cut -f1))"
            fi
        fi
    done
}

# 备份模板 (核心数据)
backup_templates() {
    log "备份模板..."
    mkdir -p "$BACKUP_DIR/templates"

    [ ! -d "$TEMPLATE_STORAGE" ] && { warn "模板目录不存在: $TEMPLATE_STORAGE"; return; }

    # 解析符号链接获取真实路径
    local real_storage=$(readlink -f "$TEMPLATE_STORAGE")

    for tdir in "$real_storage"/*/; do
        [ -d "$tdir" ] || continue
        local build_id=$(basename "$tdir")
        mkdir -p "$BACKUP_DIR/templates/$build_id"

        # metadata.json (必须)
        if [ -f "$tdir/metadata.json" ]; then
            cp "$tdir/metadata.json" "$BACKUP_DIR/templates/$build_id/"
            log "  + $build_id/metadata.json"
        fi

        # rootfs.ext4 (大文件，单独上传到 OSS)
        if [ -f "$tdir/rootfs.ext4" ] && [ ! -L "$tdir/rootfs.ext4" ]; then
            local rootfs_size=$(du -h "$tdir/rootfs.ext4" | cut -f1)
            local rootfs_oss="$OSS_BUCKET/$OSS_PATH/rootfs/${build_id}.ext4.gz"
            local rootfs_md5=$(md5sum "$tdir/rootfs.ext4" 2>/dev/null | cut -d' ' -f1)

            # 检查 OSS 上是否已有相同文件
            local remote_md5=""
            if command -v ossutil64 &>/dev/null; then
                remote_md5=$(ossutil64 stat "$rootfs_oss" 2>/dev/null | grep "X-Oss-Meta-Md5" | awk '{print $2}' || echo "")
            fi

            if [ "$rootfs_md5" != "$remote_md5" ] || [ "$FORCE_FULL" = "true" ]; then
                log "  上传 $build_id/rootfs.ext4 ($rootfs_size)..."
                if command -v ossutil64 &>/dev/null; then
                    # 先压缩到临时文件，再上传（ossutil64 不支持管道输入）
                    local tmp_gz="/tmp/rootfs-${build_id}.ext4.gz"
                    log "    压缩中..."
                    gzip -c "$tdir/rootfs.ext4" > "$tmp_gz"
                    local gz_size=$(du -h "$tmp_gz" | cut -f1)
                    log "    压缩完成 ($gz_size)，上传中..."
                    if ossutil64 cp "$tmp_gz" "$rootfs_oss" --meta "X-Oss-Meta-Md5:$rootfs_md5" -f; then
                        log "    ✅ rootfs 已上传到 OSS"
                    else
                        warn "    rootfs 上传失败"
                    fi
                    rm -f "$tmp_gz"
                else
                    warn "    ossutil64 未安装，跳过 rootfs 上传"
                fi
            else
                log "  = $build_id rootfs 未变化"
            fi
            echo "$rootfs_md5" > "$BACKUP_DIR/templates/$build_id/rootfs.md5"
        fi

        # memfile 和 snapfile (如果存在)
        for f in memfile snapfile; do
            if [ -f "$tdir/$f" ]; then
                cp "$tdir/$f" "$BACKUP_DIR/templates/$build_id/"
                log "  + $build_id/$f"
            fi
        done
    done
}

# 备份 envd 二进制
backup_envd() {
    log "备份 envd..."
    mkdir -p "$BACKUP_DIR/envd"

    local envd_path="$PACKAGES_DIR/envd/bin/envd"
    if [ -f "$envd_path" ]; then
        cp "$envd_path" "$BACKUP_DIR/envd/"
        log "  + envd ($(du -h "$envd_path" | cut -f1))"
    fi
}

# 上传备份包
upload_backup() {
    local backup_name="e2b-${HOSTNAME}-${DATE}.tar.gz"

    log "打包备份..."
    tar -czf "/tmp/$backup_name" -C "$BACKUP_DIR" .

    local size=$(du -h "/tmp/$backup_name" | cut -f1)

    if command -v ossutil64 &>/dev/null; then
        log "上传到 OSS..."
        ossutil64 cp "/tmp/$backup_name" "$OSS_BUCKET/$OSS_PATH/$backup_name" -f
        log "备份完成: $backup_name ($size)"
    else
        warn "ossutil64 未安装，备份保存在本地: /tmp/$backup_name"
    fi

    rm -f "/tmp/$backup_name"

    # 更新标记
    touch "$MARKER_FILE"

    log "备份完成!"
}

# 列出备份
list_backups() {
    log "E2B 备份列表:"
    echo ""

    if ! command -v ossutil64 &>/dev/null; then
        warn "ossutil64 未安装，无法列出 OSS 备份"
        return
    fi

    echo "配置备份:"
    ossutil64 ls "$OSS_BUCKET/$OSS_PATH/" 2>/dev/null | grep -E "e2b-.*\.tar\.gz" | \
        awk '{printf "  %-50s %s\n", $NF, $3}' || echo "  (无)"
    echo ""
    echo "Rootfs 镜像:"
    ossutil64 ls "$OSS_BUCKET/$OSS_PATH/rootfs/" 2>/dev/null | grep -E "\.gz$" | \
        awk '{printf "  %-50s %s\n", $NF, $3}' || echo "  (无)"
}

# 恢复备份
do_restore() {
    local auto_confirm="${1:-false}"

    log "开始恢复 E2B 环境..."

    if ! command -v ossutil64 &>/dev/null; then
        err "ossutil64 未安装，无法从 OSS 恢复"
        exit 1
    fi

    # 获取最新备份
    local latest=$(ossutil64 ls "$OSS_BUCKET/$OSS_PATH/" 2>/dev/null | \
        grep -E "e2b-.*\.tar\.gz" | tail -1 | awk '{print $NF}')
    [ -z "$latest" ] && { err "未找到备份"; exit 1; }

    log "最新备份: $(basename "$latest")"

    if [ "$auto_confirm" != "true" ]; then
        read -p "确认恢复? [y/N]: " confirm
        [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && { log "取消"; exit 0; }
    fi

    mkdir -p "$BACKUP_DIR"

    # 下载并解压
    log "下载备份..."
    ossutil64 cp "$latest" "/tmp/e2b-restore.tar.gz" -f
    tar -xzf "/tmp/e2b-restore.tar.gz" -C "$BACKUP_DIR"

    # 恢复数据库
    restore_db

    # 恢复配置
    restore_config

    # 恢复二进制
    restore_binaries

    # 恢复 Firecracker
    restore_firecracker

    # 恢复内核
    restore_kernels

    # 恢复模板
    restore_templates

    # 恢复 envd
    restore_envd

    # 创建存储目录结构
    create_storage_dirs

    rm -rf "$BACKUP_DIR" "/tmp/e2b-restore.tar.gz"

    log "恢复完成!"
    echo ""
    echo "下一步:"
    echo "  1. 启动基础设施: docker compose -f $SCRIPT_DIR/docker-compose.yml up -d"
    echo "  2. 启动 Nomad: $SCRIPT_DIR/scripts/start-nomad.sh"
    echo "  3. 部署服务: nomad job run $JOBS_DIR/orchestrator.hcl && nomad job run $JOBS_DIR/api.hcl"
    echo "  4. 或使用: pcloud up"
}

# 恢复数据库
restore_db() {
    if [ -f "$BACKUP_DIR/db/e2b.dump" ]; then
        log "恢复数据库..."
        # 创建数据库 (如果不存在)
        PGPASSWORD=postgres psql -h "$DB_HOST" -U "$DB_USER" -c "CREATE DATABASE e2b;" 2>/dev/null || true
        pg_restore -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c "$BACKUP_DIR/db/e2b.dump" 2>/dev/null || \
            warn "数据库恢复有警告 (可能表已存在)"
    elif [ -f "$BACKUP_DIR/db/postgres.dump" ]; then
        log "恢复 postgres 数据库..."
        pg_restore -h "$DB_HOST" -U "$DB_USER" -d "postgres" -c "$BACKUP_DIR/db/postgres.dump" 2>/dev/null || \
            warn "数据库恢复有警告"
    fi
}

# 恢复配置
restore_config() {
    if [ -d "$BACKUP_DIR/config" ]; then
        log "恢复配置..."
        [ -f "$BACKUP_DIR/config/.env.local" ] && cp "$BACKUP_DIR/config/.env.local" "$SCRIPT_DIR/"
        [ -f "$BACKUP_DIR/config/nomad-dev.hcl" ] && cp "$BACKUP_DIR/config/nomad-dev.hcl" "$SCRIPT_DIR/"

        # 恢复 Nomad jobs
        if [ -d "$BACKUP_DIR/config/jobs" ]; then
            mkdir -p "$JOBS_DIR"
            cp "$BACKUP_DIR/config/jobs/"*.hcl "$JOBS_DIR/" 2>/dev/null || true
            log "  恢复了 $(ls "$BACKUP_DIR/config/jobs/"*.hcl 2>/dev/null | wc -l) 个 Nomad jobs"
        fi

        # 恢复脚本
        if [ -d "$BACKUP_DIR/config/scripts" ]; then
            mkdir -p "$SCRIPT_DIR/scripts"
            cp "$BACKUP_DIR/config/scripts/"*.sh "$SCRIPT_DIR/scripts/" 2>/dev/null || true
            chmod +x "$SCRIPT_DIR/scripts/"*.sh 2>/dev/null || true
        fi
    fi
}

# 恢复二进制
restore_binaries() {
    if [ -d "$BACKUP_DIR/bin" ]; then
        log "恢复二进制文件..."
        mkdir -p "$PACKAGES_DIR/api/bin" "$PACKAGES_DIR/client-proxy/bin" \
                 "$PACKAGES_DIR/envd/bin" "$PACKAGES_DIR/orchestrator/bin"

        [ -f "$BACKUP_DIR/bin/api" ] && cp "$BACKUP_DIR/bin/api" "$PACKAGES_DIR/api/bin/"
        [ -f "$BACKUP_DIR/bin/client-proxy" ] && cp "$BACKUP_DIR/bin/client-proxy" "$PACKAGES_DIR/client-proxy/bin/"
        [ -f "$BACKUP_DIR/bin/envd" ] && cp "$BACKUP_DIR/bin/envd" "$PACKAGES_DIR/envd/bin/"
        [ -f "$BACKUP_DIR/bin/orchestrator" ] && cp "$BACKUP_DIR/bin/orchestrator" "$PACKAGES_DIR/orchestrator/bin/"
        [ -f "$BACKUP_DIR/bin/build-template" ] && cp "$BACKUP_DIR/bin/build-template" "$PACKAGES_DIR/orchestrator/bin/"

        chmod +x "$PACKAGES_DIR"/*/bin/* 2>/dev/null || true
    fi
}

# 恢复 Firecracker
restore_firecracker() {
    if [ -d "$BACKUP_DIR/fc" ]; then
        log "恢复 Firecracker..."
        for ver in "$BACKUP_DIR/fc"/*/; do
            [ -d "$ver" ] || continue
            local name=$(basename "$ver")
            mkdir -p "$PACKAGES_DIR/fc-versions/builds/$name"
            cp "$ver"/* "$PACKAGES_DIR/fc-versions/builds/$name/"
            chmod +x "$PACKAGES_DIR/fc-versions/builds/$name"/* 2>/dev/null || true
        done
    fi
}

# 恢复内核
restore_kernels() {
    if [ -d "$BACKUP_DIR/kernels" ]; then
        log "恢复内核..."
        for kdir in "$BACKUP_DIR/kernels"/*/; do
            [ -d "$kdir" ] || continue
            local name=$(basename "$kdir")
            mkdir -p "$PACKAGES_DIR/fc-kernels/$name"
            cp "$kdir"/* "$PACKAGES_DIR/fc-kernels/$name/"
        done
    fi
}

# 恢复模板
restore_templates() {
    if [ -d "$BACKUP_DIR/templates" ]; then
        log "恢复模板..."

        # 确保存储目录存在
        sudo mkdir -p "$TEMPLATE_STORAGE"

        for tdir in "$BACKUP_DIR/templates"/*/; do
            [ -d "$tdir" ] || continue
            local build_id=$(basename "$tdir")
            sudo mkdir -p "$TEMPLATE_STORAGE/$build_id"

            # metadata.json
            [ -f "$tdir/metadata.json" ] && sudo cp "$tdir/metadata.json" "$TEMPLATE_STORAGE/$build_id/"

            # memfile 和 snapfile
            [ -f "$tdir/memfile" ] && sudo cp "$tdir/memfile" "$TEMPLATE_STORAGE/$build_id/"
            [ -f "$tdir/snapfile" ] && sudo cp "$tdir/snapfile" "$TEMPLATE_STORAGE/$build_id/"

            # 下载 rootfs (如果有 md5 文件)
            if [ -f "$tdir/rootfs.md5" ]; then
                local rootfs_oss="$OSS_BUCKET/$OSS_PATH/rootfs/${build_id}.ext4.gz"
                if ossutil64 stat "$rootfs_oss" &>/dev/null; then
                    log "  下载 $build_id/rootfs.ext4..."
                    ossutil64 cp "$rootfs_oss" "/tmp/${build_id}.ext4.gz" -f
                    gunzip -c "/tmp/${build_id}.ext4.gz" | sudo tee "$TEMPLATE_STORAGE/$build_id/rootfs.ext4" > /dev/null
                    rm -f "/tmp/${build_id}.ext4.gz"
                fi
            fi
        done
    fi
}

# 恢复 envd
restore_envd() {
    if [ -d "$BACKUP_DIR/envd" ] && [ -f "$BACKUP_DIR/envd/envd" ]; then
        log "恢复 envd..."
        mkdir -p "$PACKAGES_DIR/envd/bin"
        cp "$BACKUP_DIR/envd/envd" "$PACKAGES_DIR/envd/bin/"
        chmod +x "$PACKAGES_DIR/envd/bin/envd"
    fi
}

# 创建存储目录结构
create_storage_dirs() {
    log "创建存储目录结构..."

    sudo mkdir -p "$E2B_STORAGE_BASE"
    sudo mkdir -p "$TEMPLATE_STORAGE"
    sudo mkdir -p "$TEMPLATE_CACHE"
    sudo mkdir -p "$CHUNK_CACHE"
    sudo mkdir -p "$BUILD_CACHE"
    sudo mkdir -p "$E2B_STORAGE_BASE/e2b-fc-vm"
    sudo mkdir -p "$E2B_STORAGE_BASE/e2b-orchestrator"
    sudo mkdir -p "$E2B_STORAGE_BASE/e2b-sandbox-cache"
    sudo mkdir -p "$E2B_STORAGE_BASE/e2b-snapshot-cache"
    sudo mkdir -p "$E2B_STORAGE_BASE/nomad-local"

    # 设置权限
    sudo chown -R $(whoami):$(whoami) "$E2B_STORAGE_BASE" 2>/dev/null || true
}

# 检查是否有变更需要备份
check_changes() {
    [ ! -f "$MARKER_FILE" ] && return 0

    # 检查数据库
    local db_check=$(PGPASSWORD=postgres psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -t -c \
        "SELECT MAX(created_at) FROM env_builds;" 2>/dev/null | tr -d ' ')

    # 检查关键文件
    for f in "$SCRIPT_DIR/.env.local" "$PACKAGES_DIR/orchestrator/bin/orchestrator" "$PACKAGES_DIR/api/bin/api"; do
        [ -f "$f" ] && [ "$f" -nt "$MARKER_FILE" ] && return 0
    done

    # 检查 Nomad jobs
    for f in "$JOBS_DIR"/*.hcl; do
        [ -f "$f" ] && [ "$f" -nt "$MARKER_FILE" ] && return 0
    done

    # 检查模板
    local real_storage=$(readlink -f "$TEMPLATE_STORAGE" 2>/dev/null || echo "$TEMPLATE_STORAGE")
    for tdir in "$real_storage"/*/; do
        [ -d "$tdir" ] || continue
        for f in "$tdir"/*; do
            [ -f "$f" ] && [ "$f" -nt "$MARKER_FILE" ] && return 0
        done
    done

    return 1
}

# 帮助
show_help() {
    cat << 'EOF'
E2B 完整备份与恢复工具

用法: backup-e2b.sh [选项]

选项:
  (无参数)        增量备份 (仅备份变更)
  --full          强制完整备份
  --list          列出 OSS 上的备份
  --restore       恢复到新服务器 (交互式)
  --restore-latest 自动恢复最新备份 (无交互)
  --check         检查是否有变更
  --help          显示帮助

备份内容:
  - PostgreSQL e2b 数据库 (完整备份 + 关键表 SQL)
  - 配置文件 (.env.local, nomad-dev.hcl)
  - Nomad jobs (api.hcl, orchestrator.hcl 等)
  - 启动脚本 (scripts/*.sh)
  - 二进制文件 (api, orchestrator, envd, client-proxy, build-template)
  - Firecracker 版本
  - 内核文件
  - 模板 (metadata + rootfs + memfile + snapfile)

新服务器恢复:
  1. 安装依赖: PostgreSQL, Docker, ossutil64, Go
  2. 配置 OSS: ossutil64 config
  3. 恢复: ./backup-e2b.sh --restore
  4. 启动: pcloud up

环境变量:
  OSS_BUCKET      OSS bucket 路径 (默认: oss://primihub)
  OSS_PATH        OSS 备份路径 (默认: backup/e2b)
EOF
}

# 清理
cleanup() { rm -rf "$BACKUP_DIR"; }
trap cleanup EXIT

# 主函数
main() {
    case "${1:-}" in
        --list)
            list_backups
            ;;
        --restore)
            do_restore false
            ;;
        --restore-latest)
            do_restore true
            ;;
        --check)
            if check_changes; then
                log "有变更需要备份"
                exit 0
            else
                log "无变更"
                exit 1
            fi
            ;;
        --full)
            FORCE_FULL=true
            log "开始完整备份..."
            mkdir -p "$BACKUP_DIR"
            backup_db
            backup_config
            backup_binaries
            backup_firecracker
            backup_kernels
            backup_envd
            backup_templates
            upload_backup
            ;;
        "")
            if ! check_changes; then
                log "无变更，跳过备份"
                exit 0
            fi
            log "开始增量备份..."
            mkdir -p "$BACKUP_DIR"
            backup_db
            backup_config
            backup_binaries
            backup_firecracker
            backup_kernels
            backup_envd
            backup_templates
            upload_backup
            ;;
        --help|-h)
            show_help
            ;;
        *)
            err "未知选项: $1"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
