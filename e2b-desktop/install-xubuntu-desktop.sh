#!/bin/bash
##############################################################################
# E2B Xubuntu Desktop Installation - Ubuntu Desktop Environment
# Purpose: Install complete Xubuntu desktop into existing E2B ubuntu-desktop template
# Features: XFCE desktop, LightDM, VNC, noVNC
# Date: 2026-01-22
##############################################################################

set -e  # Exit on error

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
echo "║     E2B Xubuntu Desktop Installation                          ║"
echo "║     Complete Ubuntu Desktop Environment                        ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Configuration
UBUNTU_DESKTOP_BUILD_ID="0f617f41-7b55-4df6-99aa-d5a38a85cda4"
STORAGE_BASE="/home/primihub/e2b-storage/e2b-template-storage"
DESKTOP_ROOTFS="$STORAGE_BASE/$UBUNTU_DESKTOP_BUILD_ID/rootfs.ext4"
MOUNT_POINT="/mnt/e2b-ubuntu-desktop-rootfs"

log_info "Configuration:"
echo "  Build ID:     $UBUNTU_DESKTOP_BUILD_ID"
echo "  Rootfs:       $DESKTOP_ROOTFS"
echo "  Mount Point:  $MOUNT_POINT"
echo ""

# Step 1: Verify prerequisites
log_info "Step 1/7: Verifying prerequisites..."

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    log_error "This script must be run as root (use sudo)"
    exit 1
fi

# Check if rootfs exists
if [ ! -f "$DESKTOP_ROOTFS" ]; then
    log_error "Rootfs not found: $DESKTOP_ROOTFS"
    exit 1
fi
log_success "Rootfs exists ($(du -h "$DESKTOP_ROOTFS" | cut -f1))"

# Create mount point
mkdir -p "$MOUNT_POINT"

# Check if already mounted
if mountpoint -q "$MOUNT_POINT"; then
    log_warn "Mount point already in use, unmounting..."
    umount -l "$MOUNT_POINT" 2>/dev/null || true
fi

log_success "Prerequisites verified"
echo ""

# Step 2: Mount the rootfs
log_info "Step 2/7: Mounting rootfs..."

mount -o loop "$DESKTOP_ROOTFS" "$MOUNT_POINT"
log_success "Rootfs mounted at $MOUNT_POINT"
echo ""

# Step 3: Setup chroot environment
log_info "Step 3/7: Setting up chroot environment..."

mount --bind /dev "$MOUNT_POINT/dev"
mount --bind /proc "$MOUNT_POINT/proc"
mount --bind /sys "$MOUNT_POINT/sys"
mount --bind /dev/pts "$MOUNT_POINT/dev/pts"

log_success "Chroot environment ready"
echo ""

# Step 4: Install Xubuntu desktop
log_info "Step 4/7: Installing Xubuntu desktop (10-15 minutes)..."

# Create package installation script
cat > "$MOUNT_POINT/tmp/install-xubuntu.sh" <<'PKGINSTALL'
#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
export TZ=UTC

echo "Updating package lists..."
apt-get update

echo "Installing X11 and core packages..."
apt-get install -y \
    xorg \
    xvfb \
    x11-xserver-utils \
    x11-utils \
    x11vnc \
    dbus-x11

echo "Installing XFCE desktop environment..."
apt-get install -y \
    xfce4 \
    xfce4-goodies \
    xfce4-terminal

echo "Installing LightDM display manager..."
apt-get install -y \
    lightdm \
    lightdm-gtk-greeter

echo "Installing VNC and noVNC..."
apt-get install -y \
    novnc \
    websockify \
    python3-websockify

echo "Installing desktop applications..."
apt-get install -y \
    firefox \
    thunar \
    gedit \
    vim \
    nano \
    python3 \
    python3-pip \
    xdotool \
    wmctrl \
    scrot \
    imagemagick

