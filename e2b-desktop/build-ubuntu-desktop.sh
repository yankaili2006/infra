#!/bin/bash
##############################################################################
# E2B Ubuntu Desktop Template Build Script
# Purpose: Build complete Ubuntu desktop environment with XFCE + VNC
# Date: 2026-01-22
##############################################################################

set -e

# 加载环境变量配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PCLOUD_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
if [ -f "$PCLOUD_ROOT/config/env.sh" ]; then
    source "$PCLOUD_ROOT/config/env.sh"
fi

# 设置路径（使用环境变量或默认值）
PCLOUD_HOME="${PCLOUD_HOME:-/home/primihub/pcloud}"
E2B_STORAGE_PATH="${E2B_STORAGE_PATH:-$PCLOUD_HOME/../e2b-storage}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║        E2B Ubuntu Desktop Template Build                      ║"
echo "║        (XFCE + LightDM + VNC)                                 ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Configuration
TEMPLATE_ID="ubuntu-desktop"
BUILD_ID=$(uuidgen)
KERNEL_VERSION="vmlinux-5.10.223"
FIRECRACKER_VERSION="v1.12.1_d990331"
DOCKERFILE_PATH="$PCLOUD_HOME/infra/e2b-desktop/templates/full-desktop.Dockerfile"

log_info "Template ID: $TEMPLATE_ID"
log_info "Build ID: $BUILD_ID"
log_info "Kernel: $KERNEL_VERSION"
log_info "Firecracker: $FIRECRACKER_VERSION"
log_info "Dockerfile: $DOCKERFILE_PATH"
echo ""

# Environment variables
log_info "Setting environment variables..."
export STORAGE_PROVIDER="Local"
export ARTIFACTS_REGISTRY_PROVIDER="Local"
export LOCAL_TEMPLATE_STORAGE_BASE_PATH="$E2B_STORAGE_PATH/e2b-template-storage"
export BUILD_CACHE_BUCKET_NAME="$E2B_STORAGE_PATH/e2b-build-cache"
export TEMPLATE_CACHE_DIR="$E2B_STORAGE_PATH/e2b-template-cache"
export SNAPSHOT_CACHE_DIR="$E2B_STORAGE_PATH/e2b-snapshot-cache"
export SHARED_CHUNK_CACHE_PATH="$E2B_STORAGE_PATH/e2b-chunk-cache"
export POSTGRES_CONNECTION_STRING="postgresql://postgres:postgres@localhost:5432/e2b?sslmode=disable"
export ENVD_PATH="$PCLOUD_HOME/infra/packages/orchestrator/bin/envd"
log_success "Environment set"

# Verify prerequisites
log_info "Verifying prerequisites..."

if ! lsmod | grep -q nbd; then
    log_error "NBD module not loaded. Run: sudo modprobe nbd max_part=8"
    exit 1
fi

if [ ! -f "$DOCKERFILE_PATH" ]; then
    log_error "Dockerfile not found: $DOCKERFILE_PATH"
    exit 1
fi

if [ ! -f "$ENVD_PATH" ]; then
    log_error "envd not found: $ENVD_PATH"
    exit 1
fi

log_success "Prerequisites OK"

# Create storage directories
log_info "Creating storage directories..."
mkdir -p "$LOCAL_TEMPLATE_STORAGE_BASE_PATH"
mkdir -p "$BUILD_CACHE_BUCKET_NAME"
mkdir -p "$TEMPLATE_CACHE_DIR"
mkdir -p "$SNAPSHOT_CACHE_DIR"
mkdir -p "$SHARED_CHUNK_CACHE_PATH"
log_success "Directories created"

# Build template
log_info "Building template with build-template..."
echo ""

sudo "$PCLOUD_HOME/infra/packages/orchestrator/bin/build-template" \
    -template "$TEMPLATE_ID" \
    -build "$BUILD_ID" \
    -kernel "$KERNEL_VERSION" \
    -firecracker "$FIRECRACKER_VERSION"

if [ $? -eq 0 ]; then
    log_success "Template built successfully"
else
    log_error "Template build failed"
    exit 1
fi
