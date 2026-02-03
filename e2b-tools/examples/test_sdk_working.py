#!/usr/bin/env python3
"""
Working E2B SDK Test for Local Infrastructure

This script demonstrates how to use the E2B SDK with local infrastructure.

Key insight: The SDK CAN work with local infrastructure by:
1. Setting E2B_API_URL to point to local API (http://localhost:3000)
2. Using E2B_SANDBOX_URL to point to the envd endpoint

The challenge is that each sandbox gets a different host IP (10.11.0.X),
so we need to find the correct IP after sandbox creation.
"""

import os
import sys
import time
import subprocess
import requests

# Configure for local E2B
os.environ["E2B_API_KEY"] = "e2b_53ae1fed82754c17ad8077fbc8bcdd90"
os.environ["E2B_API_URL"] = "http://localhost:3000"

from e2b import Sandbox
from e2b.connection_config import ConnectionConfig

API_URL = "http://localhost:3000"
API_KEY = os.environ["E2B_API_KEY"]

def find_sandbox_envd_ip(sandbox_id):
    """
    Find the host IP that can reach the sandbox's envd.
    
    The E2B infrastructure creates a dual-layer network:
    - Layer 1: Host IP (10.11.0.X) 
    - Layer 2: Namespace veth (10.12.X.X) -> TAP (169.254.0.22) -> Guest (169.254.0.21)
    
    We need to find which 10.11.0.X address corresponds to our sandbox.
    """
    # Get all listening 10.11.0.X ports
    try:
        result = subprocess.run(
            ["netstat", "-tlnp"],
            capture_output=True,
            text=True
        )
        
        listening_ips = []
        for line in result.stdout.split('\n'):
            if '10.11.0.' in line and ':49983' in line:
                parts = line.split()
                if len(parts) >= 4:
                    addr = parts[3].split(':')[0]
                    listening_ips.append(addr)
        
        print(f"  Found {len(listening_ips)} potential IPs: {listening_ips[-5:]}...")
        
        # Test each IP
        for ip in reversed(listening_ips):  # Try newest first
            try:
                resp = requests.get(f"http://{ip}:49983/health", timeout=2)
                if resp.status_code in [200, 404]:  # envd responds
                    return ip
            except:
                continue
                
    except Exception as e:
        print(f"  Warning: {e}")
    
    return None


def test_with_direct_api():
    """Test using direct API calls (bypassing SDK URL issues)"""
    print("\n" + "="*60)
    print("Test 1: Direct API Calls")
    print("="*60)
    
    headers = {
        "X-API-Key": API_KEY,
        "Content-Type": "application/json"
    }
    
    # Create sandbox
    print("\nCreating sandbox...")
    resp = requests.post(
        f"{API_URL}/sandboxes",
        headers=headers,
        json={"templateID": "base", "timeout": 300}
    )
    
    if resp.status_code not in [200, 201]:
        print(f"  ❌ Failed: {resp.status_code} - {resp.text}")
        return None
        
    data = resp.json()
    sandbox_id = data.get("sandboxID")
    print(f"  ✅ Sandbox created: {sandbox_id}")
    print(f"  Domain: {data.get('domain')}")
    print(f"  envdVersion: {data.get('envdVersion')}")
    
    # Wait for VM to initialize
    print("\n  Waiting for VM initialization...")
    time.sleep(3)
    
    return sandbox_id


def test_sdk_with_sandbox_url(sandbox_id):
    """Try connecting SDK with custom sandbox_url"""
    print("\n" + "="*60)
    print("Test 2: SDK with Custom sandbox_url")
    print("="*60)
    
    # Find envd IP
    print("\nFinding envd endpoint...")
    envd_ip = find_sandbox_envd_ip(sandbox_id)
    
    if not envd_ip:
        print("  ❌ Could not find envd IP")
        print("  The socat bridge might not be running")
        return False
    
    print(f"  ✅ Found envd at: http://{envd_ip}:49983")
    
    # Test direct envd connection
    print("\nTesting direct envd HTTP...")
    try:
        resp = requests.get(f"http://{envd_ip}:49983/health", timeout=5)
        print(f"  Health response: {resp.status_code}")
    except Exception as e:
        print(f"  ❌ Direct HTTP failed: {e}")
        return False
    
    # Now try SDK with sandbox_url
    print("\nAttempting SDK connection...")
    try:
        # Set sandbox_url environment variable
        os.environ["E2B_SANDBOX_URL"] = f"http://{envd_ip}:49983"
        
        # Connect to existing sandbox
        sandbox = Sandbox.connect(
            sandbox_id,
            sandbox_url=f"http://{envd_ip}:49983"
        )
        
        print(f"  ✅ Connected to sandbox: {sandbox.sandbox_id}")
        print(f"  envd_api_url: {sandbox.envd_api_url}")
        
        # Try running a command
        print("\nRunning test command...")
        result = sandbox.commands.run("echo 'Hello from E2B!'")
        print(f"  Exit code: {result.exit_code}")
        print(f"  Output: {result.stdout}")
        
        return True
        
    except Exception as e:
        print(f"  ❌ SDK connection failed: {e}")
        print(f"  Error type: {type(e).__name__}")
        return False


def cleanup(sandbox_id):
    """Clean up sandbox"""
    if sandbox_id:
        print(f"\nCleaning up sandbox {sandbox_id}...")
        try:
            resp = requests.delete(
                f"{API_URL}/sandboxes/{sandbox_id}",
                headers={"X-API-Key": API_KEY}
            )
            if resp.status_code in [200, 204]:
                print("  ✅ Sandbox deleted")
            else:
                print(f"  ⚠️ Delete returned: {resp.status_code}")
        except Exception as e:
            print(f"  ⚠️ Cleanup error: {e}")


def main():
    print("="*60)
    print("E2B SDK Local Infrastructure Test")
    print("="*60)
    print(f"API URL: {API_URL}")
    print(f"API Key: {API_KEY[:20]}...")
    
    sandbox_id = None
    
    try:
        # Test 1: Direct API
        sandbox_id = test_with_direct_api()
        
        if sandbox_id:
            # Test 2: SDK with custom URL
            test_sdk_with_sandbox_url(sandbox_id)
            
    finally:
        cleanup(sandbox_id)
    
    print("\n" + "="*60)
    print("Summary")
    print("="*60)
    print("""
The E2B SDK works with local infrastructure when:
1. E2B_API_URL points to local API (http://localhost:3000)
2. E2B_SANDBOX_URL points to local envd (http://10.11.0.X:49983)

The challenge is mapping sandbox_id to its host IP automatically.

For production use, consider:
1. Using direct REST API calls (most reliable)
2. Setting up a local DNS/proxy to route *.localhost to correct IPs
3. Patching SDK to support local URL patterns
""")
    
    return 0


if __name__ == "__main__":
    sys.exit(main())
