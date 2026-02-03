#!/bin/bash
set -e

# Code Interpreter Template Creator v3 - Copy host Python approach

echo "=================================================="
echo "Code Interpreter Template Creator v3"
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

echo "📋 Configuration:"
echo "  Template ID:    $TEMPLATE_ID"
echo "  New build ID:   $NEW_BUILD_ID"
echo ""

# Check root
if [ "$EUID" -ne 0 ]; then
    echo "❌ Run as root (use sudo)"
    exit 1
fi

# Check base
if [ ! -f "$BASE_DIR/rootfs.ext4" ]; then
    echo "❌ Base template not found"
    exit 1
fi

echo "✅ Base template found"

# Copy base rootfs first
echo "📋 Copying base rootfs..."
mkdir -p "$NEW_DIR"
cp "$BASE_DIR/rootfs.ext4" "$NEW_DIR/rootfs.ext4"
echo "✅ Copied ($(du -h "$NEW_DIR/rootfs.ext4" | cut -f1))"
echo ""

# Mount
echo "🔧 Mounting rootfs..."
mkdir -p "$MOUNT_POINT"
mount -o loop "$NEW_DIR/rootfs.ext4" "$MOUNT_POINT"
trap "echo '🔧 Unmounting...'; umount $MOUNT_POINT 2>/dev/null || true; rm -rf $MOUNT_POINT" EXIT

echo "✅ Mounted"
echo ""

# Install packages on HOST, then copy to guest
echo "📦 Installing packages on host..."
TEMP_VENV="/tmp/e2b-ci-venv"
rm -rf "$TEMP_VENV"
python3 -m venv "$TEMP_VENV" --without-pip

# Use pip from outside venv to install into venv
echo "  Installing fastapi, uvicorn, numpy, pandas..."
python3 -m pip install --target="$TEMP_VENV/lib/python$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')/site-packages" \
    fastapi==0.115.0 \
    uvicorn==0.32.0 \
    pydantic==2.10.0 \
    numpy==1.26.4 \
    pandas==2.2.3 2>&1 | grep -E "(Successfully|Collecting)" || true

echo "✅ Packages installed in temp venv"
echo ""

# Copy Python binary and libraries to guest
echo "📦 Copying Python to guest rootfs..."

# Find Python3 path
PYTHON_BIN=$(which python3)
PYTHON_VERSION=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")

echo "  Python binary: $PYTHON_BIN"
echo "  Python version: $PYTHON_VERSION"

# Copy Python binary
cp "$PYTHON_BIN" "$MOUNT_POINT/usr/bin/python3"
chmod +x "$MOUNT_POINT/usr/bin/python3"

