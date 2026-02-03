#!/usr/bin/env python3
"""
Code Interpreter VM Test Script

This script tests the code-interpreter-v1 template by:
1. Creating a VM based on the template
2. Executing shell and code in the VM
3. Installing Python if needed
4. Verifying the code interpretation results

Usage:
    cd /home/primihub/pcloud/infra
    source e2b-venv/bin/activate
    python3 e2b-tools/examples/test_code_interpreter.py
"""

import os
import sys
import time
import subprocess
import requests
import json
import argparse

# Configure environment
os.environ["E2B_API_KEY"] = "e2b_53ae1fed82754c17ad8077fbc8bcdd90"
os.environ["E2B_API_URL"] = "http://localhost:3000"

API_URL = "http://localhost:3000"
API_KEY = os.environ["E2B_API_KEY"]
TEMPLATE_ID = "code-interpreter-v1"

# Parse arguments
parser = argparse.ArgumentParser(description='Code Interpreter VM Test')
parser.add_argument('--install-python', action='store_true', help='Install Python in VM')
parser.add_argument('--keep-sandbox', action='store_true', help='Keep sandbox after test')
args, _ = parser.parse_known_args()


def print_section(title):
    """Print section header"""
    print(f"\n{'='*60}")
    print(f"  {title}")
    print('='*60)


def check_api_health():
    """Check if API is healthy"""
    try:
        resp = requests.get(f"{API_URL}/health", timeout=5)
        return resp.status_code == 200
    except:
        return False


def find_envd_ip():
    """Find the envd IP address from listening ports"""
    try:
        result = subprocess.run(["netstat", "-tlnp"], capture_output=True, text=True)
        listening_ips = []
        for line in result.stdout.split('\n'):
            if '10.11.0.' in line and ':49983' in line:
                parts = line.split()
                if len(parts) >= 4:
                    addr = parts[3].split(':')[0]
                    listening_ips.append(addr)

        # Test each IP (newest first)
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


def create_sandbox():
    """Create a sandbox via REST API"""
    print_section("Creating Sandbox")
    print(f"Template: {TEMPLATE_ID}")

    resp = requests.post(
        f"{API_URL}/sandboxes",
        headers={"X-API-Key": API_KEY, "Content-Type": "application/json"},
        json={"templateID": TEMPLATE_ID, "timeout": 300},
        timeout=60
    )

    if resp.status_code not in [200, 201]:
        print(f"ERROR: Failed to create sandbox: {resp.status_code}")
        print(f"Response: {resp.text}")
        return None

    data = resp.json()
    sandbox_id = data.get("sandboxID")
    print(f"Sandbox ID: {sandbox_id}")
    print(f"Client ID: {data.get('clientID')}")
    return sandbox_id


def delete_sandbox(sandbox_id):
    """Delete a sandbox"""
    try:
        requests.delete(
            f"{API_URL}/sandboxes/{sandbox_id}",
            headers={"X-API-Key": API_KEY},
            timeout=10
        )
        print(f"Sandbox {sandbox_id} deleted")
    except Exception as e:
        print(f"Warning: Failed to delete sandbox: {e}")


def execute_code_via_sdk(sandbox_id, envd_ip):
    """Execute code using E2B SDK"""
    from e2b import Sandbox

    print_section("SDK Connection Test")
    print(f"Connecting to: http://{envd_ip}:49983")

    try:
        sandbox = Sandbox.connect(sandbox_id, sandbox_url=f"http://{envd_ip}:49983")
        print("SDK connected successfully")
        return sandbox
    except Exception as e:
        print(f"ERROR: SDK connection failed: {e}")
        return None


