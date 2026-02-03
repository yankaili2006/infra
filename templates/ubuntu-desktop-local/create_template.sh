#!/bin/bash
##############################################################################
# Ubuntu Desktop Template Creator
# Purpose: Create E2B template with full Ubuntu Desktop (GNOME) environment
# Based on: desktop-template configuration (Xvfb + x11vnc)
##############################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_ID="ubuntu-desktop-v1"
BASE_BUILD_ID="9ac9c8b9-9b8b-476c-9238-8266af308c32"
NEW_BUILD_ID=$(uuidgen)
STORAGE_BASE="/home/primihub/e2b-storage/e2b-template-storage"
BASE_DIR="$STORAGE_BASE/$BASE_BUILD_ID"
NEW_DIR="$STORAGE_BASE/$NEW_BUILD_ID"
MOUNT_POINT="/mnt/e2b-rootfs-ubuntu-desktop"

echo "=================================================="
echo "Ubuntu Desktop Template Creator"
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

# Copy base rootfs (expand size for desktop)
echo "📋 Copying and expanding rootfs..."
sudo cp "$BASE_DIR/rootfs.ext4" "$NEW_DIR/rootfs.ext4"
sudo truncate -s 15G "$NEW_DIR/rootfs.ext4"
sudo e2fsck -f -y "$NEW_DIR/rootfs.ext4" || true
sudo resize2fs "$NEW_DIR/rootfs.ext4"
echo "✅ Rootfs expanded to 15GB"
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
sudo mount -t proc proc "$MOUNT_POINT/proc"
sudo mount -t sysfs sys "$MOUNT_POINT/sys"
sudo mount --bind /dev "$MOUNT_POINT/dev"
sudo mount --bind /dev/pts "$MOUNT_POINT/dev/pts"

cleanup_chroot() {
    echo "🔧 Cleaning up chroot mounts..."
    sudo umount "$MOUNT_POINT/dev/pts" 2>/dev/null || true
    sudo umount "$MOUNT_POINT/dev" 2>/dev/null || true
    sudo umount "$MOUNT_POINT/sys" 2>/dev/null || true
    sudo umount "$MOUNT_POINT/proc" 2>/dev/null || true
}
trap "cleanup_chroot; sudo umount $MOUNT_POINT 2>/dev/null || true; sudo rm -rf $MOUNT_POINT" EXIT

sudo cp /etc/resolv.conf "$MOUNT_POINT/etc/resolv.conf"
echo "✅ Chroot environment ready"
echo ""

# Install desktop environment
echo "📦 Installing Ubuntu Desktop (this will take 10-20 minutes)..."

cat > /tmp/install_desktop.sh <<'INSTALL_EOF'
#!/bin/bash
set -e

export DEBIAN_FRONTEND=noninteractive
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

echo "→ Updating package lists..."
apt-get update -qq

echo "→ Installing Xvfb and x11vnc..."
apt-get install -y \
    xvfb \
    x11vnc \
    xterm

echo "→ Installing ubuntu-desktop (minimal)..."
apt-get install -y --no-install-recommends \
    ubuntu-desktop-minimal \
    gnome-session \
    gnome-terminal

echo "→ Installing additional tools..."
apt-get install -y \
    firefox \
    xdotool \
    wmctrl

echo "✅ Desktop environment installed"
INSTALL_EOF

chmod +x /tmp/install_desktop.sh
sudo cp /tmp/install_desktop.sh "$MOUNT_POINT/tmp/install_desktop.sh"

echo "  Running installation (this may take 10-20 minutes)..."
echo ""
sudo chroot "$MOUNT_POINT" /bin/bash /tmp/install_desktop.sh

echo ""
echo "✅ Desktop environment installed"
echo ""

# No GDM configuration needed - using Xvfb instead
echo "⚙️  Skipping GDM configuration (using Xvfb)"
echo ""

# Update init script (based on desktop-template)
echo "⚙️  Updating init script..."
sudo bash -c "cat > '$MOUNT_POINT/sbin/init' <<'INIT_EOF'
#!/bin/bash
# E2B Ubuntu Desktop Init - Based on desktop-template

set -e
exec > /dev/ttyS0 2>&1

echo \"=== [INIT] Starting E2B Ubuntu Desktop ===\"

# 1. Mount filesystems
mount -t proc proc /proc 2>/dev/null || true
mount -t sysfs sys /sys 2>/dev/null || true
mount -t devtmpfs dev /dev 2>/dev/null || true
mount -t devpts devpts /dev/pts 2>/dev/null || true
mount -t tmpfs tmpfs /tmp 2>/dev/null || true
mount -t tmpfs tmpfs /run 2>/dev/null || true

