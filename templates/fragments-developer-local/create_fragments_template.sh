#!/bin/bash
# Fragments Developer Template Creator
# Creates a template with pre-installed Next.js dependencies

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
BASE_BUILD_ID="89767275-365d-4ee7-a699-2b857506552d"  # Current fragments-developer
NEW_BUILD_ID="$(uuidgen | tr '[:upper:]' '[:lower:]')"
STORAGE_BASE="$E2B_STORAGE_PATH/e2b-template-storage"
BASE_DIR="$STORAGE_BASE/$BASE_BUILD_ID"
NEW_DIR="$STORAGE_BASE/$NEW_BUILD_ID"
MOUNT_POINT="/mnt/e2b-rootfs-fragments"
ROOTFS_SIZE="6G"  # Larger size to accommodate npm dependencies

echo "=================================================="
echo "Fragments Developer Template Creator"
echo "=================================================="
echo ""
echo "📋 Configuration:"
echo "  Template ID:    $TEMPLATE_ID"
echo "  Base build ID:  $BASE_BUILD_ID"
echo "  New build ID:   $NEW_BUILD_ID"
echo "  Rootfs size:    $ROOTFS_SIZE"
echo ""

# Check base template exists
if [ ! -f "$BASE_DIR/rootfs.ext4" ]; then
    echo "❌ Base template not found at $BASE_DIR"
    exit 1
fi
echo "✅ Base template found"

# Create new directory
echo "Primihub@2022." | sudo -S mkdir -p "$NEW_DIR"

# Create a new larger rootfs instead of copying
echo "📋 Creating new larger rootfs ($ROOTFS_SIZE)..."
echo "Primihub@2022." | sudo -S dd if=/dev/zero of="$NEW_DIR/rootfs.ext4" bs=1 count=0 seek=$ROOTFS_SIZE 2>/dev/null
echo "Primihub@2022." | sudo -S mkfs.ext4 -F "$NEW_DIR/rootfs.ext4" >/dev/null 2>&1
echo "✅ Created new rootfs"
echo ""

# Mount new rootfs
echo "🔧 Mounting new rootfs..."
echo "Primihub@2022." | sudo -S mkdir -p "$MOUNT_POINT"
echo "Primihub@2022." | sudo -S mount -o loop "$NEW_DIR/rootfs.ext4" "$MOUNT_POINT"
trap "echo '🔧 Unmounting...'; echo "Primihub@2022." | sudo -S umount $MOUNT_POINT 2>/dev/null || true; echo "Primihub@2022." | sudo -S rm -rf $MOUNT_POINT" EXIT
echo "✅ Mounted"
echo ""

# Mount base rootfs to copy from
BASE_MOUNT="/mnt/e2b-rootfs-base"
echo "Primihub@2022." | sudo -S mkdir -p "$BASE_MOUNT"
echo "Primihub@2022." | sudo -S mount -o loop,ro "$BASE_DIR/rootfs.ext4" "$BASE_MOUNT"
trap "echo "Primihub@2022." | sudo -S umount $BASE_MOUNT 2>/dev/null || true; echo "Primihub@2022." | sudo -S rm -rf $BASE_MOUNT; echo "Primihub@2022." | sudo -S umount $MOUNT_POINT 2>/dev/null || true; echo "Primihub@2022." | sudo -S rm -rf $MOUNT_POINT" EXIT

# Copy base rootfs contents
echo "📋 Copying base rootfs contents..."
echo "Primihub@2022." | sudo -S rsync -a "$BASE_MOUNT/" "$MOUNT_POINT/"
echo "✅ Copied"
echo ""

# Unmount base
echo "Primihub@2022." | sudo -S umount "$BASE_MOUNT"
echo "Primihub@2022." | sudo -S rm -rf "$BASE_MOUNT"

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
trap "cleanup_chroot; echo "Primihub@2022." | sudo -S umount $MOUNT_POINT 2>/dev/null || true; echo "Primihub@2022." | sudo -S rm -rf $MOUNT_POINT" EXIT