def run_code_tests(sandbox):
    """Run various code execution tests"""
    print_section("Code Execution Tests")

    # First check if Python is available
    print("\n--- Checking Python availability ---")
    result = sandbox.commands.run("which python3 || which python", user="root", timeout=10)
    python_available = result.exit_code == 0 and result.stdout.strip()

    if python_available:
        print(f"Python found at: {result.stdout.strip()}")
        python_cmd = result.stdout.strip()
    else:
        print("Python not found in VM")
        if args.install_python:
            print("\n--- Installing Python (this may take a while) ---")
            install_result = sandbox.commands.run(
                "apt-get update && apt-get install -y python3 python3-pip",
                user="root",
                timeout=300
            )
            if install_result.exit_code == 0:
                print("Python installed successfully")
                python_cmd = "/usr/bin/python3"
                python_available = True
            else:
                print(f"Failed to install Python: {install_result.stderr}")
        else:
            print("Use --install-python flag to install Python in VM")
            print("Running shell tests only...")

    passed = 0
    failed = 0

    # Shell tests (always run)
    shell_tests = [
        {
            "name": "Basic Echo",
            "cmd": "echo 'Hello from Code Interpreter VM!'"
        },
        {
            "name": "System Info",
            "cmd": "uname -a"
        },
        {
            "name": "Current User",
            "cmd": "whoami"
        },
        {
            "name": "Working Directory",
            "cmd": "pwd"
        },
        {
            "name": "Math Calculation (bc)",
            "cmd": "echo '10 + 20' | bc 2>/dev/null || echo $((10 + 20))"
        },
        {
            "name": "File Operations",
            "cmd": "echo 'test content' > /tmp/test.txt && cat /tmp/test.txt && rm /tmp/test.txt"
        },
        {
            "name": "Environment Variables",
            "cmd": "env | head -5"
        },
        {
            "name": "Network Check",
            "cmd": "ip addr show eth0 | grep inet"
        }
    ]

    print("\n=== Shell Command Tests ===")
    for test in shell_tests:
        print(f"\n--- {test['name']} ---")
        try:
            result = sandbox.commands.run(test["cmd"], user="root", timeout=30)
            if result.exit_code == 0:
                output = result.stdout.strip()[:200]
                print(f"Output: {output}")
                print("PASSED")
                passed += 1
            else:
                print(f"Exit code: {result.exit_code}")
                print(f"Stderr: {result.stderr}")
                print("FAILED")
                failed += 1
        except Exception as e:
            print(f"ERROR: {e}")
            print("FAILED")
            failed += 1

    # Python tests (if available)
    if python_available:
        python_tests = [
            {
                "name": "Basic Python Print",
                "code": "print('Hello from Python!')"
            },
            {
                "name": "Math Calculation",
                "code": "result = sum(range(1, 101))\nprint(f'Sum of 1-100: {result}')"
            },
            {
                "name": "System Info",
                "code": "import sys\nimport os\nprint(f'Python: {sys.version}')\nprint(f'CWD: {os.getcwd()}')"
            },
            {
                "name": "Data Processing",
                "code": "data = [1, 2, 3, 4, 5]\nsquared = [x**2 for x in data]\nprint(f'Squared: {squared}')"
            },
            {
                "name": "JSON Processing",
                "code": "import json\ndata = {'name': 'test', 'values': [1, 2, 3]}\nprint(json.dumps(data))"
            }
        ]

        print("\n=== Python Code Tests ===")
        for test in python_tests:
            print(f"\n--- {test['name']} ---")
            try:
                # Escape single quotes in code
                code = test["code"].replace("'", "'\"'\"'")
                cmd = f"{python_cmd} -c '{code}'"
                result = sandbox.commands.run(cmd, user="root", timeout=30)

                if result.exit_code == 0:
                    print(f"Output: {result.stdout.strip()[:200]}")
                    print("PASSED")
                    passed += 1
                else:
                    print(f"Exit code: {result.exit_code}")
                    print(f"Stderr: {result.stderr}")
                    print("FAILED")
                    failed += 1
            except Exception as e:
                print(f"ERROR: {e}")
                print("FAILED")
                failed += 1

    return passed, failed


