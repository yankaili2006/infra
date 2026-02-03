#!/bin/bash
# Orchestrator Wrapper Script
# 使用PCLOUD_HOME环境变量来定位orchestrator二进制文件

# 设置默认的PCLOUD_HOME（如果未设置）
: ${PCLOUD_HOME:="/mnt/data1/pcloud"}

# 设置其他环境变量（基于PCLOUD_HOME）
export FIRECRACKER_VERSIONS_DIR="${PCLOUD_HOME}/infra/packages/fc-versions/builds"
export HOST_ENVD_PATH="${PCLOUD_HOME}/infra/packages/envd/bin/envd"
export HOST_KERNELS_DIR="${PCLOUD_HOME}/infra/packages/fc-kernels"

# 执行orchestrator
exec "${PCLOUD_HOME}/infra/packages/orchestrator/bin/orchestrator" "$@"
