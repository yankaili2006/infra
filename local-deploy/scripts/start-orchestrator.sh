#!/bin/bash
# Orchestrator 启动脚本 - 从环境变量加载配置

# 设置默认值（如果环境变量未设置）
export PCLOUD_HOME="${PCLOUD_HOME:-/mnt/data1/pcloud}"
export E2B_STORAGE_PATH="${E2B_STORAGE_PATH:-/mnt/data1/e2b-storage}"

# 加载 PCloud 环境变量
if [ -f "$PCLOUD_HOME/config/env.sh" ]; then
    source "$PCLOUD_HOME/config/env.sh"
else
    echo "Error: $PCLOUD_HOME/config/env.sh not found"
    exit 1
fi

# 导出所有必需的环境变量
export FIRECRACKER_VERSIONS_DIR="$PCLOUD_HOME/infra/packages/fc-versions/builds"
export HOST_ENVD_PATH="$PCLOUD_HOME/infra/packages/envd/bin/envd"
export HOST_KERNELS_DIR="$PCLOUD_HOME/infra/packages/fc-kernels"

export ORCHESTRATOR_BASE_PATH="$E2B_STORAGE_PATH/e2b-orchestrator"
export SANDBOX_DIR="$E2B_STORAGE_PATH/e2b-fc-vm"
export LOCAL_TEMPLATE_STORAGE_BASE_PATH="$E2B_STORAGE_PATH/e2b-template-storage"
export BUILD_CACHE_BUCKET_NAME="$E2B_STORAGE_PATH/e2b-build-cache"
export SANDBOX_CACHE_DIR="$E2B_STORAGE_PATH/e2b-sandbox-cache"
export SNAPSHOT_CACHE_DIR="$E2B_STORAGE_PATH/e2b-snapshot-cache"
export TEMPLATE_CACHE_DIR="$E2B_STORAGE_PATH/e2b-template-cache"
export SHARED_CHUNK_CACHE_PATH="$E2B_STORAGE_PATH/e2b-chunk-cache"
export ORCHESTRATOR_LOCK_PATH="$E2B_STORAGE_PATH/e2b-orchestrator.lock"

# 启动 orchestrator
exec "$PCLOUD_HOME/infra/packages/orchestrator/bin/orchestrator" "$@"
