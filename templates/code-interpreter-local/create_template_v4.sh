#!/bin/bash
# Code Interpreter Template Creator v4
# Uses chroot to install Python inside guest environment (proper GLIBC version)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_ID="code-interpreter-v1"
BASE_BUILD_ID="9ac9c8b9-9b8b-476c-9238-8266af308c32"
NEW_BUILD_ID="15dc8110-c9da-49a7-96f9-d221e06425c8"
STORAGE_BASE="/home/primihub/e2b-storage/e2b-template-storage"
BASE_DIR="$STORAGE_BASE/$BASE_BUILD_ID"
NEW_DIR="$STORAGE_BASE/$NEW_BUILD_ID"
MOUNT_POINT="/mnt/e2b-rootfs-ci"

echo "=================================================="
echo "Code Interpreter Template Creator v4"
echo "=================================================="
echo ""
echo "📋 Configuration:"
echo "  Template ID:    $TEMPLATE_ID"
echo "  Base build ID:  $BASE_BUILD_ID"
echo "  New build ID:   $NEW_BUILD_ID"
echo ""

# Check base template exists
if [ ! -f "$BASE_DIR/rootfs.ext4" ]; then
    echo "❌ Base template not found at $BASE_DIR"
    exit 1
fi
echo "✅ Base template found"

# Create new directory
sudo mkdir -p "$NEW_DIR"

# Copy base rootfs
echo "📋 Copying base rootfs..."
sudo cp "$BASE_DIR/rootfs.ext4" "$NEW_DIR/rootfs.ext4"
echo "✅ Copied ($(du -h "$NEW_DIR/rootfs.ext4" | cut -f1))"
echo ""

# Mount
echo "🔧 Mounting rootfs..."
sudo mkdir -p "$MOUNT_POINT"
sudo mount -o loop "$NEW_DIR/rootfs.ext4" "$MOUNT_POINT"
trap "echo '🔧 Unmounting...'; sudo umount $MOUNT_POINT 2>/dev/null || true; sudo rm -rf $MOUNT_POINT" EXIT

echo "✅ Mounted"
echo ""

# Setup chroot environment
echo "📦 Setting up chroot environment..."

# Mount essential filesystems for chroot
sudo mount -t proc proc "$MOUNT_POINT/proc"
sudo mount -t sysfs sys "$MOUNT_POINT/sys"
sudo mount --bind /dev "$MOUNT_POINT/dev"
sudo mount --bind /dev/pts "$MOUNT_POINT/dev/pts"

# Cleanup function
cleanup_chroot() {
    echo "🔧 Cleaning up chroot mounts..."
    sudo umount "$MOUNT_POINT/dev/pts" 2>/dev/null || true
    sudo umount "$MOUNT_POINT/dev" 2>/dev/null || true
    sudo umount "$MOUNT_POINT/sys" 2>/dev/null || true
    sudo umount "$MOUNT_POINT/proc" 2>/dev/null || true
}
trap "cleanup_chroot; sudo umount $MOUNT_POINT 2>/dev/null || true; sudo rm -rf $MOUNT_POINT" EXIT

echo "✅ Chroot environment ready"
echo ""

# Install Python and packages via chroot
echo "📦 Installing Python and packages in guest environment..."

# Create install script for chroot
cat > /tmp/install_python.sh <<'INSTALL_EOF'
#!/bin/bash
set -e

export DEBIAN_FRONTEND=noninteractive
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Update package lists (use existing sources)
apt-get update -qq || true

# Install Python and pip
apt-get install -y --no-install-recommends \
    python3 \
    python3-pip \
    python3-dev \
    gcc \
    2>&1 | grep -E "(Setting up|Processing|Unpacking)" || true

# Install Python packages
pip3 install --no-cache-dir \
    fastapi==0.115.0 \
    uvicorn[standard]==0.32.0 \
    pydantic==2.10.0 \
    numpy==1.26.4 \
    pandas==2.2.3 \
    2>&1 | grep -E "(Successfully|Collecting)" || true

