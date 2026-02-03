#!/bin/bash
##############################################################################
# E2B Ubuntu Desktop Startup Script
# Purpose: Start GNOME desktop, VNC, and noVNC services
##############################################################################

set -e

echo "=== E2B Ubuntu Desktop Starting ==="

# Set display
export DISPLAY=:0

# Start GDM (GNOME Display Manager)
echo "Starting GDM..."
systemctl start gdm3
sleep 10

# Wait for X server
echo "Waiting for X server..."
timeout=30
while [ $timeout -gt 0 ]; do
    if xdpyinfo -display :0 >/dev/null 2>&1; then
        echo "X server is ready"
        break
    fi
    sleep 1
    timeout=$((timeout - 1))
done

if [ $timeout -eq 0 ]; then
    echo "ERROR: X server failed to start"
    exit 1
fi

# Start VNC server
echo "Starting VNC server on port 5900..."
x11vnc -display :0 -forever -shared -rfbport 5900 -rfbauth /root/.vnc/passwd -bg -o /var/log/x11vnc.log

# Start noVNC web client
echo "Starting noVNC on port 6080..."
/usr/share/novnc/utils/novnc_proxy --vnc localhost:5900 --listen 6080 > /var/log/novnc.log 2>&1 &

echo "=== Desktop Ready ==="
echo "VNC: localhost:5900 (password: e2bdesktop)"
echo "noVNC: http://localhost:6080/vnc.html"

# Keep script running
tail -f /var/log/x11vnc.log
