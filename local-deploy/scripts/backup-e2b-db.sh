#!/bin/bash
# E2B PostgreSQL数据库备份脚本

set -e

# 配置
BACKUP_DIR="${PCLOUD_HOME}/infra/local-deploy/db-backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DB_NAME="e2b"
DB_USER="postgres"
DB_HOST="127.0.0.1"
DB_PORT="5432"

# 创建备份目录
mkdir -p "$BACKUP_DIR"

echo "=== E2B数据库备份开始 ==="
echo "时间: $(date)"
echo "数据库: $DB_NAME"
echo "备份目录: $BACKUP_DIR"

# 1. 备份完整数据库（包含数据）
echo ""
echo "1. 备份完整数据库（schema + data）..."
PGPASSWORD=postgres pg_dump \
  -h "$DB_HOST" \
  -p "$DB_PORT" \
  -U "$DB_USER" \
  -d "$DB_NAME" \
  -F c \
  -f "$BACKUP_DIR/e2b_full_${TIMESTAMP}.dump"

echo "✓ 完整备份: e2b_full_${TIMESTAMP}.dump"

# 2. 备份纯SQL格式（便于查看和编辑）
echo ""
echo "2. 备份SQL格式..."
PGPASSWORD=postgres pg_dump \
  -h "$DB_HOST" \
  -p "$DB_PORT" \
  -U "$DB_USER" \
  -d "$DB_NAME" \
  --clean \
  --if-exists \
  -f "$BACKUP_DIR/e2b_full_${TIMESTAMP}.sql"

echo "✓ SQL备份: e2b_full_${TIMESTAMP}.sql"

# 3. 仅备份schema（用于初始化）
echo ""
echo "3. 备份schema（不含数据）..."
PGPASSWORD=postgres pg_dump \
  -h "$DB_HOST" \
  -p "$DB_PORT" \
  -U "$DB_USER" \
  -d "$DB_NAME" \
  --schema-only \
  --clean \
  --if-exists \
  -f "$BACKUP_DIR/e2b_schema_${TIMESTAMP}.sql"

echo "✓ Schema备份: e2b_schema_${TIMESTAMP}.sql"

# 4. 创建最新版本的符号链接
echo ""
echo "4. 创建最新版本链接..."
ln -sf "e2b_full_${TIMESTAMP}.dump" "$BACKUP_DIR/e2b_latest.dump"
ln -sf "e2b_full_${TIMESTAMP}.sql" "$BACKUP_DIR/e2b_latest.sql"
ln -sf "e2b_schema_${TIMESTAMP}.sql" "$BACKUP_DIR/e2b_schema_latest.sql"

echo "✓ 符号链接已创建"

# 5. 显示备份文件信息
echo ""
echo "=== 备份完成 ==="
echo ""
echo "备份文件列表:"
ls -lh "$BACKUP_DIR" | grep "${TIMESTAMP}\|latest"

echo ""
echo "备份文件大小:"
du -sh "$BACKUP_DIR"

echo ""
echo "✅ 备份成功完成！"
