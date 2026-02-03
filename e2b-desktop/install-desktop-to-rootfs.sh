#!/bin/bash
##############################################################################
# E2B Desktop Installation - Manual Rootfs Modification
# Purpose: Install desktop environment into existing E2B base template
# Approach: Mount rootfs, install packages, configure startup scripts
# Date: 2026-01-11
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
echo "║     E2B Desktop Environment Installation                      ║"
echo "║     Modifying Existing Rootfs                                 ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Configuration
BASE_BUILD_ID="9ac9c8b9-9b8b-476c-9238-8266af308c32"
DESKTOP_BUILD_ID="8f9398ba-14d1-469c-aa2e-169f890a2520"
STORAGE_BASE="/home/primihub/e2b-storage/e2b-template-storage"
BASE_ROOTFS="$STORAGE_BASE/$BASE_BUILD_ID/rootfs.ext4"
DESKTOP_ROOTFS="$STORAGE_BASE/$DESKTOP_BUILD_ID/rootfs.ext4"
MOUNT_POINT="/mnt/e2b-desktop-rootfs"

log_info "Configuration:"
echo "  Base Build ID:    $BASE_BUILD_ID"
echo "  Desktop Build ID: $DESKTOP_BUILD_ID"
echo "  Base Rootfs:      $BASE_ROOTFS"
echo "  Desktop Rootfs:   $DESKTOP_ROOTFS"
echo "  Mount Point:      $MOUNT_POINT"
echo ""

# Step 1: Verify prerequisites
log_info "Step 1/8: Verifying prerequisites..."

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    log_error "This script must be run as root (use sudo)"
    exit 1
fi

# Check if base rootfs exists
if [ ! -f "$BASE_ROOTFS" ]; then
    log_error "Base rootfs not found: $BASE_ROOTFS"
    exit 1
fi
log_success "Base rootfs exists"

# Check if mount point exists or create it
if [ ! -d "$MOUNT_POINT" ]; then
    mkdir -p "$MOUNT_POINT"
    log_success "Created mount point: $MOUNT_POINT"
else
    log_success "Mount point exists"
fi

# Check if already mounted
if mountpoint -q "$MOUNT_POINT"; then
    log_warn "Mount point already in use, unmounting..."
    umount "$MOUNT_POINT"
fi

echo ""

# Step 2: Copy base rootfs to new build ID
log_info "Step 2/8: Creating desktop template directory..."

mkdir -p "$STORAGE_BASE/$DESKTOP_BUILD_ID"

if [ ! -f "$DESKTOP_ROOTFS" ]; then
    log_info "Copying base rootfs to desktop build ID (this may take 1-2 minutes)..."
    cp "$BASE_ROOTFS" "$DESKTOP_ROOTFS"
    log_success "Rootfs copied: $(du -h "$DESKTOP_ROOTFS" | cut -f1)"
else
    log_warn "Desktop rootfs already exists, using existing file"
fi

echo ""

# Step 3: Mount the rootfs
log_info "Step 3/8: Mounting rootfs..."

mount -o loop "$DESKTOP_ROOTFS" "$MOUNT_POINT"
log_success "Rootfs mounted at $MOUNT_POINT"

echo ""

# Step 4: Install desktop packages
log_info "Step 4/8: Installing desktop packages (this will take 5-10 minutes)..."

# Setup apt for chroot
log_info "Preparing chroot environment..."
mount --bind /dev "$MOUNT_POINT/dev"
mount --bind /proc "$MOUNT_POINT/proc"
mount --bind /sys "$MOUNT_POINT/sys"

# Prevent interactive prompts
export DEBIAN_FRONTEND=noninteractive

# Create package installation script
cat > "$MOUNT_POINT/tmp/install-desktop.sh" <<'PKGINSTALL'
#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
export TZ=UTC

# Update package list
apt-get update

# Stage 1: X11 and desktop base
echo "Installing X11 and VNC..."
apt-get install -y \
    xvfb x11-xserver-utils x11-utils \
    x11vnc \
    fluxbox \
    xdotool wmctrl scrot imagemagick \
    dbus-x11

