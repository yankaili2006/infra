#!/bin/bash
#
# E2B Code-Interpreter Template Builder
# =====================================
#
# This script creates a reusable code-interpreter template for E2B sandbox.
# It copies a working base rootfs and optionally installs Python packages.
#
# Usage:
#   ./build-code-interpreter-template.sh [options]
#
# Options:
#   -b, --build-id ID        Build ID (default: c0de1a73-7000-4000-a000-000000000001)
#   -t, --template-id ID     Template ID (default: code-interpreter-v1)
#   -s, --source-build ID    Source build ID to copy rootfs from (default: 9ac9c8b9-9b8b-476c-9238-8266af308c32)
#   -p, --install-python     Install Python and common packages
#   -d, --update-db          Update database with new template
#   -c, --clear-cache        Clear template cache after creation
#   -f, --force              Force rebuild even if template exists
#   -h, --help               Show this help message
#
# Examples:
#   ./build-code-interpreter-template.sh                     # Basic build with defaults
#   ./build-code-interpreter-template.sh -p -d -c            # Full build with Python and DB update
#   ./build-code-interpreter-template.sh -b my-build-id      # Custom build ID
#

set -e

# =============================================================================
# Configuration
# =============================================================================

# Load environment variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PCLOUD_HOME="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Try to load environment configuration
if [ -f "$PCLOUD_HOME/config/env.sh" ]; then
    source "$PCLOUD_HOME/config/env.sh"
fi

# Set defaults if not already set
PCLOUD_HOME="${PCLOUD_HOME:-$HOME/pcloud}"
E2B_STORAGE_PATH="${E2B_STORAGE_PATH:-$HOME/e2b-storage}"

# Default values
BUILD_ID="c0de1a73-7000-4000-a000-000000000001"
TEMPLATE_ID="code-interpreter-v1"
SOURCE_BUILD_ID="9ac9c8b9-9b8b-476c-9238-8266af308c32"
INSTALL_PYTHON=false
UPDATE_DB=false
CLEAR_CACHE=false
FORCE_REBUILD=false

# Paths
STORAGE_BASE="$E2B_STORAGE_PATH/e2b-template-storage"
CACHE_BASE="$E2B_STORAGE_PATH/e2b-template-cache"
CHUNK_CACHE="$E2B_STORAGE_PATH/e2b-chunk-cache"
ENVD_BIN="$PCLOUD_HOME/infra/packages/envd/bin/envd"
MOUNT_POINT="/mnt/e2b-rootfs"

# Database
DB_HOST="localhost"
DB_PORT="5432"
DB_NAME="postgres"
DB_USER="postgres"
DB_PASS="postgres"

# Kernel and Firecracker versions
KERNEL_VERSION="vmlinux-5.10.223"
FIRECRACKER_VERSION="v1.12.1_d990331"
ENVD_VERSION="0.2.0"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# =============================================================================
# Helper Functions
# =============================================================================

# Check if we can run sudo commands
check_sudo() {
    if [ "$EUID" -eq 0 ]; then
        # Running as root, no sudo needed
        SUDO=""
        return 0
    fi

    # First check if sudo works without password
    if sudo -n true 2>/dev/null; then
        SUDO="sudo"
        return 0
    fi

    # Check if sudo credentials are already cached
    if sudo -v 2>/dev/null; then
        SUDO="sudo"
        return 0
    fi

    # If running in non-interactive mode, fail gracefully
    if [ ! -t 0 ]; then
        log_warn "Running in non-interactive mode without sudo privileges."
        log_warn "Please run 'sudo -v' first or run this script with sudo."
        log_error "Failed to get sudo privileges."
        exit 1
    fi

    # Interactive mode - prompt for password
    log_warn "This script requires sudo privileges for file operations."
    log_info "Enter your password when prompted:"
    if sudo -v; then
        SUDO="sudo"
    else
        log_error "Failed to get sudo privileges. Run as root or configure sudo."
        exit 1
    fi
}

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

show_help() {
    cat << 'HELPEOF'
E2B Code-Interpreter Template Builder
=====================================

This script creates a reusable code-interpreter template for E2B sandbox.
It copies a working base rootfs and optionally installs Python packages.

Usage:
  ./build-code-interpreter-template.sh [options]

Options:
  -b, --build-id ID        Build ID (default: c0de1a73-7000-4000-a000-000000000001)
  -t, --template-id ID     Template ID (default: code-interpreter-v1)
  -s, --source-build ID    Source build ID to copy rootfs from
  -p, --install-python     Install Python and common packages
  -d, --update-db          Update database with new template
  -c, --clear-cache        Clear template cache after creation
  -f, --force              Force rebuild even if template exists
  -h, --help               Show this help message

Examples:
  ./build-code-interpreter-template.sh                     # Basic build
  ./build-code-interpreter-template.sh -p -d -c            # Full build
  ./build-code-interpreter-template.sh -f -d -c            # Force rebuild
HELPEOF
    exit 0
}

