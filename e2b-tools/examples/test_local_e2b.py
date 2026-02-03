#!/usr/bin/env python3
"""
Test E2B SDK against local infrastructure
Based on examples from ~/github/E2B/packages/python-sdk/tests/
"""

import os
import sys

# Set environment variables for local E2B
os.environ["E2B_API_KEY"] = "e2b_53ae1fed82754c17ad8077fbc8bcdd90"
os.environ["E2B_API_URL"] = "http://localhost:3000"

from e2b import Sandbox

def test_create_sandbox():
    """Test creating a sandbox"""
    print("=" * 60)
    print("Test 1: Create Sandbox")
    print("=" * 60)

    try:
        # Use Sandbox.create() for SDK 2.9.0+
        sandbox = Sandbox.create(template="base", timeout=300)
        print(f"✅ Sandbox created: {sandbox.sandbox_id}")
        return sandbox
    except Exception as e:
        print(f"❌ Failed to create sandbox: {e}")
        import traceback
        traceback.print_exc()
        return None

def test_run_command(sandbox):
    """Test running a command"""
    print("\n" + "=" * 60)
    print("Test 2: Run Command")
    print("=" * 60)

    try:
        text = "Hello from E2B VM!"
        cmd = sandbox.commands.run(f'echo "{text}"')
        print(f"Exit code: {cmd.exit_code}")
        print(f"Stdout: {cmd.stdout}")

        if cmd.exit_code == 0 and text in cmd.stdout:
            print("✅ Command executed successfully")
            return True
        else:
            print("❌ Command output mismatch")
            return False
    except Exception as e:
        print(f"❌ Failed to run command: {e}")
        return False

def test_run_python(sandbox):
    """Test running Python code"""
    print("\n" + "=" * 60)
    print("Test 3: Run Python Code")
    print("=" * 60)

    try:
        python_code = '''
import sys
print(f"Python version: {sys.version}")
print(f"Platform: {sys.platform}")
result = 2 + 2
print(f"2 + 2 = {result}")
'''
        cmd = sandbox.commands.run(f'python3 -c "{python_code}"')
        print(f"Exit code: {cmd.exit_code}")
        print(f"Output:\n{cmd.stdout}")

        if cmd.exit_code == 0:
            print("✅ Python code executed successfully")
            return True
        else:
            print(f"❌ Python execution failed: {cmd.stderr}")
            return False
    except Exception as e:
        print(f"❌ Failed to run Python: {e}")
        return False

def test_filesystem(sandbox):
    """Test filesystem operations"""
    print("\n" + "=" * 60)
    print("Test 4: Filesystem Operations")
    print("=" * 60)

    try:
        # Write a file
        content = "Hello from E2B filesystem test!"
        sandbox.files.write("/tmp/test.txt", content)
        print(f"✅ File written: /tmp/test.txt")

        # Read the file
        read_content = sandbox.files.read("/tmp/test.txt")
        print(f"✅ File read: {read_content}")

        if read_content == content:
            print("✅ Filesystem test passed")
            return True
        else:
            print("❌ Content mismatch")
            return False
    except Exception as e:
        print(f"❌ Filesystem test failed: {e}")
        return False

def test_list_files(sandbox):
    """Test listing files"""
    print("\n" + "=" * 60)
    print("Test 5: List Files")
    print("=" * 60)

    try:
        files = sandbox.files.list("/")
        print(f"Root directory contents ({len(files)} items):")
        for f in files[:10]:
            print(f"  - {f.name} ({'dir' if f.is_dir else 'file'})")
        if len(files) > 10:
            print(f"  ... and {len(files) - 10} more")
        print("✅ List files test passed")
        return True
    except Exception as e:
        print(f"❌ List files failed: {e}")
        return False

def main():
    print("=" * 60)
    print("E2B Local Infrastructure Test")
    print("=" * 60)
    print(f"API URL: {os.environ.get('E2B_API_URL')}")
    print(f"API Key: {os.environ.get('E2B_API_KEY')[:20]}...")
    print()

    # Create sandbox
    sandbox = test_create_sandbox()
    if not sandbox:
        print("\n❌ Cannot continue without sandbox")
        return 1

    results = []

    # Run tests
    results.append(("Run Command", test_run_command(sandbox)))
    results.append(("Run Python", test_run_python(sandbox)))
    results.append(("Filesystem", test_filesystem(sandbox)))
    results.append(("List Files", test_list_files(sandbox)))

    # Cleanup
    print("\n" + "=" * 60)
    print("Cleanup")
    print("=" * 60)
    try:
        sandbox.kill()
        print("✅ Sandbox killed")
    except Exception as e:
        print(f"⚠️ Failed to kill sandbox: {e}")

    # Summary
    print("\n" + "=" * 60)
    print("Test Summary")
    print("=" * 60)
    passed = sum(1 for _, r in results if r)
    total = len(results)
    print(f"Passed: {passed}/{total}")
    for name, result in results:
        status = "✅" if result else "❌"
        print(f"  {status} {name}")

    return 0 if passed == total else 1

if __name__ == "__main__":
    sys.exit(main())