echo "Cleaning up..."
apt-get clean
rm -rf /var/lib/apt/lists/*
rm -rf /tmp/*

echo "Desktop installation complete"
PKGINSTALL

chmod +x "$MOUNT_POINT/tmp/install-xubuntu.sh"

# Run installation in chroot
log_info "Running package installation (this will take 10-15 minutes)..."
chroot "$MOUNT_POINT" /tmp/install-xubuntu.sh

log_success "Xubuntu desktop installed"
echo ""

# Step 5: Configure VNC and LightDM
log_info "Step 5/7: Configuring display services..."

# Configure VNC password
mkdir -p "$MOUNT_POINT/root/.vnc"
chroot "$MOUNT_POINT" x11vnc -storepasswd e2bdesktop /root/.vnc/passwd

# Configure LightDM for autologin
mkdir -p "$MOUNT_POINT/etc/lightdm/lightdm.conf.d"
cat > "$MOUNT_POINT/etc/lightdm/lightdm.conf.d/50-e2b-autologin.conf" <<'LIGHTDM'
[Seat:*]
autologin-user=root
autologin-user-timeout=0
autologin-session=xfce
LIGHTDM

# Disable LightDM greeter screen lock
cat > "$MOUNT_POINT/root/.xsessionrc" <<'XSESSION'
# Disable screen saver and power management
xset s off
xset -dpms
xset s noblank
XSESSION

log_success "Display services configured"
echo ""

# Step 6: Create desktop startup script
log_info "Step 6/7: Creating Xubuntu startup script..."

cat > "$MOUNT_POINT/usr/local/bin/start-xubuntu-desktop.sh" <<'DESKTOPSTART'
#!/bin/sh
# E2B Xubuntu Desktop Startup Script

exec > /dev/ttyS0 2>&1

echo "=== E2B Xubuntu Desktop Starting ==="
date

# Set display and environment
export DISPLAY=:99
export XAUTHORITY=/root/.Xauthority
export XDG_RUNTIME_DIR=/tmp/runtime-root
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

# Clean up any existing X11 locks
rm -f /tmp/.X99-lock 2>/dev/null || true
rm -f /tmp/.X11-unix/X99 2>/dev/null || true

# Start D-Bus
echo "Starting D-Bus..."
mkdir -p /var/run/dbus
dbus-daemon --system --fork || true

# Start Xvfb (virtual display)
echo "Starting Xvfb..."
Xvfb :99 -screen 0 1920x1080x24 -ac +extension GLX +render -noreset > /var/log/xvfb.log 2>&1 &
XVFB_PID=$!
echo "Xvfb started with PID: $XVFB_PID"

# Wait for X server
sleep 3

# Verify X server
if ! xdpyinfo -display :99 >/dev/null 2>&1; then
    echo "ERROR: X server failed to start"
    return 1
fi
echo "X server verified"

# Start XFCE session
echo "Starting XFCE desktop..."
startxfce4 > /var/log/xfce.log 2>&1 &
XFCE_PID=$!
echo "XFCE started with PID: $XFCE_PID"

sleep 3

# Start VNC server
echo "Starting x11vnc server..."
x11vnc \
    -display :99 \
    -forever \
    -shared \
    -rfbport 5900 \
    -rfbauth /root/.vnc/passwd \
    -bg \
    -o /var/log/x11vnc.log

sleep 2
echo "VNC server started on port 5900"

# Start noVNC
echo "Starting noVNC..."
/usr/share/novnc/utils/novnc_proxy \
    --vnc localhost:5900 \
    --listen 6080 \
    > /var/log/novnc.log 2>&1 &
NOVNC_PID=$!
echo "noVNC started with PID: $NOVNC_PID on port 6080"

sleep 2

echo "=== E2B Xubuntu Desktop Ready ==="
echo "VNC: localhost:5900 (password: e2bdesktop)"
echo "noVNC: http://localhost:6080/vnc.html"
echo "Display: :99 (1920x1080x24)"
echo "Desktop: XFCE 4"
DESKTOPSTART

chmod +x "$MOUNT_POINT/usr/local/bin/start-xubuntu-desktop.sh"

log_success "Startup script created"
echo ""

# Step 7: Update init script
log_info "Step 7/7: Updating init script..."

# Backup original init
if [ -f "$MOUNT_POINT/sbin/init" ]; then
    cp "$MOUNT_POINT/sbin/init" "$MOUNT_POINT/sbin/init.backup-before-xubuntu"
fi

# Create new init with Xubuntu
cat > "$MOUNT_POINT/sbin/init" <<'NEWINIT'
#!/bin/sh
# E2B Init Script with Xubuntu Desktop

exec > /dev/ttyS0 2>&1

echo "=== E2B Guest Init Starting ==="

# Mount filesystems
mount -t proc proc /proc 2>/dev/null || true
mount -t sysfs sysfs /sys 2>/dev/null || true
mount -t devtmpfs devtmpfs /dev 2>/dev/null || true
mount -t devpts devpts /dev/pts 2>/dev/null || true

# Configure network
ip link set lo up 2>/dev/null || true
ip link set eth0 up 2>/dev/null || true

sleep 1

echo "=== Starting Xubuntu Desktop Environment ==="
/usr/local/bin/start-xubuntu-desktop.sh &

# Wait for desktop initialization
sleep 5

echo "=== Starting envd daemon ==="
/usr/local/bin/envd &

echo "=== Init complete: Xubuntu desktop and envd running ==="

# Keep init alive
while true; do
    sleep 100
done
NEWINIT

chmod +x "$MOUNT_POINT/sbin/init"

log_success "Init script updated"
echo ""

# Cleanup
log_info "Cleaning up..."

umount "$MOUNT_POINT/dev/pts" 2>/dev/null || true
umount "$MOUNT_POINT/dev" 2>/dev/null || true
umount "$MOUNT_POINT/proc" 2>/dev/null || true
umount "$MOUNT_POINT/sys" 2>/dev/null || true
umount "$MOUNT_POINT"

log_success "Rootfs unmounted"

# Clear caches
log_info "Clearing template caches..."
rm -rf /home/primihub/e2b-storage/e2b-template-cache/$UBUNTU_DESKTOP_BUILD_ID 2>/dev/null || true
rm -rf /home/primihub/e2b-storage/e2b-chunk-cache/$UBUNTU_DESKTOP_BUILD_ID 2>/dev/null || true

log_success "Caches cleared"
echo ""

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║     Xubuntu Desktop Installation Complete!                    ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

log_success "Build ID: $UBUNTU_DESKTOP_BUILD_ID"
log_success "Template: ubuntu-desktop"
log_success "Rootfs: $(du -h "$DESKTOP_ROOTFS" | cut -f1)"

echo ""
log_info "Installed components:"
echo "  ✓ XFCE 4 desktop environment"
echo "  ✓ LightDM display manager"
echo "  ✓ X11 (Xvfb virtual display)"
echo "  ✓ VNC server (x11vnc on port 5900)"
echo "  ✓ noVNC web client (port 6080)"
echo "  ✓ Desktop applications (Firefox, Thunar, etc.)"
echo ""

log_info "Next steps:"
echo "  1. Test VM creation:"
echo '     curl -X POST http://localhost:3000/sandboxes \'
echo '       -H "Content-Type: application/json" \'
echo '       -H "X-API-Key: e2b_53ae1fed82754c17ad8077fbc8bcdd90" \'
echo '       -d '"'"'{"templateID": "ubuntu-desktop", "timeout": 600}'"'"
echo ""
echo "  2. Access desktop via VNC:"
echo "     VNC client to: <VM-IP>:5900"
echo "     Password: e2bdesktop"
echo ""
