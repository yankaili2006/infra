#!/bin/bash
##############################################################################
# E2B Desktop Template Build Script
# Purpose: Build desktop template with X11 + VNC using official build-template
# Date: 2026-01-11
##############################################################################

set -e  # Exit on error

# Load environment variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PCLOUD_HOME="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source environment configuration
if [ -f "$PCLOUD_HOME/config/env.sh" ]; then
    source "$PCLOUD_HOME/config/env.sh"
else
    # Fallback defaults
    export PCLOUD_HOME="${PCLOUD_HOME:-/home/primihub/pcloud}"
    export E2B_STORAGE_PATH="${E2B_STORAGE_PATH:-$PCLOUD_HOME/../e2b-storage}"
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║        E2B Desktop Template Build                             ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Template configuration
TEMPLATE_ID="desktop-template-000-0000-0000-000000000001"
BUILD_ID="8f9398ba-14d1-469c-aa2e-169f890a2520"
KERNEL_VERSION="vmlinux-5.10.223"
FIRECRACKER_VERSION="v1.12.1_d990331"
DOCKERFILE_PATH="$PCLOUD_HOME/infra/e2b-desktop/templates/desktop.Dockerfile"

log_info "Template ID: $TEMPLATE_ID"
log_info "Build ID: $BUILD_ID"
log_info "Kernel: $KERNEL_VERSION"
log_info "Firecracker: $FIRECRACKER_VERSION"
echo ""

# Step 1: Set environment variables
log_info "Step 1/5: Setting environment variables..."

export STORAGE_PROVIDER="Local"
export ARTIFACTS_REGISTRY_PROVIDER="Local"
export LOCAL_TEMPLATE_STORAGE_BASE_PATH="$E2B_STORAGE_PATH/e2b-template-storage"
export BUILD_CACHE_BUCKET_NAME="$E2B_STORAGE_PATH/e2b-build-cache"
export TEMPLATE_CACHE_DIR="$E2B_STORAGE_PATH/e2b-template-cache"
export SNAPSHOT_CACHE_DIR="$E2B_STORAGE_PATH/e2b-snapshot-cache"
export SHARED_CHUNK_CACHE_PATH="$E2B_STORAGE_PATH/e2b-chunk-cache"
export POSTGRES_CONNECTION_STRING="postgresql://postgres:postgres@localhost:5432/e2b?sslmode=disable"
export ENVD_PATH="$PCLOUD_HOME/infra/packages/envd/bin/envd"

log_success "Environment variables set"

# Step 2: Verify prerequisites
log_info "Step 2/5: Verifying prerequisites..."

# Check NBD module
if ! lsmod | grep -q nbd; then
    log_error "NBD kernel module not loaded"
    log_info "Run: sudo modprobe nbd max_part=8 nbds_max=64"
    exit 1
fi
log_success "NBD module loaded"

# Check PostgreSQL
if ! PGPASSWORD=postgres psql -h localhost -U postgres -d e2b -c "SELECT 1" &>/dev/null; then
    log_error "PostgreSQL connection failed"
    exit 1
fi
log_success "PostgreSQL connection verified"

# Check Dockerfile exists
if [ ! -f "$DOCKERFILE_PATH" ]; then
    log_error "Dockerfile not found: $DOCKERFILE_PATH"
    exit 1
fi
log_success "Dockerfile found"

# Check build-template binary
BUILD_TEMPLATE_BIN="$PCLOUD_HOME/infra/packages/orchestrator/bin/build-template"
if [ ! -f "$BUILD_TEMPLATE_BIN" ]; then
    log_error "build-template binary not found: $BUILD_TEMPLATE_BIN"
    exit 1
fi
log_success "build-template binary found"

# Check envd binary
if [ ! -f "$ENVD_PATH" ]; then
    log_error "envd binary not found: $ENVD_PATH"
    exit 1
fi
log_success "envd binary found"

echo ""

# Step 3: Create storage directories
log_info "Step 3/5: Creating storage directories..."

mkdir -p "$LOCAL_TEMPLATE_STORAGE_BASE_PATH"
mkdir -p "$BUILD_CACHE_BUCKET_NAME"
mkdir -p "$TEMPLATE_CACHE_DIR"
mkdir -p "$SNAPSHOT_CACHE_DIR"
mkdir -p "$SHARED_CHUNK_CACHE_PATH"

log_success "Storage directories created"
echo ""

# Step 4: Run build-template
log_info "Step 4/5: Building desktop template..."
log_warn "This may take 10-30 minutes depending on your system..."
echo ""

cd "$PCLOUD_HOME/infra/packages/orchestrator"

# Run build-template with proper parameters
"$BUILD_TEMPLATE_BIN" \
    -build="$BUILD_ID" \
    -template="$TEMPLATE_ID" \
    -kernel="$KERNEL_VERSION" \
    -firecracker="$FIRECRACKER_VERSION" \
    -dockerfile="$DOCKERFILE_PATH" \
    2>&1 | tee /tmp/desktop-template-build.log

BUILD_EXIT_CODE=${PIPESTATUS[0]}

echo ""

if [ $BUILD_EXIT_CODE -ne 0 ]; then
    log_error "Template build failed with exit code $BUILD_EXIT_CODE"
    log_info "Check log: /tmp/desktop-template-build.log"
    exit 1
fi

log_success "Template build completed"
echo ""

# Step 5: Verify template files
log_info "Step 5/5: Verifying template files..."

TEMPLATE_DIR="$LOCAL_TEMPLATE_STORAGE_BASE_PATH/$BUILD_ID"

if [ ! -d "$TEMPLATE_DIR" ]; then
    log_error "Template directory not created: $TEMPLATE_DIR"
    exit 1
fi
log_success "Template directory exists"

# Check rootfs.ext4
if [ ! -f "$TEMPLATE_DIR/rootfs.ext4" ]; then
    log_error "rootfs.ext4 not found"
    exit 1
fi
ROOTFS_SIZE=$(du -h "$TEMPLATE_DIR/rootfs.ext4" | cut -f1)
log_success "rootfs.ext4 found ($ROOTFS_SIZE)"

# Check metadata.json
if [ ! -f "$TEMPLATE_DIR/metadata.json" ]; then
    log_error "metadata.json not found"
    exit 1
fi
log_success "metadata.json found"

# Display metadata
log_info "Template metadata:"
cat "$TEMPLATE_DIR/metadata.json" | jq '.'

echo ""

# Update database status
log_info "Updating database status to 'uploaded'..."
PGPASSWORD=postgres psql -h localhost -U postgres -d e2b -c "
UPDATE env_builds
SET status = 'uploaded', finished_at = NOW()
WHERE id = '$BUILD_ID';
" &>/dev/null

log_success "Database updated"
echo ""

# Clear caches to ensure fresh template is used
log_info "Clearing template caches..."
sudo rm -rf "$TEMPLATE_CACHE_DIR/$BUILD_ID" 2>/dev/null || true
sudo rm -rf "$SHARED_CHUNK_CACHE_PATH/$BUILD_ID" 2>/dev/null || true
log_success "Caches cleared"

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║        Desktop Template Build Complete!                       ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
log_success "Template ID: $TEMPLATE_ID"
log_success "Build ID: $BUILD_ID"
log_success "Template path: $TEMPLATE_DIR"
log_success "Rootfs size: $ROOTFS_SIZE"
echo ""
log_info "Next steps:"
echo "  1. Configure Python SDK for local API"
echo "  2. Run integration tests"
echo "  3. Test desktop features (VNC, mouse control, etc.)"
echo ""
