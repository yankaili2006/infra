#!/usr/bin/env python3
"""
Test desktop template to see if it has the same TAP NO-CARRIER issue
"""

import sys
import os
from pathlib import Path

# Add SDK path
sdk_path = Path(__file__).parent
sys.path.insert(0, str(sdk_path))

from e2b import Sandbox
import dotenv

# Load configuration
dotenv.load_dotenv('.env.local')

print("=" * 70)
print("Testing Desktop Template")
print("=" * 70)
print(f"API URL: {os.getenv('E2B_API_URL')}")
print("=" * 70)

try:
    # Test with desktop template
    print("\n[1] Creating desktop template VM...")
    sandbox = Sandbox.create(template="desktop-template-000-0000-0000-000000000001", timeout=600)
    print(f"✓ Desktop sandbox created: {sandbox.sandbox_id}")

    # Try to execute a simple command
    print("\n[2] Testing command execution...")
    result = sandbox.commands.run("echo 'Hello from desktop VM'")
    print(f"✓ Command executed successfully!")
    print(f"  Output: {result.stdout.strip()}")
    print(f"  Exit code: {result.exit_code}")

    # Close sandbox
    print("\n[3] Closing sandbox...")
    sandbox.close()
    print("✓ Desktop template test PASSED!")

except Exception as e:
    print(f"\n✗ Desktop template test FAILED: {e}")
    import traceback
    traceback.print_exc()
    sys.exit(1)
