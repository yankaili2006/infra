#!/bin/bash
set -e

# Code Interpreter Template Creator for E2B (Version 2 - With offline package installation)

echo "=================================================="
echo "Code Interpreter Template Creator v2"
echo "=================================================="
echo ""

# Configuration
BASE_BUILD_ID="9ac9c8b9-9b8b-476c-9238-8266af308c32"
NEW_BUILD_ID="$(uuidgen | tr '[:upper:]' '[:lower:]')"
TEMPLATE_ID="code-interpreter-v1"
TEMPLATE_STORAGE="/home/primihub/e2b-storage/e2b-template-storage"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

BASE_DIR="$TEMPLATE_STORAGE/$BASE_BUILD_ID"
NEW_DIR="$TEMPLATE_STORAGE/$NEW_BUILD_ID"
MOUNT_POINT="/mnt/e2b-code-interpreter"
PACKAGES_DIR="$SCRIPT_DIR/packages"

echo "📋 Configuration:"
echo "  Base build ID:  $BASE_BUILD_ID"
echo "  New build ID:   $NEW_BUILD_ID"
echo "  Template ID:    $TEMPLATE_ID"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "❌ This script must be run as root (use sudo)"
    exit 1
fi

# Check base template exists
if [ ! -f "$BASE_DIR/rootfs.ext4" ]; then
    echo "❌ Base template not found at $BASE_DIR/rootfs.ext4"
    exit 1
fi

echo "✅ Base template found"
echo ""

# Download Python packages (on host)
echo "📦 Downloading Python packages on host..."
mkdir -p "$PACKAGES_DIR"
cd "$PACKAGES_DIR"

if [ ! -f "python3-minimal_*.deb" ]; then
    echo "  Downloading Python packages..."
    apt-get download python3-minimal python3 python3-pip python3-distutils python3-lib2to3 \
        libpython3-stdlib libpython3.12-minimal libpython3.12-stdlib 2>/dev/null || true
fi

PACKAGE_COUNT=$(ls *.deb 2>/dev/null | wc -l)
echo "✅ Downloaded/found $PACKAGE_COUNT packages"
echo ""

# Create mount point
echo "📁 Creating mount point..."
mkdir -p "$MOUNT_POINT"

# Mount base rootfs
echo "🔧 Mounting base rootfs..."
mount -o loop "$BASE_DIR/rootfs.ext4" "$MOUNT_POINT"

# Ensure cleanup on exit
trap "echo '🔧 Unmounting...'; umount $MOUNT_POINT 2>/dev/null || true" EXIT

echo "✅ Rootfs mounted"
echo ""