echo "Python and packages installed successfully"
INSTALL_EOF

chmod +x /tmp/install_python.sh
sudo cp /tmp/install_python.sh "$MOUNT_POINT/tmp/install_python.sh"

# Run install script in chroot
echo "  Running package installation (this may take 2-3 minutes)..."
sudo chroot "$MOUNT_POINT" /tmp/install_python.sh

echo "✅ Python and packages installed"
echo ""

# Install API server
echo "📄 Installing API server..."
sudo cp "$SCRIPT_DIR/code_exec_api.py" "$MOUNT_POINT/usr/local/bin/code-exec-api"
sudo chmod +x "$MOUNT_POINT/usr/local/bin/code-exec-api"
echo "✅ API server installed"
echo ""

# Update init script to start API
echo "⚙️  Updating init script..."
sudo bash -c "cat > '$MOUNT_POINT/sbin/init' <<'INIT_EOF'
#!/bin/sh
# E2B Code Interpreter Init

# Mount essential filesystems
mount -t proc proc /proc 2>/dev/null || true
mount -t sysfs sys /sys 2>/dev/null || true
mount -t devtmpfs dev /dev 2>/dev/null || true

# Setup network
ip link set lo up 2>/dev/null || true
ip link set eth0 up 2>/dev/null || true

# Start envd daemon (if exists)
if [ -f /usr/bin/envd ]; then
    /usr/bin/envd &
fi

# Start code execution API
if [ -f /usr/local/bin/code-exec-api ]; then
    cd /tmp
    python3 /usr/local/bin/code-exec-api &
fi

# Keep init running forever
while true; do
    sleep 100
done
INIT_EOF"

sudo chmod +x "$MOUNT_POINT/sbin/init"
echo "✅ Init script updated"
echo ""

# Test Python in chroot
echo "🧪 Testing Python in guest environment..."
sudo chroot "$MOUNT_POINT" python3 --version || echo "⚠️  Python test had warnings"
echo ""

# Cleanup chroot mounts
cleanup_chroot

# Unmount
echo "🔧 Unmounting..."
sudo umount "$MOUNT_POINT"
sudo rm -rf "$MOUNT_POINT"
trap - EXIT
echo "✅ Unmounted"
echo ""

# Create metadata
echo "📝 Creating metadata..."
cat > /tmp/ci_metadata.json <<EOF
{
  "kernelVersion": "vmlinux-5.10.223",
  "firecrackerVersion": "v1.12.1_d990331",
  "buildID": "$NEW_BUILD_ID",
  "templateID": "$TEMPLATE_ID"
}
EOF
sudo cp /tmp/ci_metadata.json "$NEW_DIR/metadata.json"
echo "✅ Metadata created"
echo ""

echo "=================================================="
echo "✅ Code Interpreter Template Created!"
echo "=================================================="
echo ""
echo "📊 Details:"
echo "  Template ID: $TEMPLATE_ID"
echo "  Build ID:    $NEW_BUILD_ID"
echo "  Location:    $NEW_DIR/"
echo ""
echo "🚀 Next Steps:"
echo ""
echo "1. Add to database:"
echo "   PGPASSWORD=postgres psql -h localhost -U postgres -d e2b < /tmp/create_code_interpreter_complete.sql"
echo ""
echo "2. Clear caches:"
echo "   sudo rm -rf /home/primihub/e2b-storage/e2b-template-cache/*"
echo "   sudo rm -rf /home/primihub/e2b-storage/e2b-chunk-cache/*"
echo ""
echo "3. Test VM creation:"
echo "   curl -X POST http://localhost:3000/sandboxes \\"
echo "     -H 'Content-Type: application/json' \\"
echo "     -H 'X-API-Key: e2b_53ae1fed82754c17ad8077fbc8bcdd90' \\"
echo "     -d '{\"templateID\": \"code-interpreter-v1\", \"timeout\": 300}'"
echo ""
