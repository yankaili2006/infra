#!/bin/bash
set -e

# Code Interpreter Template Creator for E2B
# This script modifies an existing base template to add Python code execution capabilities

echo "=================================================="
echo "Code Interpreter Template Creator"
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
echo "  Base build ID:  $BASE_BUILD_ID"
echo "  New build ID:   $NEW_BUILD_ID"
echo "  Template ID:    $TEMPLATE_ID"
echo "  Script dir:     $SCRIPT_DIR"
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

# Create mount point
echo "📁 Creating mount point..."
mkdir -p "$MOUNT_POINT"

# Mount base rootfs
echo "🔧 Mounting base rootfs..."
mount -o loop "$BASE_DIR/rootfs.ext4" "$MOUNT_POINT"

# Ensure cleanup on exit
trap "echo '🔧 Unmounting...'; umount $MOUNT_POINT 2>/dev/null || true; rm -rf $MOUNT_POINT" EXIT

echo "✅ Rootfs mounted"
echo ""

# Install Python and dependencies
echo "📦 Installing Python and dependencies in chroot environment..."

# Copy DNS config (needed for apt)
cp /etc/resolv.conf "$MOUNT_POINT/etc/resolv.conf"

# Install packages
cat > "$MOUNT_POINT/tmp/install.sh" << 'INSTALL_SCRIPT'
#!/bin/bash
export DEBIAN_FRONTEND=noninteractive
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

echo "Updating package lists..."
apt-get update -qq > /dev/null 2>&1

echo "Installing Python and pip..."
apt-get install -y -qq python3 python3-pip python3-venv > /dev/null 2>&1

echo "Python installed:"
python3 --version

echo "pip installed:"
pip3 --version

echo "✅ Installation complete"
INSTALL_SCRIPT

chmod +x "$MOUNT_POINT/tmp/install.sh"

# Execute in chroot
echo "  Running installation in chroot..."
chroot "$MOUNT_POINT" /tmp/install.sh

if [ $? -eq 0 ]; then
    echo "✅ Python and pip installed"
else
    echo "⚠️  Installation had warnings, continuing..."
fi
echo ""

# Install Python API dependencies
echo "📦 Installing API dependencies..."
cp "$SCRIPT_DIR/api_requirements.txt" "$MOUNT_POINT/tmp/requirements.txt"

cat > "$MOUNT_POINT/tmp/install_deps.sh" << 'DEPS_SCRIPT'
#!/bin/bash
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

echo "Installing FastAPI and dependencies..."
pip3 install --no-cache-dir -r /tmp/requirements.txt > /tmp/pip_install.log 2>&1

if [ $? -eq 0 ]; then
    echo "✅ Dependencies installed"
    pip3 list | grep -E "(fastapi|uvicorn|pandas|numpy|matplotlib)"
else
    echo "❌ Dependency installation failed"
    cat /tmp/pip_install.log
    exit 1
fi
DEPS_SCRIPT

chmod +x "$MOUNT_POINT/tmp/install_deps.sh"
chroot "$MOUNT_POINT" /tmp/install_deps.sh

echo ""

# Copy API server code
echo "📄 Installing API server code..."
mkdir -p "$MOUNT_POINT/usr/local/bin"
cp "$SCRIPT_DIR/code_exec_api.py" "$MOUNT_POINT/usr/local/bin/code-exec-api"
chmod +x "$MOUNT_POINT/usr/local/bin/code-exec-api"
echo "✅ API server installed at /usr/local/bin/code-exec-api"
echo ""

# Modify init script to start API server
echo "⚙️  Configuring init script to start API server..."

# Backup original init
if [ -f "$MOUNT_POINT/sbin/init" ]; then
    cp "$MOUNT_POINT/sbin/init" "$MOUNT_POINT/sbin/init.backup"
fi

# Create new init that starts both envd and API server
cat > "$MOUNT_POINT/sbin/init" << 'INIT_SCRIPT'
#!/bin/sh
# E2B Init Script with Code Execution API

exec > /dev/ttyS0 2>&1

echo "=== E2B Guest Init Starting ==="

# Mount essential filesystems
mount -t proc proc /proc 2>/dev/null || true
mount -t sysfs sysfs /sys 2>/dev/null || true
mount -t devtmpfs devtmpfs /dev 2>/dev/null || true