# Copy packages into rootfs
echo "📦 Copying packages into rootfs..."
mkdir -p "$MOUNT_POINT/tmp/python-packages"
cp "$PACKAGES_DIR"/*.deb "$MOUNT_POINT/tmp/python-packages/" 2>/dev/null || true
echo "✅ Packages copied"
echo ""

# Install packages in chroot
echo "📦 Installing Python via dpkg in chroot..."

cat > "$MOUNT_POINT/tmp/install_python.sh" << 'INSTALL_SCRIPT'
#!/bin/bash
export DEBIAN_FRONTEND=noninteractive
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

cd /tmp/python-packages

echo "Installing Python packages..."
dpkg -i *.deb 2>/dev/null || true

# Fix any dependency issues
echo "Fixing dependencies if any..."
apt-get install -f -y 2>/dev/null || true

# Verify Python is installed
if command -v python3 &> /dev/null; then
    echo "✅ Python installed successfully"
    python3 --version
else
    echo "⚠️  Python installation verification failed"
fi

# Clean up
rm -rf /tmp/python-packages
INSTALL_SCRIPT

chmod +x "$MOUNT_POINT/tmp/install_python.sh"
chroot "$MOUNT_POINT" /tmp/install_python.sh

echo ""

# Install pip packages using host pip and copy to rootfs
echo "📦 Installing Python packages on host then copying..."

# Create a temporary venv on host
TEMP_VENV="/tmp/e2b-code-venv"
rm -rf "$TEMP_VENV"
python3 -m venv "$TEMP_VENV"

# Install packages in venv
echo "  Installing FastAPI and dependencies..."
"$TEMP_VENV/bin/pip" install --quiet \
    fastapi==0.115.0 \
    uvicorn[standard]==0.32.0 \
    pydantic==2.10.0 \
    numpy==1.26.4 \
    pandas==2.2.3 \
    matplotlib==3.9.0

# Copy site-packages to rootfs
echo "  Copying packages to rootfs..."
PYTHON_VERSION=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
mkdir -p "$MOUNT_POINT/usr/local/lib/python${PYTHON_VERSION}/site-packages"

cp -r "$TEMP_VENV/lib/python${PYTHON_VERSION}/site-packages"/* \
      "$MOUNT_POINT/usr/local/lib/python${PYTHON_VERSION}/site-packages/"

# Clean up venv
rm -rf "$TEMP_VENV"

echo "✅ Python packages installed"
echo ""

# Copy API server code
echo "📄 Installing API server code..."
mkdir -p "$MOUNT_POINT/usr/local/bin"
cp "$SCRIPT_DIR/code_exec_api.py" "$MOUNT_POINT/usr/local/bin/code-exec-api"
chmod +x "$MOUNT_POINT/usr/local/bin/code-exec-api"
echo "✅ API server installed"
echo ""

# Modify init script
echo "⚙️  Configuring init script..."

if [ -f "$MOUNT_POINT/sbin/init" ]; then
    cp "$MOUNT_POINT/sbin/init" "$MOUNT_POINT/sbin/init.backup"
fi

cat > "$MOUNT_POINT/sbin/init" << 'INIT_SCRIPT'
#!/bin/sh
exec > /dev/ttyS0 2>&1

echo "=== E2B Code Interpreter Init ==="

# Mount filesystems
mount -t proc proc /proc 2>/dev/null || true
mount -t sysfs sysfs /sys 2>/dev/null || true
mount -t devtmpfs devtmpfs /dev 2>/dev/null || true

# Network
ip link set lo up 2>/dev/null || true
ip link set eth0 up 2>/dev/null || true
sleep 1

echo "=== Starting envd ==="
/usr/bin/envd &

echo "=== Starting code execution API ==="
sleep 2
python3 /usr/local/bin/code-exec-api &

echo "=== Init complete ==="

while true; do
    sleep 100
done
INIT_SCRIPT

chmod +x "$MOUNT_POINT/sbin/init"
echo "✅ Init configured"
echo ""

# Unmount
echo "🔧 Unmounting..."
umount "$MOUNT_POINT"
trap - EXIT

echo "✅ Unmounted"
echo ""

# Copy to new template directory
echo "📋 Creating new template..."
mkdir -p "$NEW_DIR"
cp "$BASE_DIR/rootfs.ext4" "$NEW_DIR/rootfs.ext4"

cat > "$NEW_DIR/metadata.json" << EOF
{
  "kernelVersion": "vmlinux-5.10.223",
  "firecrackerVersion": "v1.12.1_d990331",
  "buildID": "$NEW_BUILD_ID",
  "templateID": "$TEMPLATE_ID"
}
EOF

echo "✅ Template created"
echo ""

# Generate SQL
cat > "/tmp/create_code_interpreter_template.sql" << EOF
INSERT INTO envs (id, created_at, updated_at)
VALUES ('$TEMPLATE_ID', NOW(), NOW())
ON CONFLICT (id) DO NOTHING;

INSERT INTO env_builds (id, env_id, kernel_version, firecracker_version, envd_version, status, created_at, updated_at)
VALUES ('$NEW_BUILD_ID', '$TEMPLATE_ID', 'vmlinux-5.10.223', 'v1.12.1_d990331', '0.2.0', 'uploaded', NOW(), NOW())
ON CONFLICT (id) DO NOTHING;
EOF

echo "=================================================="
echo "✅ SUCCESS - Code Interpreter Template Created"
echo "=================================================="
echo ""
echo "Template ID: $TEMPLATE_ID"
echo "Build ID:    $NEW_BUILD_ID"
echo ""
echo "Next steps:"
echo "1. Find PostgreSQL container and run SQL:"
echo "   docker ps | grep postgres"
echo "   docker exec -i <container-name> psql -U postgres -d postgres < /tmp/create_code_interpreter_template.sql"
echo ""
echo "2. Clear caches:"
echo "   sudo rm -rf /home/primihub/e2b-storage/e2b-template-cache/*"
echo ""
echo "3. Test VM creation:"
echo "   curl -X POST http://localhost:3000/sandboxes -H 'Content-Type: application/json' -H 'X-API-Key: e2b_53ae1fed82754c17ad8077fbc8bcdd90' -d '{\"templateID\": \"$TEMPLATE_ID\", \"timeout\": 300}'"
echo ""
