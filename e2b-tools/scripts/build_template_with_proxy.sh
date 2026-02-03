#!/bin/bash

# Load environment variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PCLOUD_HOME="$(cd "$SCRIPT_DIR/../../.." && pwd)"
if [ -f "$PCLOUD_HOME/config/env.sh" ]; then
    source "$PCLOUD_HOME/config/env.sh"
fi

PCLOUD_HOME="${PCLOUD_HOME:-/home/primihub/pcloud}"
E2B_STORAGE_PATH="${E2B_STORAGE_PATH:-$PCLOUD_HOME/../e2b-storage}"

# 设置代理
export HTTP_PROXY="http://127.0.0.1:7890"
export HTTPS_PROXY="http://127.0.0.1:7890"
export http_proxy="http://127.0.0.1:7890"
export https_proxy="http://127.0.0.1:7890"
export NO_PROXY="localhost,127.0.0.1"
export no_proxy="localhost,127.0.0.1"

# Storage configuration
export STORAGE_PROVIDER="Local"
export ARTIFACTS_REGISTRY_PROVIDER="Local"

# Path configuration
export FIRECRACKER_VERSIONS_DIR="$PCLOUD_HOME/infra/packages/fc-versions/builds"
export HOST_ENVD_PATH="$PCLOUD_HOME/infra/packages/envd/bin/envd"
export HOST_KERNELS_DIR="$PCLOUD_HOME/infra/packages/fc-kernels"
export ORCHESTRATOR_BASE_PATH="$E2B_STORAGE_PATH/e2b-orchestrator"
export SANDBOX_DIR="$E2B_STORAGE_PATH/e2b-fc-vm"

# Cache directories
export LOCAL_TEMPLATE_STORAGE_BASE_PATH="$E2B_STORAGE_PATH/e2b-template-storage"
export TEMPLATE_BUCKET_NAME="$E2B_STORAGE_PATH/e2b-template-storage"
export BUILD_CACHE_BUCKET_NAME="$E2B_STORAGE_PATH/e2b-build-cache"
export SANDBOX_CACHE_DIR="$E2B_STORAGE_PATH/e2b-sandbox-cache"
export SNAPSHOT_CACHE_DIR="$E2B_STORAGE_PATH/e2b-snapshot-cache"
export TEMPLATE_CACHE_DIR="$E2B_STORAGE_PATH/e2b-template-cache"
export SHARED_CHUNK_CACHE_PATH="$E2B_STORAGE_PATH/e2b-chunk-cache"

# Huge Pages configuration
export ORCHESTRATOR_HUGE_PAGES="true"
export HUGE_PAGES="true"
export ORCHESTRATOR_ENABLE_HUGE_PAGES="true"

# Run build-template
"$PCLOUD_HOME/infra/packages/orchestrator/bin/build-template" \
  -template=base \
  -build=fcb118f7-4d32-45d0-a935-13f3e630ecbb \
  -kernel=vmlinux-6.1.158 \
  -firecracker=v1.12.1_d990331