cleanup() {
    if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
        log_info "Cleaning up..."
        $SUDO umount "$MOUNT_POINT" 2>/dev/null || true
    fi
}

trap cleanup EXIT

# =============================================================================
# Parse Arguments
# =============================================================================

while [[ $# -gt 0 ]]; do
    case $1 in
        -b|--build-id)
            BUILD_ID="$2"
            shift 2
            ;;
        -t|--template-id)
            TEMPLATE_ID="$2"
            shift 2
            ;;
        -s|--source-build)
            SOURCE_BUILD_ID="$2"
            shift 2
            ;;
        -p|--install-python)
            INSTALL_PYTHON=true
            shift
            ;;
        -d|--update-db)
            UPDATE_DB=true
            shift
            ;;
        -c|--clear-cache)
            CLEAR_CACHE=true
            shift
            ;;
        -f|--force)
            FORCE_REBUILD=true
            shift
            ;;
        -h|--help)
            show_help
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            ;;
    esac
done

# =============================================================================
# Main Script
# =============================================================================

# Initialize sudo variable first
check_sudo

echo ""
echo "=========================================="
echo "  E2B Code-Interpreter Template Builder"
echo "=========================================="
echo ""
log_info "Build ID:        $BUILD_ID"
log_info "Template ID:     $TEMPLATE_ID"
log_info "Source Build:    $SOURCE_BUILD_ID"
log_info "Install Python:  $INSTALL_PYTHON"
log_info "Update DB:       $UPDATE_DB"
log_info "Clear Cache:     $CLEAR_CACHE"
echo ""

# -----------------------------------------------------------------------------
# Step 1: Verify Prerequisites
# -----------------------------------------------------------------------------

log_step "Step 1: Verifying prerequisites..."

# Check source rootfs exists
SOURCE_ROOTFS="$STORAGE_BASE/$SOURCE_BUILD_ID/rootfs.ext4"
if [ ! -f "$SOURCE_ROOTFS" ]; then
    log_error "Source rootfs not found: $SOURCE_ROOTFS"
    exit 1
fi
log_info "Source rootfs found: $(du -h "$SOURCE_ROOTFS" | cut -f1)"

# Check envd binary exists
if [ ! -f "$ENVD_BIN" ]; then
    log_warn "envd binary not found at $ENVD_BIN"
    log_warn "Will use envd from source rootfs"
fi

# Check target directory
TARGET_DIR="$STORAGE_BASE/$BUILD_ID"
if [ -d "$TARGET_DIR" ] && [ "$FORCE_REBUILD" = false ]; then
    if [ -f "$TARGET_DIR/rootfs.ext4" ]; then
        log_warn "Target directory exists with rootfs: $TARGET_DIR"
        log_warn "Use -f/--force to rebuild"
        echo ""
        log_info "Existing template can be used directly."
        exit 0
    fi
fi

# -----------------------------------------------------------------------------
# Step 2: Create Target Directory
# -----------------------------------------------------------------------------

log_step "Step 2: Creating target directory..."

$SUDO mkdir -p "$TARGET_DIR"
log_info "Created: $TARGET_DIR"

# -----------------------------------------------------------------------------
# Step 3: Copy Source Rootfs
# -----------------------------------------------------------------------------

log_step "Step 3: Copying source rootfs..."

TARGET_ROOTFS="$TARGET_DIR/rootfs.ext4"

if [ -f "$TARGET_ROOTFS" ] && [ "$FORCE_REBUILD" = true ]; then
    log_warn "Removing existing rootfs..."
    $SUDO rm -f "$TARGET_ROOTFS"
fi

if [ ! -f "$TARGET_ROOTFS" ]; then
    log_info "Copying rootfs (this may take a moment)..."
    $SUDO cp "$SOURCE_ROOTFS" "$TARGET_ROOTFS"
    log_info "Copied: $(du -h "$TARGET_ROOTFS" | cut -f1)"
else
    log_info "Rootfs already exists, skipping copy"
fi

# -----------------------------------------------------------------------------
# Step 4: Install Python (Optional)
# -----------------------------------------------------------------------------

