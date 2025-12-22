#!/bin/bash

# Storage configuration
export STORAGE_PROVIDER="Local"
export ARTIFACTS_REGISTRY_PROVIDER="Local"

# Path configuration
export FIRECRACKER_VERSIONS_DIR="/home/primihub/pcloud/infra/packages/fc-versions/builds"
export HOST_ENVD_PATH="/home/primihub/pcloud/infra/packages/envd/bin/envd"
export HOST_KERNELS_DIR="/home/primihub/pcloud/infra/packages/fc-kernels"
export ORCHESTRATOR_BASE_PATH="/home/primihub/e2b-storage/e2b-orchestrator"
export SANDBOX_DIR="/home/primihub/e2b-storage/e2b-fc-vm"

# Cache directories
export LOCAL_TEMPLATE_STORAGE_BASE_PATH="/mnt/sdb/e2b-storage/e2b-template-storage"
export TEMPLATE_BUCKET_NAME="/mnt/sdb/e2b-storage/e2b-template-storage"
export BUILD_CACHE_BUCKET_NAME="/home/primihub/e2b-storage/e2b-build-cache"
export SANDBOX_CACHE_DIR="/home/primihub/e2b-storage/e2b-sandbox-cache"
export SNAPSHOT_CACHE_DIR="/home/primihub/e2b-storage/e2b-snapshot-cache"
export TEMPLATE_CACHE_DIR="/home/primihub/e2b-storage/e2b-template-cache"
export SHARED_CHUNK_CACHE_PATH="/home/primihub/e2b-storage/e2b-chunk-cache"

# Huge Pages configuration
export ORCHESTRATOR_HUGE_PAGES="true"
export HUGE_PAGES="true"
export ORCHESTRATOR_ENABLE_HUGE_PAGES="true"

# Run build-template
/home/primihub/pcloud/infra/packages/orchestrator/bin/build-template \
  -template=base \
  -build=fcb118f7-4d32-45d0-a935-13f3e630ecbb \
  -kernel=vmlinux-6.1.158 \
  -firecracker=v1.12.1_d990331
