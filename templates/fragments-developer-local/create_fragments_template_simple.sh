#!/bin/bash
# Fragments Developer Template Creator - Simplified Version
# Avoids loop device conflicts by copying rootfs file directly

set -e

# 加载环境变量配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PCLOUD_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
if [ -f "$PCLOUD_ROOT/config/env.sh" ]; then
    source "$PCLOUD_ROOT/config/env.sh"
fi

# 设置路径（使用环境变量或默认值）
E2B_STORAGE_PATH="${E2B_STORAGE_PATH:-$PCLOUD_ROOT/../e2b-storage}"

TEMPLATE_ID="fragments-developer"
BASE_BUILD_ID="89767275-365d-4ee7-a699-2b857506552d"
NEW_BUILD_ID="$(uuidgen | tr '[:upper:]' '[:lower:]')"
STORAGE_BASE="$E2B_STORAGE_PATH/e2b-template-storage"
BASE_DIR="$STORAGE_BASE/$BASE_BUILD_ID"
NEW_DIR="$STORAGE_BASE/$NEW_BUILD_ID"
MOUNT_POINT="/mnt/e2b-rootfs-fragments"

echo "=================================================="
echo "Fragments Developer Template Creator (Simplified)"
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
echo "Primihub@2022." | sudo -S mkdir -p "$NEW_DIR"

# Copy base rootfs directly (no mounting needed)
echo "📋 Copying base rootfs file..."
echo "Primihub@2022." | sudo -S cp "$BASE_DIR/rootfs.ext4" "$NEW_DIR/rootfs.ext4"
echo "✅ Copied ($(du -h "$NEW_DIR/rootfs.ext4" | cut -f1))"
echo ""

# Expand the rootfs file by adding 3GB
echo "📋 Expanding rootfs by 3GB..."
echo "Primihub@2022." | sudo -S dd if=/dev/zero bs=1M count=3072 >> "$NEW_DIR/rootfs.ext4" 2>&1 | tail -3
echo "✅ Expanded to $(du -h "$NEW_DIR/rootfs.ext4" | cut -f1)"
echo ""

# Check and resize filesystem
echo "📋 Checking and resizing filesystem..."
echo "Primihub@2022." | sudo -S e2fsck -f -y "$NEW_DIR/rootfs.ext4" 2>&1 | tail -5
echo "Primihub@2022." | sudo -S resize2fs "$NEW_DIR/rootfs.ext4" 2>&1 | tail -3
echo "✅ Filesystem resized"
echo ""

# Mount the new rootfs
echo "🔧 Mounting new rootfs..."
echo "Primihub@2022." | sudo -S mkdir -p "$MOUNT_POINT"
echo "Primihub@2022." | sudo -S mount -o loop "$NEW_DIR/rootfs.ext4" "$MOUNT_POINT"
trap "echo '🔧 Unmounting...'; echo 'Primihub@2022.' | sudo -S umount $MOUNT_POINT 2>/dev/null || true; echo 'Primihub@2022.' | sudo -S rm -rf $MOUNT_POINT" EXIT
echo "✅ Mounted"
echo ""

# Check available space
echo "📊 Available space:"
df -h "$MOUNT_POINT" | tail -1
echo ""

# Setup chroot environment
echo "📦 Setting up chroot environment..."
echo "Primihub@2022." | sudo -S mount -t proc proc "$MOUNT_POINT/proc"
echo "Primihub@2022." | sudo -S mount -t sysfs sys "$MOUNT_POINT/sys"
echo "Primihub@2022." | sudo -S mount --bind /dev "$MOUNT_POINT/dev"
echo "Primihub@2022." | sudo -S mount --bind /dev/pts "$MOUNT_POINT/dev/pts"

cleanup_chroot() {
    echo "🔧 Cleaning up chroot mounts..."
    echo "Primihub@2022." | sudo -S umount "$MOUNT_POINT/dev/pts" 2>/dev/null || true
    echo "Primihub@2022." | sudo -S umount "$MOUNT_POINT/dev" 2>/dev/null || true
    echo "Primihub@2022." | sudo -S umount "$MOUNT_POINT/sys" 2>/dev/null || true
    echo "Primihub@2022." | sudo -S umount "$MOUNT_POINT/proc" 2>/dev/null || true
}
trap "cleanup_chroot; echo 'Primihub@2022.' | sudo -S umount $MOUNT_POINT 2>/dev/null || true; echo 'Primihub@2022.' | sudo -S rm -rf $MOUNT_POINT" EXIT

# Setup DNS for chroot
echo "Primihub@2022." | sudo -S cp /etc/resolv.conf "$MOUNT_POINT/etc/resolv.conf"
echo "✅ Chroot environment ready"
echo ""

# Install npm dependencies
echo "📦 Installing Next.js dependencies..."

# Create install script
cat > /tmp/install_nextjs.sh <<'INSTALL_EOF'
#!/bin/bash
set -e

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
cd /root

echo "→ Node.js version: $(node --version)"
echo "→ npm version: $(npm --version)"
echo ""

echo "→ Installing npm dependencies..."
npm install --legacy-peer-deps --no-audit --no-fund 2>&1 | tail -20

echo ""
echo "→ Verifying installation..."
ls -lh node_modules/ | head -5
echo "→ Total packages: $(ls node_modules/ | wc -l)"
echo "→ node_modules size: $(du -sh node_modules/ | cut -f1)"

echo "✅ Dependencies installed"
INSTALL_EOF

# Copy and run install script
echo "Primihub@2022." | sudo -S cp /tmp/install_nextjs.sh "$MOUNT_POINT/tmp/install_nextjs.sh"
echo "Primihub@2022." | sudo -S chmod +x "$MOUNT_POINT/tmp/install_nextjs.sh"

echo "→ Running npm install (this may take several minutes)..."
echo "Primihub@2022." | sudo -S chroot "$MOUNT_POINT" /tmp/install_nextjs.sh

echo "✅ Dependencies installed"
echo ""

# Cleanup
cleanup_chroot
echo "Primihub@2022." | sudo -S umount "$MOUNT_POINT"
echo "Primihub@2022." | sudo -S rm -rf "$MOUNT_POINT"

# Create metadata.json
echo "📋 Creating metadata.json..."
cat > "$NEW_DIR/metadata.json" <<META_EOF
{
  "templateID": "$TEMPLATE_ID",
  "buildID": "$NEW_BUILD_ID",
  "aliases": ["fragments-developer", "nextjs-developer"],
  "public": true,
  "cpuCount": 2,
  "memoryMB": 2048,
  "diskSizeMB": 0,
  "kernelVersion": "vmlinux-5.10",
  "firecrackerVersion": "v1.7.0-dev_8bb88311",
  "envdVersion": "0.2.0",
  "startCmd": "",
  "readyCheckCmd": "",
  "createdAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
META_EOF

echo "✅ Metadata created"
echo ""

echo "=================================================="
echo "✅ Template created successfully!"
echo "=================================================="
echo ""
echo "📋 Template details:"
echo "  Template ID:  $TEMPLATE_ID"
echo "  Build ID:     $NEW_BUILD_ID"
echo "  Location:     $NEW_DIR"
echo "  Rootfs size:  $(du -h "$NEW_DIR/rootfs.ext4" | cut -f1)"
echo ""
echo "📝 Next steps:"
echo "  1. Update database to use new build ID"
echo "  2. Clear template cache"
echo "  3. Test with: E2B_TEMPLATE_ID=fragments-developer e2b create"
echo ""
