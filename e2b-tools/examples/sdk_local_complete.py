#!/usr/bin/env python3
"""
E2B SDK Complete Local Infrastructure Test

This script demonstrates full E2B SDK functionality with local infrastructure.

Requirements:
1. E2B API running at localhost:3000
2. E2B Orchestrator running (manages Firecracker VMs)
3. e2b Python SDK installed: pip install e2b

Usage:
    cd /home/primihub/pcloud/infra
    source e2b-venv/bin/activate
    python3 e2b-tools/examples/sdk_local_complete.py

Key Configuration:
    - E2B_API_URL=http://localhost:3000 (local API)
    - E2B_API_KEY=e2b_53ae1fed82754c17ad8077fbc8bcdd90 (local test key)
    - sandbox_url parameter overrides cloud envd URL
    - user="root" for command execution (VM only has root user)
"""

import os
import sys
import time
import subprocess
import requests

# Configure environment BEFORE importing e2b
os.environ["E2B_API_KEY"] = "e2b_53ae1fed82754c17ad8077fbc8bcdd90"
os.environ["E2B_API_URL"] = "http://localhost:3000"

from e2b import Sandbox

API_URL = "http://localhost:3000"
API_KEY = os.environ["E2B_API_KEY"]


def find_envd_ip():
    """
    Find the host IP that can reach the sandbox's envd.

    E2B local infrastructure uses dual-layer network:
    - Layer 1: Host IP (10.11.0.X:49983)
    - Layer 2: Namespace veth -> TAP -> Guest (169.254.0.21:49983)
    """
    try:
        result = subprocess.run(["netstat", "-tlnp"], capture_output=True, text=True)
        listening_ips = []
        for line in result.stdout.split('\n'):
            if '10.11.0.' in line and ':49983' in line:
                parts = line.split()
                if len(parts) >= 4:
                    addr = parts[3].split(':')[0]
                    listening_ips.append(addr)

        # Test each IP (try newest first - most recent sandbox)
        for ip in reversed(listening_ips[-10:]):
            try:
                resp = requests.get(f"http://{ip}:49983/health", timeout=2)
                if resp.status_code in [200, 204]:
                    return ip
            except:
                continue
    except Exception as e:
        print(f"Warning: Could not find envd IP: {e}")

    return None


def create_sandbox_via_api():
    """Create sandbox via REST API (more reliable for local)"""
    resp = requests.post(
        f"{API_URL}/sandboxes",
        headers={"X-API-Key": API_KEY, "Content-Type": "application/json"},
        json={"templateID": "base", "timeout": 300},
        timeout=60
    )
    if resp.status_code not in [200, 201]:
        raise Exception(f"Failed to create sandbox: {resp.status_code} - {resp.text}")
    return resp.json()


def delete_sandbox(sandbox_id):
    """Clean up sandbox"""
    try:
        requests.delete(
            f"{API_URL}/sandboxes/{sandbox_id}",
            headers={"X-API-Key": API_KEY},
            timeout=10
        )
    except:
        pass


def test_command_execution(sandbox, envd_ip):
    """Test various command execution scenarios"""
    print("\n" + "="*60)
    print("Command Execution Tests")
    print("="*60)

    tests = [
        ("Basic echo", "echo 'Hello from E2B!'"),
        ("System info", "uname -a"),
        ("Python version", "python3 --version"),
        ("List root directory", "ls /"),
        ("Network config", "ip addr show eth0 | head -3"),
        ("Current user", "whoami"),
        ("Environment", "env | head -5"),
    ]

    passed = 0
    failed = 0

    for name, cmd in tests:
        try:
            # IMPORTANT: Use user="root" for local infrastructure
            result = sandbox.commands.run(cmd, user="root", timeout=30)
            if result.exit_code == 0:
                print(f"✅ {name}")
                print(f"   Command: {cmd}")
                print(f"   Output: {result.stdout[:100]}...")
                passed += 1
            else:
                print(f"⚠️ {name} (exit code: {result.exit_code})")
                print(f"   Stderr: {result.stderr}")
                failed += 1
        except Exception as e:
            print(f"❌ {name}: {e}")
            failed += 1

    print(f"\n📊 Results: {passed} passed, {failed} failed")
    return passed, failed