# Setup DNS for chroot
echo "Primihub@2022." | sudo -S cp /etc/resolv.conf "$MOUNT_POINT/etc/resolv.conf"
echo "✅ Chroot environment ready"
echo ""

# Install npm dependencies
echo "📦 Installing Next.js dependencies in guest environment..."

# Create install script for chroot
cat > /tmp/install_nextjs.sh <<'INSTALL_EOF'
#!/bin/bash
set -e

export DEBIAN_FRONTEND=noninteractive
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

echo "→ Checking Node.js and npm..."
node --version
npm --version

echo "→ Creating /root directory structure..."
cd /root

# Ensure package.json, next.config.js, and tsconfig.json exist
if [ ! -f package.json ]; then
    echo "→ Creating package.json..."
    cat > package.json <<'PKG_EOF'
{
  "name": "nextjs-app",
  "version": "0.1.0",
  "scripts": {
    "dev": "next dev -p 3000",
    "build": "next build",
    "start": "next start"
  },
  "dependencies": {
    "next": "14.2.5",
    "react": "^18",
    "react-dom": "^18",
    "typescript": "^5",
    "@types/node": "^20",
    "@types/react": "^18",
    "@types/react-dom": "^18"
  }
}
PKG_EOF
fi

if [ ! -f next.config.js ]; then
    echo "→ Creating next.config.js..."
    cat > next.config.js <<'NEXT_EOF'
/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
}
module.exports = nextConfig
NEXT_EOF
fi

if [ ! -f tsconfig.json ]; then
    echo "→ Creating tsconfig.json..."
    cat > tsconfig.json <<'TS_EOF'
{
  "compilerOptions": {
    "target": "es5",
    "lib": ["dom", "dom.iterable", "esnext"],
    "allowJs": true,
    "skipLibCheck": true,
    "strict": false,
    "forceConsistentCasingInFileNames": true,
    "noEmit": true,
    "incremental": true,
    "esModuleInterop": true,
    "module": "esnext",
    "moduleResolution": "node",
    "resolveJsonModule": true,
    "isolatedModules": true,
    "jsx": "preserve"
  },
  "include": ["next-env.d.ts", "**/*.ts", "**/*.tsx"],
  "exclude": ["node_modules"]
}
TS_EOF
fi

echo "→ Installing npm dependencies..."
npm install --legacy-peer-deps --no-audit --no-fund

echo "→ Verifying installation..."
ls -lh node_modules/ | head -10
du -sh node_modules/

echo "✅ Next.js dependencies installed successfully"
INSTALL_EOF

# Copy install script to chroot
echo "Primihub@2022." | sudo -S cp /tmp/install_nextjs.sh "$MOUNT_POINT/tmp/install_nextjs.sh"
echo "Primihub@2022." | sudo -S chmod +x "$MOUNT_POINT/tmp/install_nextjs.sh"

# Run install script in chroot
echo "→ Running npm install in chroot..."
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
echo "  1. Register template in database:"
echo "     PGPASSWORD=e2b psql -h localhost -U postgres -d e2b -c \\"
echo "       INSERT INTO templates (template_id, aliases, build_id, public, cpu_count, memory_mb) \\"
echo "       VALUES ('$TEMPLATE_ID', '{fragments-developer,nextjs-developer}', '$NEW_BUILD_ID', true, 2, 2048) \\"
echo "       ON CONFLICT (template_id) DO UPDATE SET build_id='$NEW_BUILD_ID';\\"
echo ""
echo "  2. Clear template cache:"
echo "     rm -rf $E2B_STORAGE_PATH/e2b-template-cache/$NEW_BUILD_ID"
echo ""
echo "  3. Test the template:"
echo "     E2B_TEMPLATE_ID=fragments-developer e2b create"
echo ""
