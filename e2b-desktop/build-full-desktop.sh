#!/bin/bash
##############################################################################
# E2B Full Desktop Template Build Script
# Purpose: Build complete desktop environment with xubuntu-desktop + lightdm
# Date: 2026-01-22
##############################################################################

set -e

# Load environment variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PCLOUD_HOME="${PCLOUD_HOME:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
source "$PCLOUD_HOME/config/env.sh" 2>/dev/null || true

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
echo "║        E2B Full Desktop Template Build                        ║"
echo "║        (Xubuntu + LightDM + VNC)                              ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Configuration
TEMPLATE_ID="full-desktop-xubuntu-001"
BUILD_ID=$(uuidgen)
KERNEL_VERSION="vmlinux-5.10.223"
FIRECRACKER_VERSION="v1.12.1_d990331"
DOCKERFILE_PATH="$PCLOUD_HOME/infra/e2b-desktop/templates/full-desktop.Dockerfile"

log_info "Template ID: $TEMPLATE_ID"
log_info "Build ID: $BUILD_ID"
log_info "Kernel: $KERNEL_VERSION"
log_info "Firecracker: $FIRECRACKER_VERSION"
echo ""

# Environment variables
log_info "Setting environment variables..."
E2B_STORAGE_PATH="${E2B_STORAGE_PATH:-$PCLOUD_HOME/../e2b-storage}"
export STORAGE_PROVIDER="Local"
export ARTIFACTS_REGISTRY_PROVIDER="Local"
export LOCAL_TEMPLATE_STORAGE_BASE_PATH="$E2B_STORAGE_PATH/e2b-template-storage"
export BUILD_CACHE_BUCKET_NAME="$E2B_STORAGE_PATH/e2b-build-cache"
export TEMPLATE_CACHE_DIR="$E2B_STORAGE_PATH/e2b-template-cache"
export SNAPSHOT_CACHE_DIR="$E2B_STORAGE_PATH/e2b-snapshot-cache"
export SHARED_CHUNK_CACHE_PATH="$E2B_STORAGE_PATH/e2b-chunk-cache"
export POSTGRES_CONNECTION_STRING="postgresql://postgres:postgres@localhost:5432/e2b?sslmode=disable"
export ENVD_PATH="$PCLOUD_HOME/infra/packages/envd/bin/envd"
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

cd "$PCLOUD_HOME/infra/packages/template-manager"

./build-template \
    --template-id "$TEMPLATE_ID" \
    --build-id "$BUILD_ID" \
    --dockerfile "$DOCKERFILE_PATH" \
    --kernel-version "$KERNEL_VERSION" \
    --firecracker-version "$FIRECRACKER_VERSION" \
    --cpu-count 2 \
    --memory-mb 4096 \
    --disk-size-mb 10240

if [ $? -eq 0 ]; then
    log_success "Template built successfully"
else
    log_error "Template build failed"
    exit 1
fi

# Insert database record
log_info "Inserting database record..."

TEMPLATE_DIR="$LOCAL_TEMPLATE_STORAGE_BASE_PATH/$BUILD_ID"
ROOTFS_SIZE=$(stat -f "%z" "$TEMPLATE_DIR/rootfs.ext4" 2>/dev/null || stat -c "%s" "$TEMPLATE_DIR/rootfs.ext4")

psql "$POSTGRES_CONNECTION_STRING" <<EOF
INSERT INTO templates (template_id, build_id, public, cpu_count, memory_mb, kernel_version, firecracker_version, created_at, updated_at)
VALUES (
    '$TEMPLATE_ID',
    '$BUILD_ID',
    false,
    2,
    4096,
    '$KERNEL_VERSION',
    '$FIRECRACKER_VERSION',
    NOW(),
    NOW()
)
ON CONFLICT (template_id) DO UPDATE SET
    build_id = EXCLUDED.build_id,
    cpu_count = EXCLUDED.cpu_count,
    memory_mb = EXCLUDED.memory_mb,
    kernel_version = EXCLUDED.kernel_version,
    firecracker_version = EXCLUDED.firecracker_version,
    updated_at = NOW();
EOF

if [ $? -eq 0 ]; then
    log_success "Database record inserted"
else
    log_warn "Database insert failed (may need manual insertion)"
fi

# Summary
echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                    BUILD COMPLETE                              ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
log_success "Template ID: $TEMPLATE_ID"
log_success "Build ID: $BUILD_ID"
log_success "Template path: $TEMPLATE_DIR"
log_success "Rootfs size: $ROOTFS_SIZE bytes"
echo ""
log_info "Next steps:"
echo "  1. Test with: python3 infra/e2b-desktop/test-full-desktop.py"
echo "  2. Connect VNC: localhost:5900 (password: e2bdesktop)"
echo "  3. Connect noVNC: http://localhost:6080/vnc.html"
echo ""
