#!/bin/bash
# Code Interpreter Template Creator v5
# Fixed Python installation logic with proper chroot environment setup

set -e

# Load environment variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PCLOUD_HOME="$(cd "$SCRIPT_DIR/../../.." && pwd)"
if [ -f "$PCLOUD_HOME/config/env.sh" ]; then
    source "$PCLOUD_HOME/config/env.sh"
fi

PCLOUD_HOME="${PCLOUD_HOME:-/home/primihub/pcloud}"
E2B_STORAGE_PATH="${E2B_STORAGE_PATH:-$PCLOUD_HOME/../e2b-storage}"
TEMPLATE_ID="code-interpreter-v1"
BASE_BUILD_ID="9ac9c8b9-9b8b-476c-9238-8266af308c32"
NEW_BUILD_ID="15dc8110-c9da-49a7-96f9-d221e06425c8"
STORAGE_BASE="$E2B_STORAGE_PATH/e2b-template-storage"
BASE_DIR="$STORAGE_BASE/$BASE_BUILD_ID"
NEW_DIR="$STORAGE_BASE/$NEW_BUILD_ID"
MOUNT_POINT="/mnt/e2b-rootfs-ci"

echo "=================================================="
echo "Code Interpreter Template Creator v5"
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

# Setup DNS for chroot
sudo cp /etc/resolv.conf "$MOUNT_POINT/etc/resolv.conf"

echo "✅ Chroot environment ready"
echo ""

# Install Python and packages via chroot
echo "📦 Installing Python and packages in guest environment..."

# Create install script for chroot
cat > /tmp/install_python.sh <<'INSTALL_EOF'
#!/bin/bash
# Don't exit on error - we want to see what fails
set +e

export DEBIAN_FRONTEND=noninteractive
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

echo "→ Updating package lists..."
apt-get update -qq 2>&1 | tail -3
if [ $? -ne 0 ]; then
    echo "❌ APT update failed"
    exit 1
fi

echo "→ Upgrading existing packages to fix dependencies..."
apt-get upgrade -y 2>&1 | tail -10
echo "✓ Packages upgraded"

echo "→ Installing Python and pip (without build tools to avoid dependency issues)..."
apt-get install -y --no-install-recommends \
    python3 \
    python3-pip

APT_RESULT=$?
if [ $APT_RESULT -ne 0 ]; then
    echo "❌ Package installation failed with code $APT_RESULT"
    exit 1
fi
echo "✓ Python and pip installed"

echo "→ Verifying Python installation..."
python3 --version
if [ $? -ne 0 ]; then
    echo "❌ Python not found after installation"
    exit 1
fi

pip3 --version
if [ $? -ne 0 ]; then
    echo "⚠️  pip3 not found, trying alternative..."
    python3 -m pip --version
fi

echo "→ Upgrading pip..."
# Use Tsinghua mirror for pip (faster in China)
python3 -m pip install --upgrade pip -i https://pypi.tuna.tsinghua.edu.cn/simple 2>&1 | tail -3

echo "→ Installing Python packages (using Tsinghua mirror, prefer binary wheels)..."
python3 -m pip install --no-cache-dir \
    -i https://pypi.tuna.tsinghua.edu.cn/simple \
    --only-binary :all: \
    fastapi==0.115.0 \
    uvicorn==0.32.0 \
    pydantic==2.10.0 \
    2>&1 | grep -E "(Successfully|Collecting|Installing)" | tail -10

# Install numpy and pandas separately (they may need compilation)
echo "→ Installing numpy and pandas (may take longer)..."
python3 -m pip install --no-cache-dir \
    -i https://pypi.tuna.tsinghua.edu.cn/simple \
    numpy==1.26.4 \
    pandas==2.2.3 \
    2>&1 | grep -E "(Successfully|Collecting|Installing)" | tail -10

echo "→ Verifying package installation..."
python3 -c "import fastapi; print(f'FastAPI: {fastapi.__version__}')"
python3 -c "import numpy; print(f'NumPy: {numpy.__version__}')"
python3 -c "import pandas; print(f'Pandas: {pandas.__version__}')"

echo "✅ Python and packages installed successfully"
INSTALL_EOF

chmod +x /tmp/install_python.sh
sudo cp /tmp/install_python.sh "$MOUNT_POINT/tmp/install_python.sh"

# Run install script in chroot
echo "  Running package installation (this may take 3-5 minutes)..."
echo ""
sudo chroot "$MOUNT_POINT" /bin/bash /tmp/install_python.sh

echo ""
echo "✅ Python and packages installed"
echo ""

# Install API server
echo "📄 Installing API server..."
if [ -f "$SCRIPT_DIR/code_exec_api.py" ]; then
    sudo cp "$SCRIPT_DIR/code_exec_api.py" "$MOUNT_POINT/usr/local/bin/code-exec-api"
    sudo chmod +x "$MOUNT_POINT/usr/local/bin/code-exec-api"
    echo "✅ API server installed"
else
    echo "⚠️  code_exec_api.py not found, skipping API server installation"
fi
echo ""

# Update init script to start API
echo "⚙️  Updating init script..."
sudo bash -c "cat > '$MOUNT_POINT/sbin/init' <<'INIT_EOF'
#!/bin/sh
# E2B Code Interpreter Init

# Redirect output to serial console
exec > /dev/ttyS0 2>&1

echo \"=== E2B Code Interpreter Init Starting ===\"

# Mount essential filesystems
mount -t proc proc /proc 2>/dev/null || true
mount -t sysfs sys /sys 2>/dev/null || true
mount -t devtmpfs dev /dev 2>/dev/null || true

echo \"✓ Filesystems mounted\"

# Setup network
ip link set lo up 2>/dev/null || true
ip link set eth0 up 2>/dev/null || true

echo \"✓ Network configured\"

# Start envd daemon (if exists)
if [ -f /usr/bin/envd ]; then
    echo \"=== Starting envd ===\"
    /usr/bin/envd &
fi

# Start code execution API
if [ -f /usr/local/bin/code-exec-api ]; then
    echo \"=== Starting code execution API ===\"
    cd /tmp
    python3 /usr/local/bin/code-exec-api &
fi

echo \"=== Init complete ===\"

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
sudo chroot "$MOUNT_POINT" python3 --version
sudo chroot "$MOUNT_POINT" python3 -c "import numpy; print(f'NumPy test: {numpy.array([1,2,3]).mean()}')"
echo "✅ Python test passed"
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
  "templateID": "$TEMPLATE_ID",
  "envdVersion": "0.2.0"
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
echo "1. Clear caches:"
echo "   sudo rm -rf $E2B_STORAGE_PATH/e2b-template-cache/*"
echo "   sudo rm -rf $E2B_STORAGE_PATH/e2b-chunk-cache/*"
echo ""
echo "2. Test VM creation:"
echo "   curl -X POST http://localhost:3000/sandboxes \\"
echo "     -H 'Content-Type: application/json' \\"
echo "     -H 'X-API-Key: e2b_53ae1fed82754c17ad8077fbc8bcdd90' \\"
echo "     -d '{\"templateID\": \"code-interpreter-v1\", \"timeout\": 300}'"
echo ""
echo "3. Test with skill:"
echo "   cd $PCLOUD_HOME"
echo "   python3 ./platform/skills/e2b-sandbox/skill.py run-python \"import numpy; print(numpy.__version__)\""
echo ""
