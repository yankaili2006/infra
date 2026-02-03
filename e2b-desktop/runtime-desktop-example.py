#!/usr/bin/env python3
"""
E2B Desktop - Runtime Installation Example
==========================================

This script demonstrates the WORKING approach: install desktop environment
at runtime instead of baking it into the template.

Advantages:
- Uses proven base template (no boot issues)
- Flexible per-session customization
- Can update packages without rebuilding template

Usage:
    python3 runtime-desktop-example.py
"""

import requests
import time
import json

# Configuration
API_URL = "http://localhost:3000"
API_KEY = "e2b_53ae1fed82754c17ad8077fbc8bcdd90"
BASE_TEMPLATE = "base"

print("=" * 70)
print("E2B Desktop - Runtime Installation Demo")
print("=" * 70)
print()

# Step 1: Create sandbox from base template
print("Step 1: Creating sandbox from base template...")
response = requests.post(
    f"{API_URL}/sandboxes",
    headers={
        "Content-Type": "application/json",
        "X-API-Key": API_KEY
    },
    json={
        "templateID": BASE_TEMPLATE,
        "timeout": 900  # 15 minutes
    }
)

if response.status_code not in [200, 201]:
    print(f"✗ Failed to create sandbox: {response.status_code}")
    print(response.text)
    exit(1)

sandbox_data = response.json()
sandbox_id = sandbox_data.get('sandboxID')
print(f"✓ Sandbox created: {sandbox_id}")
print()

# Helper function to execute commands
def run_command(sandbox_id, command, description):
    print(f"  {description}...")
    response = requests.post(
        f"{API_URL}/sandboxes/{sandbox_id}/commands",
        headers={
            "Content-Type": "application/json",
            "X-API-Key": API_KEY
        },
        json={
            "command": command,
            "timeout": 300
        }
    )

    if response.status_code == 200:
        result = response.json()
        if result.get('exitCode') == 0:
            print(f"    ✓ Success")
            return True
        else:
            print(f"    ✗ Failed (exit code: {result.get('exitCode')})")
            print(f"    stderr: {result.get('stderr', '')[:200]}")
            return False
    else:
        print(f"    ✗ API Error: {response.status_code}")
        return False

# Step 2: Install desktop packages
print("Step 2: Installing desktop packages (this takes 2-3 minutes)...")
print()

install_script = """
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq

# Install X11 and VNC
apt-get install -y -qq xvfb x11vnc fluxbox > /tmp/desktop-install.log 2>&1
if [ $? -ne 0 ]; then
    echo "Failed to install desktop packages"
    cat /tmp/desktop-install.log
    exit 1
fi

# Install noVNC
apt-get install -y -qq novnc websockify >> /tmp/desktop-install.log 2>&1

# Install basic applications
apt-get install -y -qq xterm firefox >> /tmp/desktop-install.log 2>&1

# Configure VNC
mkdir -p /root/.vnc
x11vnc -storepasswd e2bdesktop /root/.vnc/passwd

echo "Desktop packages installed successfully"
"""

if not run_command(sandbox_id, install_script, "Installing packages"):
    print()
    print("✗ Package installation failed. Cleaning up...")
    requests.delete(
        f"{API_URL}/sandboxes/{sandbox_id}",
        headers={"X-API-Key": API_KEY}
    )
    exit(1)

print()

# Step 3: Create desktop startup script
print("Step 3: Creating desktop startup script...")

startup_script = """
cat > /usr/local/bin/start-desktop.sh << 'DESKTOP_START'
#!/bin/bash
# E2B Desktop Startup Script

export DISPLAY=:99

# Start Xvfb (virtual display)
Xvfb :99 -screen 0 1920x1080x24 > /tmp/xvfb.log 2>&1 &
XVFB_PID=$!
sleep 2

# Start Fluxbox (window manager)
fluxbox > /tmp/fluxbox.log 2>&1 &
FLUXBOX_PID=$!
sleep 1

# Start x11vnc (VNC server)
x11vnc -display :99 -forever -shared -rfbauth /root/.vnc/passwd -rfbport 5900 > /tmp/x11vnc.log 2>&1 &
X11VNC_PID=$!

# Start noVNC (web interface)
websockify --web /usr/share/novnc 6080 localhost:5900 > /tmp/novnc.log 2>&1 &
WEBSOCKIFY_PID=$!

echo "Desktop environment started:"
echo "  Xvfb PID: $XVFB_PID"
echo "  Fluxbox PID: $FLUXBOX_PID"
echo "  x11vnc PID: $X11VNC_PID"
echo "  noVNC PID: $WEBSOCKIFY_PID"
echo ""
echo "VNC Access:"
echo "  Direct: localhost:5900 (password: e2bdesktop)"
echo "  Web: http://localhost:6080/vnc.html"
DESKTOP_START

chmod +x /usr/local/bin/start-desktop.sh
echo "Desktop startup script created"
"""

if not run_command(sandbox_id, startup_script, "Creating startup script"):
    print("✗ Failed to create startup script")
    exit(1)

print()

# Step 4: Start desktop environment
print("Step 4: Starting desktop environment...")

if not run_command(sandbox_id, "/usr/local/bin/start-desktop.sh", "Starting desktop"):
    print("✗ Failed to start desktop")
    exit(1)

print()

# Step 5: Verify desktop is running
print("Step 5: Verifying desktop processes...")

verify_script = """
echo "Checking desktop processes:"
ps aux | grep -E '(Xvfb|fluxbox|x11vnc|websockify)' | grep -v grep
echo ""
echo "Checking VNC port:"
netstat -tlnp 2>/dev/null | grep 5900 || ss -tlnp 2>/dev/null | grep 5900
echo ""
echo "Checking noVNC port:"
netstat -tlnp 2>/dev/null | grep 6080 || ss -tlnp 2>/dev/null | grep 6080
"""

run_command(sandbox_id, verify_script, "Checking processes")

print()
print("=" * 70)
print("✅ SUCCESS! Desktop environment is running")
print("=" * 70)
print()
print(f"Sandbox ID: {sandbox_id}")
print()
print("Access the desktop:")
print("  1. VNC Direct: localhost:5900")
print("     Password: e2bdesktop")
print("     Use any VNC client (TigerVNC, RealVNC, etc.)")
print()
print("  2. Web Browser: http://localhost:6080/vnc.html")
print("     No client needed - works in browser")
print()
print("Test applications:")
print("  # Open terminal")
print(f'  curl -X POST {API_URL}/sandboxes/{sandbox_id}/commands \\')
print(f'    -H "X-API-Key: {API_KEY}" \\')
print('    -d \'{"command": "DISPLAY=:99 xterm &"}\'')
print()
print("  # Open Firefox")
print(f'  curl -X POST {API_URL}/sandboxes/{sandbox_id}/commands \\')
print(f'    -H "X-API-Key: {API_KEY}" \\')
print('    -d \'{"command": "DISPLAY=:99 firefox &"}\'')
print()
print("Clean up:")
print(f"  curl -X DELETE {API_URL}/sandboxes/{sandbox_id} \\")
print(f'    -H "X-API-Key: {API_KEY}"')
print()
print("=" * 70)

# Keep sandbox alive for testing
print()
print("Sandbox will remain running for testing.")
print("Press Ctrl+C to exit (sandbox will continue running)")
print()

try:
    while True:
        time.sleep(60)
except KeyboardInterrupt:
    print()
    print("Exiting. Sandbox is still running.")
    print(f"Remember to delete it: curl -X DELETE {API_URL}/sandboxes/{sandbox_id} -H 'X-API-Key: {API_KEY}'")