# 2. Configure cgroup v2
mkdir -p /sys/fs/cgroup
mount -t cgroup2 none /sys/fs/cgroup 2>/dev/null || true
echo \"+cpu +cpuset +io +memory +pids\" > /sys/fs/cgroup/cgroup.subtree_control 2>/dev/null || true

# 3. Configure network
ip link set lo up 2>/dev/null || true
ip link set eth0 up 2>/dev/null || true
sleep 2

# 4. Set environment variables
export USER=root
export HOME=/root
export DISPLAY=:1
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# 5. Start envd (most important!)
echo \"[INIT] Starting envd...\"
/usr/local/bin/envd &
sleep 3

# 6. Start Xvfb
echo \"[INIT] Starting Xvfb...\"
Xvfb :1 -screen 0 1920x1080x24 -ac +extension GLX +render -noreset &
sleep 2

# 7. Start x11vnc
echo \"[INIT] Starting x11vnc...\"
x11vnc -display :1 -forever -shared -rfbport 5900 -passwd e2bdesktop -noxdamage -noxfixes &
sleep 2

# 8. Start GNOME Session
echo \"[INIT] Starting GNOME Session...\"
DISPLAY=:1 dbus-launch gnome-session &
sleep 3

# 9. Start gnome-terminal
echo \"[INIT] Starting gnome-terminal...\"
DISPLAY=:1 gnome-terminal --geometry=100x30+50+50 &

echo \"[INIT] ✅ Ubuntu Desktop Ready\"
echo \"[INIT] VNC: port 5900, password: e2bdesktop\"

# Keep running
while true; do sleep 3600; done
INIT_EOF"

sudo chmod +x "$MOUNT_POINT/sbin/init"
echo "✅ Init script updated"
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
cat > /tmp/desktop_metadata.json <<EOF
{
  "kernelVersion": "vmlinux-5.10.223",
  "firecrackerVersion": "v1.12.1_d990331",
  "buildID": "$NEW_BUILD_ID",
  "templateID": "$TEMPLATE_ID",
  "envdVersion": "0.2.0"
}
EOF
sudo cp /tmp/desktop_metadata.json "$NEW_DIR/metadata.json"
echo "✅ Metadata created"
echo ""

# Update database
echo "📊 Updating database..."
PGPASSWORD=postgres psql -h localhost -U postgres -d e2b <<DBEOF
-- Insert or update env
INSERT INTO envs (id, public, created_at)
VALUES ('$TEMPLATE_ID', false, NOW())
ON CONFLICT (id) DO NOTHING;

-- Insert or update env_build
INSERT INTO env_builds (
    id,
    env_id,
    status,
    vcpu,
    ram_mb,
    kernel_version,
    firecracker_version,
    envd_version,
    created_at
)
VALUES (
    '$NEW_BUILD_ID',
    '$TEMPLATE_ID',
    'ready',
    4,
    8192,
    'vmlinux-5.10.223',
    'v1.12.1_d990331',
    '0.2.0',
    NOW()
)
ON CONFLICT (id) DO UPDATE SET
    status = EXCLUDED.status,
    vcpu = EXCLUDED.vcpu,
    ram_mb = EXCLUDED.ram_mb;
DBEOF

if [ $? -eq 0 ]; then
    echo "✅ Database updated"
else
    echo "⚠️  Database update failed (may need manual update)"
fi
echo ""

echo "=================================================="
echo "✅ Ubuntu Desktop Template Created!"
echo "=================================================="
echo ""
echo "📊 Details:"
echo "  Template ID: $TEMPLATE_ID"
echo "  Build ID:    $NEW_BUILD_ID"
echo "  Location:    $NEW_DIR/"
echo "  Size:        $(du -h "$NEW_DIR/rootfs.ext4" | cut -f1)"
echo ""
echo "🚀 Next Steps:"
echo ""
echo "1. Clear caches:"
echo "   sudo rm -rf /home/primihub/e2b-storage/e2b-template-cache/*"
echo "   sudo rm -rf /home/primihub/e2b-storage/e2b-chunk-cache/*"
echo ""
echo "2. Test VM creation:"
echo "   curl -X POST http://localhost:3000/sandboxes \\"
echo "     -H 'Content-Type: application/json' \\"
echo "     -H 'X-API-Key: e2b_53ae1fed82754c17ad8077fbc8bcdd90' \\"
echo "     -d '{\"templateID\": \"ubuntu-desktop-v1\", \"timeout\": 600}'"
echo ""
echo "3. Access desktop:"
echo "   VNC: localhost:5900 (password: e2bdesktop)"
echo "   noVNC: http://localhost:6080/vnc.html"
echo ""
