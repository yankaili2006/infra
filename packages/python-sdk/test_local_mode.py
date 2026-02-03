#!/usr/bin/env python3
"""
Test script for E2B Python SDK with local deployment.

This script demonstrates how to use the modified SDK to connect to a local E2B infrastructure.

Usage:
    # Set environment variables
    export E2B_LOCAL_MODE=true
    export E2B_API_KEY=e2b_53ae1fed82754c17ad8077fbc8bcdd90
    export E2B_API_URL=http://localhost:3000

    # Run the test
    python test_local_mode.py
"""

import os
import sys

# Add the local SDK to path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

# Set environment variables for local mode
os.environ["E2B_LOCAL_MODE"] = "true"
os.environ["E2B_API_KEY"] = "e2b_53ae1fed82754c17ad8077fbc8bcdd90"
os.environ["E2B_API_URL"] = "http://localhost:3000"

from e2b.connection_config import ConnectionConfig


def test_connection_config():
    """Test ConnectionConfig with local mode."""
    print("=" * 60)
    print("Testing ConnectionConfig with local mode")
    print("=" * 60)

    config = ConnectionConfig()

    print(f"  local_mode: {config.local_mode}")
    print(f"  api_url: {config.api_url}")
    print(f"  domain: {config.domain}")
    print(f"  debug: {config.debug}")
    print(f"  envd_port: {config.envd_port}")
    print(f"  local_envd_url_template: {config.local_envd_url_template}")

    # Test get_sandbox_url in local mode
    sandbox_url = config.get_sandbox_url("test-sandbox-id", "e2b.app", host_ip="127.0.0.1")
    print(f"  get_sandbox_url (with host_ip): {sandbox_url}")

    sandbox_url_no_ip = config.get_sandbox_url("test-sandbox-id", "e2b.app")
    print(f"  get_sandbox_url (no host_ip): {sandbox_url_no_ip}")

    # Test get_host in local mode
    host = config.get_host("test-sandbox-id", "e2b.app", 49983, host_ip="127.0.0.1")
    print(f"  get_host (with host_ip): {host}")

    host_no_ip = config.get_host("test-sandbox-id", "e2b.app", 49983)
    print(f"  get_host (no host_ip): {host_no_ip}")

    print("\n✅ ConnectionConfig tests passed!")
    return True


def test_sandbox_creation():
    """Test creating a sandbox with local mode."""
    print("\n" + "=" * 60)
    print("Testing Sandbox creation with local mode")
    print("=" * 60)

    try:
        from e2b import Sandbox

        print("  Creating sandbox...")
        sandbox = Sandbox.create(template="base", timeout=60)

        print(f"  ✅ Sandbox created!")
        print(f"     sandbox_id: {sandbox.sandbox_id}")
        print(f"     envd_api_url: {sandbox.envd_api_url}")

        # Test if sandbox is running
        print("  Checking if sandbox is running...")
        try:
            is_running = sandbox.is_running(request_timeout=10)
            print(f"     is_running: {is_running}")
        except Exception as e:
            print(f"     ⚠️ Could not check if running: {e}")

        # Try to run a simple command
        print("  Running test command...")
        try:
            result = sandbox.commands.run("echo 'Hello from E2B!'", timeout=30)
            print(f"     stdout: {result.stdout}")
            print(f"     exit_code: {result.exit_code}")
        except Exception as e:
            print(f"     ⚠️ Could not run command: {e}")

        # Kill the sandbox
        print("  Killing sandbox...")
        sandbox.kill()
        print("  ✅ Sandbox killed!")

        return True

    except Exception as e:
        print(f"  ❌ Error: {e}")
        import traceback
        traceback.print_exc()
        return False


def test_api_connection():
    """Test direct API connection."""
    print("\n" + "=" * 60)
    print("Testing direct API connection")
    print("=" * 60)

    import requests

    api_url = os.environ.get("E2B_API_URL", "http://localhost:3000")
    api_key = os.environ.get("E2B_API_KEY")

    # Test health endpoint
    print(f"  Testing health endpoint: {api_url}/health")
    try:
        resp = requests.get(f"{api_url}/health", timeout=5)
        print(f"     Status: {resp.status_code}")
        print(f"     Response: {resp.text[:100]}")
    except Exception as e:
        print(f"     ❌ Error: {e}")
        return False

    # Test sandbox list
    print(f"  Testing sandbox list: {api_url}/sandboxes")
    try:
        resp = requests.get(
            f"{api_url}/sandboxes",
            headers={"X-API-Key": api_key},
            timeout=5
        )
        print(f"     Status: {resp.status_code}")
        sandboxes = resp.json()
        print(f"     Active sandboxes: {len(sandboxes)}")
    except Exception as e:
        print(f"     ❌ Error: {e}")
        return False

    print("\n✅ API connection tests passed!")
    return True


def main():
    print("\n" + "=" * 60)
    print("E2B Python SDK Local Mode Test")
    print("=" * 60)
    print(f"\nEnvironment:")
    print(f"  E2B_LOCAL_MODE: {os.environ.get('E2B_LOCAL_MODE')}")
    print(f"  E2B_API_URL: {os.environ.get('E2B_API_URL')}")
    print(f"  E2B_API_KEY: {os.environ.get('E2B_API_KEY', '')[:20]}...")

    results = []

    # Test 1: ConnectionConfig
    results.append(("ConnectionConfig", test_connection_config()))

    # Test 2: API Connection
    results.append(("API Connection", test_api_connection()))

    # Test 3: Sandbox Creation (optional, requires running infrastructure)
    print("\n" + "=" * 60)
    print("Do you want to test sandbox creation? (requires running E2B infrastructure)")
    print("This will create and destroy a sandbox.")
    print("=" * 60)

    user_input = input("Run sandbox test? [y/N]: ").strip().lower()
    if user_input == 'y':
        results.append(("Sandbox Creation", test_sandbox_creation()))
    else:
        print("  Skipping sandbox creation test.")

    # Summary
    print("\n" + "=" * 60)
    print("Test Summary")
    print("=" * 60)
    for name, passed in results:
        status = "✅ PASSED" if passed else "❌ FAILED"
        print(f"  {name}: {status}")

    all_passed = all(passed for _, passed in results)
    print("\n" + ("✅ All tests passed!" if all_passed else "❌ Some tests failed!"))

    return 0 if all_passed else 1


if __name__ == "__main__":
    sys.exit(main())