# Configure network
ip link set lo up 2>/dev/null || true
ip link set eth0 up 2>/dev/null || true
sleep 1

echo "=== Starting envd daemon ==="
/usr/bin/envd &

echo "=== Starting code execution API server ==="
# Wait a bit for Python to be ready
sleep 2

# Start API server on port 49999
python3 /usr/local/bin/code-exec-api &
API_PID=$!

echo "=== Services started ==="
echo "  envd: running"
echo "  code-exec-api: PID $API_PID"

# Keep init running forever
while true; do
    sleep 100
done
INIT_SCRIPT

chmod +x "$MOUNT_POINT/sbin/init"
echo "✅ Init script configured"
echo ""

# Clean up
echo "🧹 Cleaning up temporary files..."
rm -f "$MOUNT_POINT/tmp/install.sh" \
      "$MOUNT_POINT/tmp/install_deps.sh" \
      "$MOUNT_POINT/tmp/requirements.txt" \
      "$MOUNT_POINT/tmp/pip_install.log"

# Unmount
echo "🔧 Unmounting rootfs..."
umount "$MOUNT_POINT"
rm -rf "$MOUNT_POINT"

trap - EXIT  # Disable trap since we manually unmounted

echo "✅ Unmounted"
echo ""

# Create new template directory
echo "📁 Creating new template directory..."
mkdir -p "$NEW_DIR"

# Copy rootfs to new location
echo "📋 Copying modified rootfs to new template..."
cp "$BASE_DIR/rootfs.ext4" "$NEW_DIR/rootfs.ext4"

# Create metadata
cat > "$NEW_DIR/metadata.json" << EOF
{
  "kernelVersion": "vmlinux-5.10.223",
  "firecrackerVersion": "v1.12.1_d990331",
  "buildID": "$NEW_BUILD_ID",
  "templateID": "$TEMPLATE_ID"
}
EOF

echo "✅ Template files created"
echo ""

# Create database entry script
cat > "/tmp/create_code_interpreter_template.sql" << EOF
-- Create template entry
INSERT INTO envs (id, created_at, updated_at)
VALUES ('$TEMPLATE_ID', NOW(), NOW())
ON CONFLICT (id) DO NOTHING;

-- Create build entry
INSERT INTO env_builds (id, env_id, kernel_version, firecracker_version, envd_version, status, created_at, updated_at)
VALUES ('$NEW_BUILD_ID', '$TEMPLATE_ID', 'vmlinux-5.10.223', 'v1.12.1_d990331', '0.2.0', 'uploaded', NOW(), NOW())
ON CONFLICT (id) DO NOTHING;
EOF

echo "📝 Database entry script created at /tmp/create_code_interpreter_template.sql"
echo ""

# Summary
echo "=================================================="
echo "✅ Code Interpreter Template Created Successfully"
echo "=================================================="
echo ""
echo "📊 Summary:"
echo "  Template ID:    $TEMPLATE_ID"
echo "  Build ID:       $NEW_BUILD_ID"
echo "  Rootfs:         $NEW_DIR/rootfs.ext4"
echo "  Metadata:       $NEW_DIR/metadata.json"
echo ""
echo "📝 Next Steps:"
echo ""
echo "1. Create database entries (if PostgreSQL is running):"
echo "   sudo -u postgres psql -d postgres -f /tmp/create_code_interpreter_template.sql"
echo ""
echo "2. Clear template cache:"
echo "   sudo rm -rf /home/primihub/e2b-storage/e2b-template-cache/*"
echo ""
echo "3. Test template creation:"
echo "   curl -X POST http://localhost:3000/sandboxes \\"
echo "     -H 'Content-Type: application/json' \\"
echo "     -H 'X-API-Key: e2b_53ae1fed82754c17ad8077fbc8bcdd90' \\"
echo "     -d '{\"templateID\": \"$TEMPLATE_ID\", \"timeout\": 300}'"
echo ""
echo "4. Test code execution:"
echo "   # Get sandbox ID from step 3, then:"
echo "   curl -X POST http://<sandbox-ip>:49999/execute \\"
echo "     -H 'Content-Type: application/json' \\"
echo "     -d '{\"code\": \"print(\\\"Hello from Python!\\\")\\nprint(2 + 2)\", \"language\": \"python\"}'"
echo ""
echo "=================================================="