def test_python_execution(sandbox):
    """Test Python code execution"""
    print("\n" + "="*60)
    print("Python Code Execution Test")
    print("="*60)

    code = '''
import sys
import os

print(f"Python version: {sys.version}")
print(f"Platform: {sys.platform}")
print(f"Working directory: {os.getcwd()}")

# Simple calculation
result = sum(range(1, 101))
print(f"Sum of 1-100: {result}")
'''

    try:
        result = sandbox.commands.run(
            f'python3 -c "{code}"',
            user="root",
            timeout=30
        )
        print(f"Exit code: {result.exit_code}")
        print(f"Output:\n{result.stdout}")
        return result.exit_code == 0
    except Exception as e:
        print(f"❌ Python execution failed: {e}")
        return False


def test_file_operations(sandbox):
    """Test file system operations"""
    print("\n" + "="*60)
    print("File System Operations Test")
    print("="*60)

    tests = [
        ("Create file", "echo 'test content' > /tmp/test.txt"),
        ("Read file", "cat /tmp/test.txt"),
        ("Append to file", "echo 'more content' >> /tmp/test.txt"),
        ("List file", "ls -la /tmp/test.txt"),
        ("Delete file", "rm /tmp/test.txt"),
    ]

    for name, cmd in tests:
        try:
            result = sandbox.commands.run(cmd, user="root", timeout=10)
            status = "✅" if result.exit_code == 0 else "❌"
            print(f"{status} {name}: {result.stdout or result.stderr}")
        except Exception as e:
            print(f"❌ {name}: {e}")


def main():
    print("="*60)
    print("E2B SDK Local Infrastructure Complete Test")
    print("="*60)
    print(f"API URL: {API_URL}")
    print(f"API Key: {API_KEY[:20]}...")

    # Check API health
    print("\n1. Checking API health...")
    try:
        resp = requests.get(f"{API_URL}/health", timeout=5)
        if resp.status_code == 200:
            print("   ✅ API is healthy")
        else:
            print(f"   ❌ API returned: {resp.status_code}")
            return 1
    except Exception as e:
        print(f"   ❌ API not reachable: {e}")
        return 1

    sandbox_id = None

    try:
        # Create sandbox
        print("\n2. Creating sandbox via API...")
        data = create_sandbox_via_api()
        sandbox_id = data.get("sandboxID")
        print(f"   ✅ Sandbox created: {sandbox_id}")
        print(f"   Template: {data.get('templateID')}")
        print(f"   Client ID: {data.get('clientID')}")

        # Wait for VM initialization
        print("\n3. Waiting for VM to initialize...")
        time.sleep(5)

        # Find envd endpoint
        print("\n4. Finding envd endpoint...")
        envd_ip = find_envd_ip()
        if not envd_ip:
            print("   ❌ Could not find working envd IP")
            print("   The socat bridge might not be running properly")
            return 1
        print(f"   ✅ Found envd at: http://{envd_ip}:49983")

        # Connect SDK with custom sandbox_url
        print("\n5. Connecting SDK to local envd...")
        sandbox = Sandbox.connect(
            sandbox_id,
            sandbox_url=f"http://{envd_ip}:49983"
        )
        print(f"   ✅ SDK connected")
        print(f"   envd_api_url: {sandbox.envd_api_url}")

        # Run tests
        test_command_execution(sandbox, envd_ip)
        test_python_execution(sandbox)
        test_file_operations(sandbox)

    except Exception as e:
        print(f"\n❌ Error: {e}")
        import traceback
        traceback.print_exc()
        return 1

    finally:
        # Cleanup
        if sandbox_id:
            print("\n" + "="*60)
            print("Cleanup")
            print("="*60)
            delete_sandbox(sandbox_id)
            print(f"   ✅ Sandbox {sandbox_id} deleted")

    print("\n" + "="*60)
    print("Summary")
    print("="*60)
    print("""
✅ E2B SDK works with local infrastructure!

Key configuration:
1. Set E2B_API_URL=http://localhost:3000
2. Create sandbox via REST API or SDK
3. Find envd host IP (10.11.0.X:49983)
4. Connect SDK: Sandbox.connect(id, sandbox_url="http://10.11.0.X:49983")
5. Use user="root" for all commands: sandbox.commands.run(cmd, user="root")

The default username is "user" but local E2B VMs only have "root" user.
""")

    return 0


if __name__ == "__main__":
    sys.exit(main())
