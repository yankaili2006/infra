#!/bin/bash
# E2B PostgreSQL数据库恢复/初始化脚本

set -e

# 配置
BACKUP_DIR="/mnt/data1/pcloud/infra/local-deploy/db-backups"
DB_NAME="e2b"
DB_USER="postgres"
DB_HOST="127.0.0.1"
DB_PORT="5432"

# 显示使用说明
usage() {
    echo "用法: $0 [backup_file]"
    echo ""
    echo "参数:"
    echo "  backup_file  - 备份文件路径（可选，默认使用最新备份）"
    echo ""
    echo "示例:"
    echo "  $0                                    # 使用最新备份"
    echo "  $0 e2b_full_20260201_123456.dump     # 使用指定备份"
    echo "  $0 e2b_full_20260201_123456.sql      # 使用SQL格式备份"
    exit 1
}

# 检查参数
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    usage
fi

echo "=== E2B数据库恢复/初始化 ==="
echo "时间: $(date)"

# 确定备份文件
if [ -n "$1" ]; then
    BACKUP_FILE="$1"
    # 如果不是绝对路径，在备份目录中查找
    if [ ! -f "$BACKUP_FILE" ]; then
        BACKUP_FILE="$BACKUP_DIR/$1"
    fi
else
    # 使用最新备份
    BACKUP_FILE="$BACKUP_DIR/e2b_latest.dump"
fi

# 检查备份文件是否存在
if [ ! -f "$BACKUP_FILE" ]; then
    echo "❌ 错误: 备份文件不存在: $BACKUP_FILE"
    echo ""
    echo "可用的备份文件:"
    ls -lh "$BACKUP_DIR" 2>/dev/null || echo "  (无备份文件)"
    exit 1
fi

echo "备份文件: $BACKUP_FILE"
echo "文件大小: $(du -h "$BACKUP_FILE" | cut -f1)"

# 检查数据库是否存在
echo ""
echo "检查数据库状态..."
DB_EXISTS=$(PGPASSWORD=postgres psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -tAc "SELECT 1 FROM pg_database WHERE datname='$DB_NAME'" 2>/dev/null || echo "")

if [ -n "$DB_EXISTS" ]; then
    echo "⚠️  数据库 '$DB_NAME' 已存在"
    read -p "是否要删除并重新创建? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "操作已取消"
        exit 0
    fi

    echo ""
    echo "删除现有数据库..."
    PGPASSWORD=postgres psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -c "DROP DATABASE IF EXISTS $DB_NAME;"
    echo "✓ 数据库已删除"
fi

# 创建数据库
echo ""
echo "创建数据库 '$DB_NAME'..."
PGPASSWORD=postgres psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -c "CREATE DATABASE $DB_NAME;"
echo "✓ 数据库已创建"

# 恢复数据
echo ""
echo "恢复数据..."

# 根据文件扩展名选择恢复方法
if [[ "$BACKUP_FILE" == *.dump ]]; then
    # 使用pg_restore恢复二进制格式
    echo "使用pg_restore恢复二进制备份..."
    PGPASSWORD=postgres pg_restore \
        -h "$DB_HOST" \
        -p "$DB_PORT" \
        -U "$DB_USER" \
        -d "$DB_NAME" \
        --no-owner \
        --no-acl \
        "$BACKUP_FILE"
else
    # 使用psql恢复SQL格式
    echo "使用psql恢复SQL备份..."
    PGPASSWORD=postgres psql \
        -h "$DB_HOST" \
        -p "$DB_PORT" \
        -U "$DB_USER" \
        -d "$DB_NAME" \
        -f "$BACKUP_FILE"
fi

echo "✓ 数据恢复完成"

# 验证恢复
echo ""
echo "验证数据库..."
TABLE_COUNT=$(PGPASSWORD=postgres psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -tAc "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public';")
echo "✓ 表数量: $TABLE_COUNT"

echo ""
echo "✅ 数据库恢复成功！"
