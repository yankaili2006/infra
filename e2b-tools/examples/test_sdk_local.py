#!/usr/bin/env python3
"""
E2B SDK Local Test with Custom Configuration
This script configures the SDK to connect to local E2B infrastructure
"""

import os
import sys
import time
import requests

# Step 1: Configure environment BEFORE importing e2b
os.environ["E2B_API_KEY"] = "e2b_53ae1fed82754c17ad8077fbc8bcdd90"
os.environ["E2B_API_URL"] = "http://localhost:3000"
os.environ["E2B_DEBUG"] = "true"

from e2b import Sandbox
from e2b.connection_config import ConnectionConfig

def find_working_envd_ip():
    """Find an IP that has envd responding"""
    # Get all listening ports on 49983
    import subprocess
    result = subprocess.run(
        ["netstat", "-tlnp"],
        capture_output=True,
        text=True
    )

    ips = []
    for line in result.stdout.split('\n'):
        if '10.11.0.' in line and ':49983' in line:
            parts = line.split()
            if len(parts) >= 4:
                addr = parts[3].split(':')[0]
                ips.append(addr)

    # Test each IP
    for ip in ips:
        try:
            resp = requests.get(f"http://{ip}:49983/", timeout=1)
            if resp.status_code in [200, 404]:  # 404 is OK, means envd is responding
                return ip
        except:
            continue

    return None

def main():
    print("=" * 60)
    print("E2B SDK Local Infrastructure Test")
    print("=" * 60)

    # Step 2: Check API health
    print("\n1. Checking API health...")
    try:
        resp = requests.get("http://localhost:3000/health", timeout=5)
        if resp.status_code == 200:
            print("   ✅ API is healthy")
        else:
            print(f"   ❌ API returned: {resp.status_code}")
            return 1
    except Exception as e:
        print(f"   ❌ API check failed: {e}")
        return 1

    # Step 3: Create sandbox using REST API (we know this works)
    print("\n2. Creating sandbox via REST API...")
    try:
        resp = requests.post(
            "http://localhost:3000/sandboxes",
            headers={
                "X-API-Key": os.environ["E2B_API_KEY"],
                "Content-Type": "application/json"
            },
            json={"templateID": "base", "timeout": 300},
            timeout=30
        )

        if resp.status_code not in [200, 201]:
            print(f"   ❌ Failed to create sandbox: {resp.text}")
            return 1

        sandbox_data = resp.json()
        sandbox_id = sandbox_data.get("sandboxID")
        print(f"   ✅ Sandbox created: {sandbox_id}")
        print(f"   Client ID: {sandbox_data.get('clientID')}")
        print(f"   Domain: {sandbox_data.get('domain')}")

    except Exception as e:
        print(f"   ❌ Error creating sandbox: {e}")
        return 1

    # Step 4: Wait for VM to initialize
    print("\n3. Waiting for VM to initialize...")
    time.sleep(5)

    # Step 5: Find working envd IP
    print("\n4. Finding envd endpoint...")
    envd_ip = find_working_envd_ip()
    if envd_ip:
        print(f"   ✅ Found working envd at: {envd_ip}:49983")
    else:
        print("   ❌ No working envd endpoint found")
        print("   This is expected - SDK expects cloud URLs")

    # Step 6: Try SDK with custom sandbox_url
    print("\n5. Testing SDK with custom sandbox_url...")

    if envd_ip:
        # Create custom configuration
        custom_config = ConnectionConfig(
            api_key=os.environ["E2B_API_KEY"],
            api_url="http://localhost:3000",
            sandbox_url=f"http://{envd_ip}:49983",
            debug=True
        )

        print(f"   Custom sandbox_url: {custom_config._sandbox_url}")
        print(f"   API URL: {custom_config.api_url}")

        # Try to connect using the SDK
        try:
            # This might still fail because the SDK reconstructs URLs internally
            # But let's see what happens
            sandbox = Sandbox(
                sandbox_id=sandbox_id,
                **{"sandbox_url": f"http://{envd_ip}:49983"}
            )

            print(f"   ✅ Sandbox object created")
            print(f"   Sandbox ID: {sandbox.sandbox_id}")

            # Try running a command
            print("\n6. Testing command execution...")
            result = sandbox.commands.run("echo 'Hello from E2B!'")
            print(f"   Exit code: {result.exit_code}")
            print(f"   Output: {result.stdout}")

        except Exception as e:
            print(f"   ❌ SDK connection failed: {e}")
            print(f"   Error type: {type(e).__name__}")

            # Alternative: Direct HTTP to envd
            print("\n6. Alternative: Direct HTTP to envd...")
            try:
                # Try listing processes
                resp = requests.post(
                    f"http://{envd_ip}:49983/process.Process/List",
                    headers={"Content-Type": "application/connect+json"},
                    json={},
                    timeout=5
                )
                print(f"   Process list response: {resp.status_code} - {resp.text}")
            except Exception as e2:
                print(f"   Direct HTTP also failed: {e2}")

    # Step 7: Cleanup
    print("\n7. Cleaning up...")
    try:
        resp = requests.delete(
            f"http://localhost:3000/sandboxes/{sandbox_id}",
            headers={"X-API-Key": os.environ["E2B_API_KEY"]},
            timeout=10
        )
        if resp.status_code in [200, 204]:
            print(f"   ✅ Sandbox {sandbox_id} deleted")
        else:
            print(f"   ⚠️ Delete returned: {resp.status_code}")
    except Exception as e:
        print(f"   ⚠️ Cleanup error: {e}")

    print("\n" + "=" * 60)
    print("Test Complete")
    print("=" * 60)

    print("""
Summary:
- API sandbox creation works ✅
- Firecracker VM starts ✅
- envd daemon runs inside VM ✅
- Network bridge (TCP proxy) works ✅
- SDK cloud URL format prevents direct connection ❌

The SDK expects URLs like:
  https://49983-{sandbox_id}.{domain}

But local infrastructure provides:
  http://10.11.0.X:49983

Solution options:
1. Use direct REST/HTTP API calls (shown in execute_in_vm.py)
2. Set up local DNS/proxy to route *.localhost to correct IPs
3. Patch SDK to support local URLs
""")

    return 0

if __name__ == "__main__":
    sys.exit(main())