# Stage 2: noVNC and websockify
echo "Installing noVNC..."
apt-get install -y \
    novnc websockify python3-websockify

# Stage 3: Desktop applications
echo "Installing desktop applications..."
apt-get install -y \
    firefox \
    gedit vim nano \
    xterm \
    python3 python3-pip

# Clean up
apt-get clean
rm -rf /var/lib/apt/lists/*
rm -rf /tmp/*

echo "Package installation complete"
PKGINSTALL

chmod +x "$MOUNT_POINT/tmp/install-desktop.sh"

# Run installation in chroot
log_info "Running package installation (this is the slowest step)..."
chroot "$MOUNT_POINT" /tmp/install-desktop.sh

log_success "Desktop packages installed"
echo ""

# Step 5: Configure VNC password
log_info "Step 5/8: Configuring VNC..."

mkdir -p "$MOUNT_POINT/root/.vnc"
# Create VNC password file (password: e2bdesktop)
chroot "$MOUNT_POINT" x11vnc -storepasswd e2bdesktop /root/.vnc/passwd

# Link noVNC files
if [ -d "$MOUNT_POINT/usr/share/novnc" ]; then
    ln -sf /usr/share/novnc/vnc.html "$MOUNT_POINT/usr/share/novnc/index.html" 2>/dev/null || true
fi

log_success "VNC configured"
echo ""

# Step 6: Create desktop startup script
log_info "Step 6/8: Creating desktop startup script..."

cat > "$MOUNT_POINT/usr/local/bin/start-desktop.sh" <<'DESKTOPSTART'
#!/bin/sh
# E2B Desktop Startup Script

# Redirect output to serial console
exec > /dev/ttyS0 2>&1

echo "=== E2B Desktop Starting ==="
date

# Set display
export DISPLAY=:99
export XAUTHORITY=/root/.Xauthority

# Clean up any existing X11 locks
rm -f /tmp/.X99-lock 2>/dev/null || true
rm -f /tmp/.X11-unix/X99 2>/dev/null || true

# Start Xvfb (virtual display)
echo "Starting Xvfb..."
Xvfb :99 -screen 0 1920x1080x24 -ac +extension GLX +render -noreset > /var/log/xvfb.log 2>&1 &
XVFB_PID=$!
echo "Xvfb started with PID: $XVFB_PID"

# Wait for X server to start
sleep 2

# Verify X server is running
if ! xdpyinfo -display :99 >/dev/null 2>&1; then
    echo "ERROR: X server failed to start"
    return 1
fi
echo "X server verified"

# Start window manager (fluxbox)
echo "Starting fluxbox window manager..."
fluxbox -display :99 > /var/log/fluxbox.log 2>&1 &
FLUXBOX_PID=$!
echo "Fluxbox started with PID: $FLUXBOX_PID"

sleep 1

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

# Wait for VNC to start
sleep 2

echo "VNC server started on port 5900"

# Start noVNC (websocket proxy)
echo "Starting noVNC..."
/usr/share/novnc/utils/novnc_proxy \
    --vnc localhost:5900 \
    --listen 6080 \
    > /var/log/novnc.log 2>&1 &
NOVNC_PID=$!
echo "noVNC started with PID: $NOVNC_PID on port 6080"

sleep 2

echo "=== E2B Desktop Ready ==="
echo "VNC: localhost:5900 (password: e2bdesktop)"
echo "noVNC: http://localhost:6080/vnc.html"
echo "Display: :99 (1920x1080x24)"
DESKTOPSTART

chmod +x "$MOUNT_POINT/usr/local/bin/start-desktop.sh"

log_success "Desktop startup script created"
echo ""

# Step 7: Integrate desktop into init script
log_info "Step 7/8: Updating init script to start desktop..."

# Check if init script exists
if [ ! -f "$MOUNT_POINT/sbin/init" ]; then
    log_error "Init script not found at /sbin/init"
    log_error "This rootfs may not be a valid E2B template"
    exit 1
fi

# Backup original init
cp "$MOUNT_POINT/sbin/init" "$MOUNT_POINT/sbin/init.backup"

# Modify init to start desktop before envd
# Insert desktop startup after network configuration, before envd
cat > "$MOUNT_POINT/sbin/init" <<'NEWINIT'
#!/bin/sh
# E2B Init Script with Desktop Support

# Redirect output to serial console
exec > /dev/ttyS0 2>&1

echo "=== E2B Guest Init Starting ==="

# Mount essential filesystems
mount -t proc proc /proc 2>/dev/null || true
mount -t sysfs sysfs /sys 2>/dev/null || true
mount -t devtmpfs devtmpfs /dev 2>/dev/null || true

# Configure network
ip link set lo up 2>/dev/null || true
ip link set eth0 up 2>/dev/null || true

# Wait for network
sleep 1

echo "=== Starting Desktop Environment ==="
# Start desktop in background
/usr/local/bin/start-desktop.sh &

# Wait for desktop to initialize
sleep 3

echo "=== Starting envd daemon ==="
# Start envd on port 49983
/usr/local/bin/envd &

echo "=== Init complete, desktop and envd started ==="

# Keep init running forever
while true; do
    sleep 100
done
NEWINIT

chmod +x "$MOUNT_POINT/sbin/init"

log_success "Init script updated"
echo ""

# Step 8: Create metadata.json
log_info "Step 8/8: Creating metadata.json..."

cat > "$STORAGE_BASE/$DESKTOP_BUILD_ID/metadata.json" <<METADATA
{
  "kernelVersion": "vmlinux-5.10.223",
  "firecrackerVersion": "v1.12.1_d990331",
  "buildID": "$DESKTOP_BUILD_ID",
  "templateID": "desktop-template-000-0000-0000-000000000001"
}
METADATA

log_success "Metadata created"
echo ""

# Cleanup: Unmount everything
log_info "Cleaning up..."

umount "$MOUNT_POINT/dev" 2>/dev/null || true
umount "$MOUNT_POINT/proc" 2>/dev/null || true
umount "$MOUNT_POINT/sys" 2>/dev/null || true
umount "$MOUNT_POINT"

log_success "Rootfs unmounted"

# Clear caches
log_info "Clearing template caches..."
rm -rf /home/primihub/e2b-storage/e2b-template-cache/$DESKTOP_BUILD_ID 2>/dev/null || true
rm -rf /home/primihub/e2b-storage/e2b-chunk-cache/$DESKTOP_BUILD_ID 2>/dev/null || true

log_success "Caches cleared"

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║     Desktop Template Installation Complete!                   ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Display summary
log_success "Desktop Build ID: $DESKTOP_BUILD_ID"
log_success "Template Path: $STORAGE_BASE/$DESKTOP_BUILD_ID/"
log_success "Rootfs: $(du -h "$DESKTOP_ROOTFS" | cut -f1)"
log_success "Metadata: $(cat "$STORAGE_BASE/$DESKTOP_BUILD_ID/metadata.json" | grep -c '\"' || echo "OK")"

echo ""
log_info "Installed desktop components:"
echo "  ✓ X11 (Xvfb virtual display)"
echo "  ✓ VNC server (x11vnc on port 5900)"
echo "  ✓ noVNC web client (port 6080)"
echo "  ✓ Fluxbox window manager"
echo "  ✓ Desktop applications (Firefox, gedit, vim)"
echo "  ✓ Control tools (xdotool, wmctrl, scrot)"
echo ""

log_info "Next steps:"
echo "  1. Update orchestrator sandbox.go line 416 with new build ID"
echo "  2. Recompile orchestrator"
echo "  3. Restart orchestrator service"
echo "  4. Test VM creation with desktop template"
echo ""

log_info "To test desktop VM:"
echo '  curl -X POST http://localhost:3000/sandboxes \'
echo '    -H "Content-Type: application/json" \'
echo '    -H "X-API-Key: e2b_53ae1fed82754c17ad8077fbc8bcdd90" \'
echo '    -d '"'"'{"templateID": "desktop-template-000-0000-0000-000000000001", "timeout": 300}'"'"
echo ""
