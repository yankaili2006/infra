#!/bin/bash
# API 启动脚本 - 从环境变量加载配置

# 设置默认值（如果环境变量未设置）
export PCLOUD_HOME="${PCLOUD_HOME:-/mnt/data1/pcloud}"
export E2B_STORAGE_PATH="${E2B_STORAGE_PATH:-/mnt/data1/e2b-storage}"

# 加载 PCloud 环境变量
if [ -f "$PCLOUD_HOME/config/env.sh" ]; then
    source "$PCLOUD_HOME/config/env.sh"
else
    echo "Warning: $PCLOUD_HOME/config/env.sh not found, using defaults"
fi

# 导出存储路径环境变量
export LOCAL_TEMPLATE_STORAGE_BASE_PATH="$E2B_STORAGE_PATH/e2b-template-storage"
export BUILD_CACHE_BUCKET_NAME="$E2B_STORAGE_PATH/e2b-build-cache"
export TEMPLATE_CACHE_DIR="$E2B_STORAGE_PATH/e2b-template-cache"

# 启动 API
exec "$PCLOUD_HOME/infra/packages/api/bin/api" "$@"
