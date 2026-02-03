#!/bin/bash

# Load environment variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PCLOUD_HOME="$(cd "$SCRIPT_DIR/../../.." && pwd)"
if [ -f "$PCLOUD_HOME/config/env.sh" ]; then
    source "$PCLOUD_HOME/config/env.sh"
fi

PCLOUD_HOME="${PCLOUD_HOME:-/home/primihub/pcloud}"
E2B_STORAGE_PATH="${E2B_STORAGE_PATH:-$PCLOUD_HOME/../e2b-storage}"

# Storage configuration
export STORAGE_PROVIDER="Local"
export ARTIFACTS_REGISTRY_PROVIDER="Local"

# Path configuration
FIRECRACKER_VERSIONS_DIR="${FIRECRACKER_VERSIONS_DIR:-$PCLOUD_HOME/infra/packages/fc-versions/builds}"
HOST_ENVD_PATH="${HOST_ENVD_PATH:-$PCLOUD_HOME/infra/packages/envd/bin/envd}"
HOST_KERNELS_DIR="${HOST_KERNELS_DIR:-$PCLOUD_HOME/infra/packages/fc-kernels}"
ORCHESTRATOR_BASE_PATH="${ORCHESTRATOR_BASE_PATH:-$E2B_STORAGE_PATH/e2b-orchestrator}"
SANDBOX_DIR="${SANDBOX_DIR:-$E2B_STORAGE_PATH/e2b-fc-vm}"

export FIRECRACKER_VERSIONS_DIR
export HOST_ENVD_PATH
export HOST_KERNELS_DIR
export ORCHESTRATOR_BASE_PATH
export SANDBOX_DIR

# Cache directories
LOCAL_TEMPLATE_STORAGE_BASE_PATH="${LOCAL_TEMPLATE_STORAGE_BASE_PATH:-$E2B_STORAGE_PATH/e2b-template-storage}"
TEMPLATE_BUCKET_NAME="${TEMPLATE_BUCKET_NAME:-$E2B_STORAGE_PATH/e2b-template-storage}"
BUILD_CACHE_BUCKET_NAME="${BUILD_CACHE_BUCKET_NAME:-$E2B_STORAGE_PATH/e2b-build-cache}"
SANDBOX_CACHE_DIR="${SANDBOX_CACHE_DIR:-$E2B_STORAGE_PATH/e2b-sandbox-cache}"
SNAPSHOT_CACHE_DIR="${SNAPSHOT_CACHE_DIR:-$E2B_STORAGE_PATH/e2b-snapshot-cache}"
TEMPLATE_CACHE_DIR="${TEMPLATE_CACHE_DIR:-$E2B_STORAGE_PATH/e2b-template-cache}"
SHARED_CHUNK_CACHE_PATH="${SHARED_CHUNK_CACHE_PATH:-$E2B_STORAGE_PATH/e2b-chunk-cache}"

export LOCAL_TEMPLATE_STORAGE_BASE_PATH
export TEMPLATE_BUCKET_NAME
export BUILD_CACHE_BUCKET_NAME
export SANDBOX_CACHE_DIR
export SNAPSHOT_CACHE_DIR
export TEMPLATE_CACHE_DIR
export SHARED_CHUNK_CACHE_PATH

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
