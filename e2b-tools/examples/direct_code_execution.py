#!/usr/bin/env python3
"""
Direct Code Execution via E2B Local Infrastructure
Bypasses SDK cloud URL issues by using direct HTTP API calls
"""

import os
import sys
import json
import time
import requests
import subprocess

# Configuration
API_URL = "http://localhost:3000"
API_KEY = "e2b_53ae1fed82754c17ad8077fbc8bcdd90"
HEADERS = {
    "X-API-Key": API_KEY,
    "Content-Type": "application/json"
}

def create_sandbox(template_id="base", timeout=300):
    """Create a new sandbox"""
    print(f"\n{'='*60}")
    print("Creating Sandbox...")
    print(f"{'='*60}")

    payload = {
        "templateID": template_id,
        "timeout": timeout
    }

    resp = requests.post(
        f"{API_URL}/sandboxes",
        headers=HEADERS,
        json=payload,
        timeout=30
    )

    if resp.status_code in [200, 201]:
        data = resp.json()
        print(f"✅ Sandbox created!")
        print(f"   ID: {data.get('sandboxID')}")
        print(f"   Template: {data.get('templateID')}")
        print(f"   Client ID: {data.get('clientID')}")
        return data
    else:
        print(f"❌ Failed: {resp.status_code} - {resp.text}")
        return None

def list_sandboxes():
    """List all running sandboxes"""
    resp = requests.get(f"{API_URL}/sandboxes", headers=HEADERS)
    if resp.status_code == 200:
        return resp.json()
    return []

def get_sandbox_info(sandbox_id):
    """Get sandbox details"""
    resp = requests.get(f"{API_URL}/sandboxes/{sandbox_id}", headers=HEADERS)
    if resp.status_code == 200:
        return resp.json()
    return None

def delete_sandbox(sandbox_id):
    """Delete a sandbox"""
    resp = requests.delete(f"{API_URL}/sandboxes/{sandbox_id}", headers=HEADERS)
    return resp.status_code in [200, 204]

def find_sandbox_host_ip(sandbox_id):
    """
    Try to find the host IP for a sandbox
    This is a workaround since the API doesn't expose the internal IP
    """
    # Get list of listening ports
    try:
        result = subprocess.run(
            ["netstat", "-tlnp"],
            capture_output=True,
            text=True
        )

        # Parse output to find 10.11.0.X:49983 ports
        listening_ips = []
        for line in result.stdout.split('\n'):
            if '10.11.0.' in line and ':49983' in line:
                parts = line.split()
                if len(parts) >= 4:
                    addr = parts[3].split(':')[0]
                    listening_ips.append(addr)

        return listening_ips
    except Exception as e:
        print(f"Warning: Could not get listening ports: {e}")
        return []

def test_envd_connection(host_ip, port=49983):
    """Test if envd is accessible on the given IP"""
    try:
        resp = requests.get(
            f"http://{host_ip}:{port}/",
            timeout=2
        )
        # envd returns 404 for root path, but that means it's responding
        return resp.status_code in [200, 404]
    except:
        return False

def execute_code_via_envd(host_ip, code, port=49983):
    """
    Execute code via envd's Connect RPC API

    envd uses Connect RPC protocol (HTTP/1.1 based)
    Endpoint: /process.Process/Run
    """
    url = f"http://{host_ip}:{port}/process.Process/Start"

    # Connect RPC uses JSON payload
    payload = {
        "process": {
            "cmd": "/bin/sh",
            "args": ["-c", code],
        }
    }

    headers = {
        "Content-Type": "application/json",
        "Connect-Protocol-Version": "1"
    }

    try:
        resp = requests.post(
            url,
            headers=headers,
            json=payload,
            timeout=30
        )
        return resp
    except Exception as e:
        return None

def main():
    print("="*60)
    print("E2B Direct Code Execution Test")
    print("="*60)
    print(f"API URL: {API_URL}")
    print()

    # Step 1: List existing sandboxes
    print("\n📋 Existing sandboxes:")
    sandboxes = list_sandboxes()
    for sb in sandboxes:
        print(f"   - {sb.get('sandboxID')} ({sb.get('state')})")

    # Step 2: Create a new sandbox
    sandbox = create_sandbox()
    if not sandbox:
        print("Failed to create sandbox")
        return 1

    sandbox_id = sandbox.get('sandboxID')

    # Step 3: Wait for VM to initialize
    print("\n⏳ Waiting for VM to initialize...")
    time.sleep(5)

    # Step 4: Find listening IPs
    print("\n🔍 Finding envd listening addresses...")
    listening_ips = find_sandbox_host_ip(sandbox_id)
    print(f"   Found {len(listening_ips)} potential addresses")

    # Step 5: Test each IP
    working_ip = None
    for ip in listening_ips[-5:]:  # Try last 5 (most recent)
        if test_envd_connection(ip):
            print(f"   ✅ {ip}:49983 - envd responding")
            working_ip = ip
            break
        else:
            print(f"   ❌ {ip}:49983 - no response")

    if not working_ip:
        print("\n❌ Could not find working envd connection")
        print("   This might be due to network bridge issues")
        print("\n   Manual test commands:")
        print(f"   sudo nsenter -t $(pgrep -f 'firecracker.*{sandbox_id}') -n curl http://169.254.0.21:49983/")

        # Cleanup
        print(f"\n🗑️ Cleaning up sandbox {sandbox_id}...")
        delete_sandbox(sandbox_id)
        return 1

    # Step 6: Execute test code
    print(f"\n{'='*60}")
    print("Executing Python Code in VM")
    print(f"{'='*60}")

    test_code = '''python3 -c "
import sys
print('Hello from E2B VM!')
print(f'Python version: {sys.version}')
print(f'Platform: {sys.platform}')
result = 2 + 2
print(f'2 + 2 = {result}')
"'''

    print(f"Code: {test_code[:50]}...")
    print()

    resp = execute_code_via_envd(working_ip, test_code)
    if resp:
        print(f"Response status: {resp.status_code}")
        print(f"Response: {resp.text[:500]}")
    else:
        print("Failed to execute code")

    # Step 7: Cleanup
    print(f"\n{'='*60}")
    print("Cleanup")
    print(f"{'='*60}")

    if delete_sandbox(sandbox_id):
        print(f"✅ Sandbox {sandbox_id} deleted")
    else:
        print(f"⚠️ Failed to delete sandbox {sandbox_id}")

    return 0

if __name__ == "__main__":
    sys.exit(main())
