#!/bin/bash
#
# E2B Rootfs Creation Script
#
# This script automates the creation of E2B VM root filesystems.
# It uses the official build-template tool which properly configures systemd,
# envd service, and all required system components.
#
# Usage:
#   ./create-e2b-rootfs.sh <build-id> <template-id> [kernel-version] [firecracker-version]
#
# Example:
#   ./create-e2b-rootfs.sh 9ac9c8b9-9b8b-476c-9238-8266af308c32 base-template-000-0000-0000-000000000001
#

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ORCHESTRATOR_DIR="${INFRA_DIR}/packages/orchestrator"

# Default values
KERNEL_VERSION="${3:-vmlinux-5.10.223}"
FIRECRACKER_VERSION="${4:-v1.12.1_d990331}"

# Required arguments
BUILD_ID="${1:-}"
TEMPLATE_ID="${2:-}"

# Function to print colored messages
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Validate arguments
if [ -z "$BUILD_ID" ] || [ -z "$TEMPLATE_ID" ]; then
    print_error "Missing required arguments"
    echo "Usage: $0 <build-id> <template-id> [kernel-version] [firecracker-version]"
    echo ""
    echo "Example:"
    echo "  $0 9ac9c8b9-9b8b-476c-9238-8266af308c32 base-template-000-0000-0000-000000000001"
    exit 1
fi

print_info "========================================="
print_info "E2B Rootfs Creation Script"
print_info "========================================="
print_info "Build ID: $BUILD_ID"
print_info "Template ID: $TEMPLATE_ID"
print_info "Kernel: $KERNEL_VERSION"
print_info "Firecracker: $FIRECRACKER_VERSION"
print_info "========================================="

# Step 1: Check prerequisites
print_info "Step 1: Checking prerequisites..."

if ! command_exists docker; then
    print_error "Docker is not installed"
    exit 1
fi

if ! command_exists go; then
    print_error "Go is not installed"
    exit 1
fi

if ! lsmod | grep -q nbd; then
    print_warn "NBD kernel module not loaded, loading now..."
    if ! echo "Primihub@2022." | sudo -S modprobe nbd max_part=8 nbds_max=64 2>/dev/null; then
        print_error "Failed to load NBD kernel module"
        exit 1
    fi
    print_info "NBD kernel module loaded successfully"
else
    print_info "NBD kernel module already loaded"
fi

# Step 2: Set required environment variables
print_info "Step 2: Setting environment variables..."

export STORAGE_PROVIDER=Local
export ARTIFACTS_REGISTRY_PROVIDER=Local
export LOCAL_TEMPLATE_STORAGE_BASE_PATH=/home/primihub/e2b-storage/e2b-template-storage
export BUILD_CACHE_BUCKET_NAME=/home/primihub/e2b-storage/e2b-build-cache
export TEMPLATE_CACHE_DIR=/home/primihub/e2b-storage/e2b-template-cache
export POSTGRES_CONNECTION_STRING=${POSTGRES_CONNECTION_STRING:-"postgresql://postgres:postgres@localhost:5432/postgres?sslmode=disable"}

print_info "Environment variables set"

# Step 3: Build the build-template tool if not exists
print_info "Step 3: Building build-template tool..."

cd "$ORCHESTRATOR_DIR"

if [ ! -f "bin/build-template" ]; then
    print_info "Compiling build-template..."
    if ! go build -o bin/build-template ./cmd/build-template/; then
        print_error "Failed to compile build-template"
        exit 1
    fi
    print_info "build-template compiled successfully"
else
    print_info "build-template already exists"
fi

# Step 4: Create storage directories
print_info "Step 4: Creating storage directories..."

echo "Primihub@2022." | sudo -S mkdir -p "$LOCAL_TEMPLATE_STORAGE_BASE_PATH" 2>/dev/null
echo "Primihub@2022." | sudo -S mkdir -p "$BUILD_CACHE_BUCKET_NAME" 2>/dev/null
echo "Primihub@2022." | sudo -S mkdir -p "$TEMPLATE_CACHE_DIR" 2>/dev/null
echo "Primihub@2022." | sudo -S chown -R $(whoami):$(whoami) "$LOCAL_TEMPLATE_STORAGE_BASE_PATH" "$BUILD_CACHE_BUCKET_NAME" "$TEMPLATE_CACHE_DIR" 2>/dev/null || true

print_info "Storage directories created"

# Step 5: Run build-template
print_info "Step 5: Running build-template to create rootfs..."
print_warn "This may take several minutes..."

if ! ./bin/build-template \
    -build="$BUILD_ID" \
    -template="$TEMPLATE_ID" \
    -kernel="$KERNEL_VERSION" \
    -firecracker="$FIRECRACKER_VERSION"; then
    print_error "build-template failed"
    print_error "Check logs above for details"
    exit 1
fi

# Step 6: Verify rootfs creation
print_info "Step 6: Verifying rootfs creation..."

ROOTFS_PATH="$LOCAL_TEMPLATE_STORAGE_BASE_PATH/$BUILD_ID/rootfs.ext4"
METADATA_PATH="$LOCAL_TEMPLATE_STORAGE_BASE_PATH/$BUILD_ID/metadata.json"

if [ ! -f "$ROOTFS_PATH" ]; then
    print_error "rootfs.ext4 not found at $ROOTFS_PATH"
    exit 1
fi

if [ ! -f "$METADATA_PATH" ]; then
    print_error "metadata.json not found at $METADATA_PATH"
    exit 1
fi

ROOTFS_SIZE=$(du -h "$ROOTFS_PATH" | cut -f1)
print_info "✓ rootfs.ext4 exists ($ROOTFS_SIZE)"
print_info "✓ metadata.json exists"

# Step 7: Clear caches (optional but recommended)
print_info "Step 7: Clearing template caches..."

if [ -d "$TEMPLATE_CACHE_DIR/$BUILD_ID" ]; then
    echo "Primihub@2022." | sudo -S rm -rf "$TEMPLATE_CACHE_DIR/$BUILD_ID" 2>/dev/null
    print_info "Template cache cleared"
fi

# Step 8: Display summary
print_info "========================================="
print_info "✅ Rootfs creation completed successfully!"
print_info "========================================="
print_info "Template Location:"
print_info "  $LOCAL_TEMPLATE_STORAGE_BASE_PATH/$BUILD_ID/"
print_info ""
print_info "Files created:"
print_info "  - rootfs.ext4 ($ROOTFS_SIZE)"
print_info "  - metadata.json"
print_info "  - memfile (if generated)"
print_info "  - snapfile (if generated)"
print_info ""
print_info "Next steps:"
print_info "  1. Test VM creation:"
print_info "     curl -X POST http://localhost:3000/sandboxes \\"
print_info "       -H 'Content-Type: application/json' \\"
print_info "       -H 'X-API-Key: YOUR_API_KEY' \\"
print_info "       -d '{\"templateID\": \"$TEMPLATE_ID\", \"timeout\": 300}'"
print_info ""
print_info "  2. Check orchestrator logs:"
print_info "     nomad alloc logs \$(nomad job allocs orchestrator | grep running | awk '{print \$1}') 2>&1 | tail -100"
print_info "========================================="

cd "$SCRIPT_DIR"
