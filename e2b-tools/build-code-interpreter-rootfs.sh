#!/bin/bash
# Build Code Interpreter Rootfs for E2B Local Infrastructure
#
# This script creates a rootfs with Python, Jupyter, and envd for the code-interpreter template.
#
# Usage:
#   ./build-code-interpreter-rootfs.sh [build-id]
#
# Requirements:
#   - Docker installed
#   - sudo access
#   - envd binary available

set -e

# Load environment variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PCLOUD_HOME="$(cd "$SCRIPT_DIR/../.." && pwd)"
if [ -f "$PCLOUD_HOME/config/env.sh" ]; then
    source "$PCLOUD_HOME/config/env.sh"
fi

PCLOUD_HOME="${PCLOUD_HOME:-/home/primihub/pcloud}"
E2B_STORAGE_PATH="${E2B_STORAGE_PATH:-$PCLOUD_HOME/../e2b-storage}"

BUILD_ID="${1:-c0de1a73-7000-4000-a000-000000000001}"
STORAGE_PATH="$E2B_STORAGE_PATH/e2b-template-storage"
TARGET_DIR="$STORAGE_PATH/$BUILD_ID"
ROOTFS_SIZE="2G"  # Larger for Python/Jupyter
ENVD_BIN="$PCLOUD_HOME/infra/packages/envd/bin/envd"

echo "=========================================="
echo "Building Code Interpreter Rootfs"
echo "=========================================="
echo "Build ID: $BUILD_ID"
echo "Target: $TARGET_DIR"
echo ""

# Check prerequisites
if ! command -v docker &> /dev/null; then
    echo "❌ Docker not found"
    exit 1
fi

if [ ! -f "$ENVD_BIN" ]; then
    echo "❌ envd binary not found at $ENVD_BIN"
    echo "   Build it first: cd packages/envd && go build -o bin/envd ."
    exit 1
fi

# Create target directory
echo "1. Creating target directory..."
sudo mkdir -p "$TARGET_DIR"

# Create container and export rootfs
echo "2. Creating Docker container with Python/Jupyter..."
CONTAINER_ID=$(docker run -d ubuntu:22.04 sleep infinity)
echo "   Container: $CONTAINER_ID"

echo "3. Installing packages in container..."
docker exec $CONTAINER_ID bash -c '
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    python3 python3-pip python3-venv \
    curl wget ca-certificates \
    iproute2 iputils-ping \
    procps htop \
    git \
    > /dev/null

# Install Jupyter and common packages
pip3 install -q \
    jupyter \
    ipykernel \
    numpy \
    pandas \
    matplotlib \
    requests \
    > /dev/null 2>&1

# Create jupyter config
mkdir -p /root/.jupyter
cat > /root/.jupyter/jupyter_server_config.py << "EOF"
c.ServerApp.ip = "0.0.0.0"
c.ServerApp.port = 49999
c.ServerApp.allow_root = True
c.ServerApp.token = ""
c.ServerApp.password = ""
c.ServerApp.open_browser = False
c.ServerApp.allow_origin = "*"
EOF

echo "Packages installed successfully"
'

echo "4. Creating rootfs image ($ROOTFS_SIZE)..."
sudo dd if=/dev/zero of="$TARGET_DIR/rootfs.ext4" bs=1 count=0 seek=$ROOTFS_SIZE 2>/dev/null
sudo mkfs.ext4 -q "$TARGET_DIR/rootfs.ext4"

echo "5. Exporting container filesystem..."
MOUNT_DIR="/tmp/code-interpreter-rootfs-$$"
sudo mkdir -p "$MOUNT_DIR"
sudo mount -o loop "$TARGET_DIR/rootfs.ext4" "$MOUNT_DIR"

docker export $CONTAINER_ID | sudo tar -xf - -C "$MOUNT_DIR" 2>/dev/null

echo "6. Installing envd..."
sudo cp "$ENVD_BIN" "$MOUNT_DIR/usr/local/bin/envd"
sudo chmod +x "$MOUNT_DIR/usr/local/bin/envd"

echo "7. Creating init script..."
sudo tee "$MOUNT_DIR/sbin/init" > /dev/null << 'INITEOF'
#!/bin/sh
# E2B Code Interpreter Init Script

exec > /dev/ttyS0 2>&1

echo "=== E2B Code Interpreter Init Starting ==="

# Mount filesystems
mount -t proc proc /proc 2>/dev/null || true
mount -t sysfs sysfs /sys 2>/dev/null || true
mount -t devtmpfs devtmpfs /dev 2>/dev/null || true
mount -t devpts devpts /dev/pts 2>/dev/null || true
mount -t tmpfs tmpfs /tmp 2>/dev/null || true
mount -t tmpfs tmpfs /run 2>/dev/null || true

echo "✓ Filesystems mounted"

# Configure network
ip link set lo up 2>/dev/null || true
ip link set eth0 up 2>/dev/null || true

# Wait for network interface
sleep 1

# Get IP from boot args or use default
ETH0_IP="169.254.0.21"
ip addr add ${ETH0_IP}/30 dev eth0 2>/dev/null || true

echo "✓ Network configured"
ip addr show eth0 | grep inet

echo "=== Starting envd ==="
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
/usr/local/bin/envd &
ENVD_PID=$!

echo "=== Starting Jupyter (background) ==="
cd /root
python3 -m jupyter server --config=/root/.jupyter/jupyter_server_config.py > /tmp/jupyter.log 2>&1 &
JUPYTER_PID=$!

echo "✓ Services started"
echo "  envd PID: $ENVD_PID"
echo "  Jupyter PID: $JUPYTER_PID"
echo "=== Init complete ==="

# Keep init running
while true; do
    sleep 100
done
INITEOF

sudo chmod +x "$MOUNT_DIR/sbin/init"

echo "8. Verifying installation..."
sudo ls -la "$MOUNT_DIR/usr/bin/python3" 2>/dev/null && echo "   ✓ python3 installed"
sudo ls -la "$MOUNT_DIR/usr/local/bin/envd" 2>/dev/null && echo "   ✓ envd installed"
sudo ls -la "$MOUNT_DIR/sbin/init" 2>/dev/null && echo "   ✓ init script created"

# Cleanup
echo "9. Cleaning up..."
sudo umount "$MOUNT_DIR"
sudo rmdir "$MOUNT_DIR"
docker stop $CONTAINER_ID > /dev/null
docker rm $CONTAINER_ID > /dev/null

echo "10. Creating metadata..."
sudo tee "$TARGET_DIR/metadata.json" > /dev/null << EOF
{
  "kernelVersion": "vmlinux-5.10.223",
  "firecrackerVersion": "v1.12.1_d990331",
  "buildID": "$BUILD_ID",
  "templateID": "code-interpreter-v1",
  "envdVersion": "0.2.0"
}
EOF

echo ""
echo "=========================================="
echo "✅ Code Interpreter rootfs created"
echo "=========================================="
echo "Location: $TARGET_DIR"
echo ""
ls -lh "$TARGET_DIR/"
echo ""
echo "Next steps:"
echo "1. Update database: UPDATE env_builds SET status = 'uploaded' WHERE id = '$BUILD_ID'::uuid;"
echo "2. Clear cache: sudo rm -rf /home/primihub/e2b-storage/e2b-template-cache/$BUILD_ID"
echo "3. Test: curl -X POST http://localhost:3000/sandboxes -H 'X-API-Key: ...' -d '{\"templateID\": \"code-interpreter-v1\"}'"