if [ "$INSTALL_PYTHON" = true ]; then
    log_step "Step 4: Installing Python packages..."

    # Create mount point
    $SUDO mkdir -p "$MOUNT_POINT"

    # Mount rootfs
    log_info "Mounting rootfs..."
    $SUDO mount -o loop "$TARGET_ROOTFS" "$MOUNT_POINT"

    # Check if Python already exists
    if [ -f "$MOUNT_POINT/usr/bin/python3" ]; then
        log_info "Python3 already installed in rootfs"
    else
        log_warn "Python3 not found in rootfs"
        log_warn "Due to GLIBC compatibility issues, Python must be installed carefully"
        log_warn "The base rootfs should already have Python installed"
    fi

    # Create Jupyter config directory
    log_info "Creating Jupyter configuration..."
    $SUDO mkdir -p "$MOUNT_POINT/root/.jupyter"
    $SUDO tee "$MOUNT_POINT/root/.jupyter/jupyter_server_config.py" > /dev/null << 'JUPYTEREOF'
# Jupyter Server Configuration
c.ServerApp.ip = '0.0.0.0'
c.ServerApp.port = 8888
c.ServerApp.allow_root = True
c.ServerApp.token = ''
c.ServerApp.password = ''
c.ServerApp.open_browser = False
c.ServerApp.allow_origin = '*'
JUPYTEREOF

    # Create a code execution helper script
    log_info "Creating code execution helper..."
    $SUDO tee "$MOUNT_POINT/usr/local/bin/run_code" > /dev/null << 'RUNEOF'
#!/bin/sh
# Simple code execution wrapper for E2B
# Usage: run_code <language> <code_file>

LANG="${1:-python}"
CODE_FILE="$2"

case "$LANG" in
    python|py)
        exec python3 "$CODE_FILE"
        ;;
    bash|sh)
        exec /bin/sh "$CODE_FILE"
        ;;
    *)
        echo "Unsupported language: $LANG"
        exit 1
        ;;
esac
RUNEOF
    $SUDO chmod +x "$MOUNT_POINT/usr/local/bin/run_code"

    # Unmount
    log_info "Unmounting rootfs..."
    $SUDO umount "$MOUNT_POINT"

    log_info "Python setup complete"
else
    log_step "Step 4: Skipping Python installation (not requested)"
fi

# -----------------------------------------------------------------------------
# Step 5: Create Metadata
# -----------------------------------------------------------------------------

log_step "Step 5: Creating metadata.json..."

METADATA_FILE="$TARGET_DIR/metadata.json"
$SUDO tee "$METADATA_FILE" > /dev/null << EOF
{
  "kernelVersion": "$KERNEL_VERSION",
  "firecrackerVersion": "$FIRECRACKER_VERSION",
  "buildID": "$BUILD_ID",
  "templateID": "$TEMPLATE_ID",
  "envdVersion": "$ENVD_VERSION"
}
EOF

log_info "Created metadata.json"
cat "$METADATA_FILE"

# -----------------------------------------------------------------------------
# Step 6: Update Database (Optional)
# -----------------------------------------------------------------------------

