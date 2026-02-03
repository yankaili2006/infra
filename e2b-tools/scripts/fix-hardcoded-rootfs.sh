#!/bin/bash
# Fix the hardcoded rootfs path that orchestrator actually uses

set -e

# Load environment variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PCLOUD_HOME="$(cd "$SCRIPT_DIR/../../.." && pwd)"
if [ -f "$PCLOUD_HOME/config/env.sh" ]; then
    source "$PCLOUD_HOME/config/env.sh"
fi

PCLOUD_HOME="${PCLOUD_HOME:-/home/primihub/pcloud}"
E2B_STORAGE_PATH="${E2B_STORAGE_PATH:-$PCLOUD_HOME/../e2b-storage}"

BUILD_ID="fcb118f7-4d32-45d0-a935-13f3e630ecbb"
ROOTFS="$E2B_STORAGE_PATH/e2b-template-storage/${BUILD_ID}/rootfs.ext4"
ENVD_BIN="$PCLOUD_HOME/infra/packages/envd/bin/envd"

echo "=== Fixing rootfs at hardcoded path: $ROOTFS ==="
echo "Primihub@2022." | sudo -S mkdir -p /mnt/rootfs
echo "Primihub@2022." | sudo -S mount -o loop "$ROOTFS" /mnt/rootfs

echo "=== Copying envd binary ==="
echo "Primihub@2022." | sudo -S cp "$ENVD_BIN" /mnt/rootfs/usr/local/bin/envd
echo "Primihub@2022." | sudo -S chmod +x /mnt/rootfs/usr/local/bin/envd

echo "=== Creating proper init script ==="
echo "Primihub@2022." | sudo -S tee /mnt/rootfs/sbin/init > /dev/null <<'INITEOF'
#!/bin/sh
# E2B Init Script

# Redirect output to serial console
exec > /dev/ttyS0 2>&1

echo "=== E2B Guest Init Starting ==="

# Mount essential filesystems
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev

# Configure network
ip link set lo up
ip link set eth0 up

# Wait for network
sleep 1

echo "=== Starting envd daemon ==="
# Start envd on port 49983
/usr/local/bin/envd &

echo "=== Init complete, envd started ==="

# Keep init running forever
while true; do
    sleep 100
done
INITEOF

echo "Primihub@2022." | sudo -S chmod +x /mnt/rootfs/sbin/init

echo "=== Verifying files ==="
echo "Primihub@2022." | sudo -S ls -lh /mnt/rootfs/usr/local/bin/envd
echo "Primihub@2022." | sudo -S ls -lh /mnt/rootfs/sbin/init

echo "=== Unmounting ==="
echo "Primihub@2022." | sudo -S umount /mnt/rootfs

echo "=== Done! Rootfs at hardcoded path now fixed ==="