def run_interactive_interpreter_test(sandbox):
    """Test interactive script execution"""
    print_section("Interactive Script Test")

    # First check if Python is available
    result = sandbox.commands.run("which python3 || which python", user="root", timeout=10)
    python_available = result.exit_code == 0 and result.stdout.strip()

    if not python_available:
        print("Python not available, skipping Python interactive test")
        print("Running shell script test instead...")

        # Shell script test
        shell_script = '''#!/bin/bash
echo "=== Shell Script Test ==="
echo "Current time: $(date)"
echo "Hostname: $(hostname)"
echo "User: $(whoami)"

# Math operations
a=10
b=20
echo "Math: $a + $b = $((a + b))"

# Array operations
arr=(1 2 3 4 5)
echo "Array: ${arr[@]}"
echo "Length: ${#arr[@]}"

# File operations
echo "Creating test file..."
echo "Hello from shell script" > /tmp/shell_test.txt
cat /tmp/shell_test.txt
rm /tmp/shell_test.txt
echo "=== Test Complete ==="
'''
        try:
            # Write and execute shell script
            result = sandbox.commands.run(
                f"cat > /tmp/test_script.sh << 'SCRIPTEOF'\n{shell_script}\nSCRIPTEOF",
                user="root",
                timeout=10
            )
            result = sandbox.commands.run("chmod +x /tmp/test_script.sh && /tmp/test_script.sh", user="root", timeout=30)

            if result.exit_code == 0:
                print(f"Output:\n{result.stdout}")
                print("PASSED")
                return True
            else:
                print(f"Exit code: {result.exit_code}")
                print(f"Stderr: {result.stderr}")
                print("FAILED")
                return False
        except Exception as e:
            print(f"ERROR: {e}")
            print("FAILED")
            return False

    # Python script test
    python_script = '''
import sys
print("Python Interpreter Test")
print(f"Version: {sys.version}")

# Interactive calculation
x = 10
y = 20
print(f"{x} + {y} = {x + y}")
print(f"{x} * {y} = {x * y}")

# List comprehension
nums = list(range(1, 6))
print(f"Numbers: {nums}")
print(f"Doubled: {[n*2 for n in nums]}")
'''

    try:
        result = sandbox.commands.run(
            f"cat > /tmp/interpreter_test.py << 'EOF'\n{python_script}\nEOF",
            user="root",
            timeout=10
        )
        result = sandbox.commands.run(
            "python3 /tmp/interpreter_test.py",
            user="root",
            timeout=30
        )

        if result.exit_code == 0:
            print(f"Output:\n{result.stdout}")
            print("PASSED")
            return True
        else:
            print(f"Exit code: {result.exit_code}")
            print(f"Stderr: {result.stderr}")
            print("FAILED")
            return False
    except Exception as e:
        print(f"ERROR: {e}")
        print("FAILED")
        return False


def main():
    print("="*60)
    print("  Code Interpreter VM Test")
    print("="*60)
    print(f"API URL: {API_URL}")
    print(f"Template: {TEMPLATE_ID}")

    # Check API health
    print("\n1. Checking API health...")
    if not check_api_health():
        print("ERROR: API is not healthy")
        return 1
    print("API is healthy")

    sandbox_id = None
    sandbox = None

    try:
        # Create sandbox
        print("\n2. Creating sandbox...")
        sandbox_id = create_sandbox()
        if not sandbox_id:
            print("ERROR: Failed to create sandbox")
            return 1

        # Wait for VM initialization
        print("\n3. Waiting for VM initialization...")
        time.sleep(5)

        # Find envd endpoint
        print("\n4. Finding envd endpoint...")
        envd_ip = find_envd_ip()
        if not envd_ip:
            print("ERROR: Could not find envd IP")
            print("Tip: Check if Firecracker VM is running and socat bridge is active")
            return 1
        print(f"Found envd at: http://{envd_ip}:49983")

        # Connect SDK
        print("\n5. Connecting E2B SDK...")
        sandbox = execute_code_via_sdk(sandbox_id, envd_ip)
        if not sandbox:
            return 1

        # Run code tests
        passed, failed = run_code_tests(sandbox)

        # Run interactive test
        interactive_passed = run_interactive_interpreter_test(sandbox)

        # Summary
        print_section("Test Summary")
        print(f"Code tests: {passed} passed, {failed} failed")
        print(f"Interactive test: {'PASSED' if interactive_passed else 'FAILED'}")

        total_passed = passed + (1 if interactive_passed else 0)
        total_tests = passed + failed + 1

        print(f"\nOverall: {total_passed}/{total_tests} tests passed")

        if total_passed == total_tests:
            print("\nCode Interpreter is working correctly!")
            return 0
        else:
            print("\nSome tests failed. Check the output above.")
            return 1

    except Exception as e:
        print(f"\nERROR: {e}")
        import traceback
        traceback.print_exc()
        return 1

    finally:
        # Cleanup
        if sandbox_id:
            print_section("Cleanup")
            delete_sandbox(sandbox_id)


if __name__ == "__main__":
    sys.exit(main())