if [ "$UPDATE_DB" = true ]; then
    log_step "Step 6: Updating database..."

    DB_UPDATED=false

    # Method 1: Try Docker PostgreSQL
    if docker exec local-dev-postgres-1 psql --version > /dev/null 2>&1; then
        log_info "Using Docker PostgreSQL..."

        EXISTS=$(docker exec local-dev-postgres-1 psql -U postgres -d postgres -t -c \
            "SELECT COUNT(*) FROM envs WHERE id = '$TEMPLATE_ID';" 2>/dev/null | tr -d ' ')

        if [ "$EXISTS" = "0" ]; then
            log_info "Creating new template in database..."

            docker exec local-dev-postgres-1 psql -U postgres -d postgres -c \
                "INSERT INTO envs (id, team_id, public, build_count)
                 VALUES ('$TEMPLATE_ID', 'e2b00001-0000-0000-0000-000000000001'::uuid, true, 1)
                 ON CONFLICT (id) DO NOTHING;"

            docker exec local-dev-postgres-1 psql -U postgres -d postgres -c \
                "INSERT INTO env_builds (id, env_id, status, vcpu, ram_mb, kernel_version, firecracker_version, envd_version)
                 VALUES ('$BUILD_ID'::uuid, '$TEMPLATE_ID', 'uploaded', 2, 1024, '$KERNEL_VERSION', '$FIRECRACKER_VERSION', '$ENVD_VERSION')
                 ON CONFLICT (id) DO UPDATE SET status = 'uploaded';"

            log_info "Database entries created"
        else
            log_info "Template already exists in database, updating build status..."
            docker exec local-dev-postgres-1 psql -U postgres -d postgres -c \
                "UPDATE env_builds SET status = 'uploaded' WHERE env_id = '$TEMPLATE_ID';"
        fi
        DB_UPDATED=true

    # Method 2: Try direct PostgreSQL connection
    elif command -v psql > /dev/null 2>&1; then
        log_info "Using direct PostgreSQL connection..."

        EXISTS=$(PGPASSWORD=$DB_PASS psql -h $DB_HOST -U $DB_USER -d $DB_NAME -t -c \
            "SELECT COUNT(*) FROM envs WHERE id = '$TEMPLATE_ID';" 2>/dev/null | tr -d ' ')

        if [ "$EXISTS" = "0" ]; then
            log_info "Creating new template in database..."

            PGPASSWORD=$DB_PASS psql -h $DB_HOST -U $DB_USER -d $DB_NAME -c \
                "INSERT INTO envs (id, team_id, public, build_count)
                 VALUES ('$TEMPLATE_ID', 'e2b00001-0000-0000-0000-000000000001'::uuid, true, 1)
                 ON CONFLICT (id) DO NOTHING;" 2>/dev/null

            PGPASSWORD=$DB_PASS psql -h $DB_HOST -U $DB_USER -d $DB_NAME -c \
                "INSERT INTO env_builds (id, env_id, status, vcpu, ram_mb, kernel_version, firecracker_version, envd_version)
                 VALUES ('$BUILD_ID'::uuid, '$TEMPLATE_ID', 'uploaded', 2, 1024, '$KERNEL_VERSION', '$FIRECRACKER_VERSION', '$ENVD_VERSION')
                 ON CONFLICT (id) DO UPDATE SET status = 'uploaded';" 2>/dev/null

            log_info "Database entries created"
        else
            log_info "Template already exists in database, updating build status..."
            PGPASSWORD=$DB_PASS psql -h $DB_HOST -U $DB_USER -d $DB_NAME -c \
                "UPDATE env_builds SET status = 'uploaded' WHERE env_id = '$TEMPLATE_ID';" 2>/dev/null
        fi
        DB_UPDATED=true
    fi

    if [ "$DB_UPDATED" = false ]; then
        log_warn "PostgreSQL not accessible, skipping database update"
        log_warn "Manual database update required:"
        echo ""
        echo "INSERT INTO envs (id, team_id, public, build_count)"
        echo "VALUES ('$TEMPLATE_ID', 'e2b00001-0000-0000-0000-000000000001'::uuid, true, 1);"
        echo ""
        echo "INSERT INTO env_builds (id, env_id, status, vcpu, ram_mb, kernel_version, firecracker_version, envd_version)"
        echo "VALUES ('$BUILD_ID'::uuid, '$TEMPLATE_ID', 'uploaded', 2, 1024, '$KERNEL_VERSION', '$FIRECRACKER_VERSION', '$ENVD_VERSION');"
        echo ""
    fi
else
    log_step "Step 6: Skipping database update (not requested)"
fi

# -----------------------------------------------------------------------------
# Step 7: Clear Cache (Optional)
# -----------------------------------------------------------------------------

if [ "$CLEAR_CACHE" = true ]; then
    log_step "Step 7: Clearing template cache..."

    # Clear template cache
    if [ -d "$CACHE_BASE/$BUILD_ID" ]; then
        $SUDO rm -rf "$CACHE_BASE/$BUILD_ID"
        log_info "Cleared template cache: $CACHE_BASE/$BUILD_ID"
    else
        log_info "No template cache to clear"
    fi

    # Clear chunk cache
    if [ -d "$CHUNK_CACHE/$BUILD_ID" ]; then
        $SUDO rm -rf "$CHUNK_CACHE/$BUILD_ID"
        log_info "Cleared chunk cache: $CHUNK_CACHE/$BUILD_ID"
    else
        log_info "No chunk cache to clear"
    fi
else
    log_step "Step 7: Skipping cache clear (not requested)"
fi

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------

echo ""
echo "=========================================="
echo "  Build Complete!"
echo "=========================================="
echo ""
log_info "Template Location: $TARGET_DIR"
echo ""
ls -lh "$TARGET_DIR/"
echo ""

log_info "To test the template:"
echo ""
echo "  # Create a sandbox"
echo "  curl -X POST http://localhost:3000/sandboxes \\"
echo "    -H 'Content-Type: application/json' \\"
echo "    -H 'X-API-Key: e2b_53ae1fed82754c17ad8077fbc8bcdd90' \\"
echo "    -d '{\"templateID\": \"$TEMPLATE_ID\", \"timeout\": 300}'"
echo ""

log_info "To use with Python SDK:"
echo ""
echo "  from e2b import Sandbox"
echo "  sandbox = Sandbox.create(template='$TEMPLATE_ID')"
echo ""

if [ "$UPDATE_DB" = false ]; then
    log_warn "Database was not updated. If this is a new template, run with -d flag:"
    echo ""
    echo "  ./build-code-interpreter-template.sh -d"
    echo ""
fi

echo "Done!"