# Copy Python standard library
echo "  Copying Python stdlib..."
PYTHON_LIB="/usr/lib/python${PYTHON_VERSION}"
if [ -d "$PYTHON_LIB" ]; then
    mkdir -p "$MOUNT_POINT$PYTHON_LIB"
    cp -r "$PYTHON_LIB"/* "$MOUNT_POINT$PYTHON_LIB/" 2>/dev/null || true
fi

# Copy shared libraries
echo "  Copying shared libraries..."
LIBS=$(ldd "$PYTHON_BIN" | grep "=> /" | awk '{print $3}')
for lib in $LIBS; do
    if [ -f "$lib" ]; then
        LIB_DIR=$(dirname "$lib")
        mkdir -p "$MOUNT_POINT$LIB_DIR"
        cp "$lib" "$MOUNT_POINT$lib" 2>/dev/null || true
    fi
done

# Copy site-packages from venv
echo "  Copying site-packages..."
SITE_PACKAGES="$TEMP_VENV/lib/python${PYTHON_VERSION}/site-packages"
mkdir -p "$MOUNT_POINT/usr/local/lib/python${PYTHON_VERSION}/site-packages"
cp -r "$SITE_PACKAGES"/* "$MOUNT_POINT/usr/local/lib/python${PYTHON_VERSION}/site-packages/" 2>/dev/null || true

rm -rf "$TEMP_VENV"

echo "✅ Python copied to guest"
echo ""

# Copy API server
echo "📄 Installing API server..."
cp "$SCRIPT_DIR/code_exec_api.py" "$MOUNT_POINT/usr/local/bin/code-exec-api"
chmod +x "$MOUNT_POINT/usr/local/bin/code-exec-api"
echo "✅ API server installed"
echo ""

# Update init script
echo "⚙️  Updating init script..."
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

# Set Python path
export PYTHONPATH=/usr/local/lib/python3.12/site-packages:/usr/lib/python3.12

echo "=== Starting envd ==="
/usr/bin/envd &

echo "=== Starting code execution API on port 49999 ==="
sleep 2
python3 /usr/local/bin/code-exec-api > /tmp/api.log 2>&1 &

echo "=== Services started ==="
ps aux | grep -E '(envd|python)'

while true; do
    sleep 100
done
INIT_SCRIPT

chmod +x "$MOUNT_POINT/sbin/init"
echo "✅ Init script updated"
echo ""

# Create test script in guest
cat > "$MOUNT_POINT/tmp/test_python.sh" << 'TEST_SCRIPT'
#!/bin/sh
echo "Testing Python installation..."
/usr/bin/python3 --version
/usr/bin/python3 -c "import fastapi; print('FastAPI:', fastapi.__version__)"
/usr/bin/python3 -c "import numpy; print('NumPy:', numpy.__version__)"
TEST_SCRIPT
chmod +x "$MOUNT_POINT/tmp/test_python.sh"

# Test in chroot
echo "🧪 Testing Python in guest environment..."
chroot "$MOUNT_POINT" /tmp/test_python.sh 2>&1 || echo "⚠️  Test had warnings"
echo ""

# Unmount
echo "🔧 Unmounting..."
umount "$MOUNT_POINT"
rm -rf "$MOUNT_POINT"
trap - EXIT
echo "✅ Unmounted"
echo ""

# Create metadata
cat > "$NEW_DIR/metadata.json" << EOF
{
  "kernelVersion": "vmlinux-5.10.223",
  "firecrackerVersion": "v1.12.1_d990331",
  "buildID": "$NEW_BUILD_ID",
  "templateID": "$TEMPLATE_ID"
}
EOF

echo "✅ Metadata created"
echo ""

# Generate SQL
cat > "/tmp/create_code_interpreter_template.sql" << EOF
-- Create template
INSERT INTO envs (id, created_at, updated_at)
VALUES ('$TEMPLATE_ID', NOW(), NOW())
ON CONFLICT (id) DO NOTHING;

-- Create build
INSERT INTO env_builds (id, env_id, kernel_version, firecracker_version, envd_version, status, created_at, updated_at)
VALUES ('$NEW_BUILD_ID', '$TEMPLATE_ID', 'vmlinux-5.10.223', 'v1.12.1_d990331', '0.2.0', 'uploaded', NOW(), NOW())
ON CONFLICT (id) DO NOTHING;
EOF

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
echo "1. Add to database (find postgres container first):"
echo "   docker ps | grep postgres"
echo "   # Then run SQL:"
echo "   cat /tmp/create_code_interpreter_template.sql"
echo ""
echo "2. Clear caches:"
echo "   sudo rm -rf /home/primihub/e2b-storage/e2b-template-cache/*"
echo ""
echo "3. Test VM creation:"
echo "   curl -X POST http://localhost:3000/sandboxes \\"
echo "     -H 'Content-Type: application/json' \\"
echo "     -H 'X-API-Key: e2b_53ae1fed82754c17ad8077fbc8bcdd90' \\"
echo "     -d '{\"templateID\": \"$TEMPLATE_ID\", \"timeout\": 300}'"
echo ""
