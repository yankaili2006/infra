#!/usr/bin/env python3
"""
Direct test of Fragments /api/sandbox endpoint
"""
import requests
import json

BASE_URL = "http://localhost:3001"

print("=== Testing Fragments Sandbox API ===\n")

# Test 1: Simple Python code execution
print("Test 1: Python Code Execution")
print("-" * 50)

payload = {
    "fragment": {
        "template": "code-interpreter-v1",
        "code": "print('Hello from Fragments!')\nprint('Testing preview functionality')\nfor i in range(3):\n    print(f'Count: {i}')"
    },
    "userID": "test-user",
    "teamID": "test-team"
}

try:
    response = requests.post(
        f"{BASE_URL}/api/sandbox",
        json=payload,
        headers={"Content-Type": "application/json"},
        timeout=60
    )
    
    print(f"Status Code: {response.status_code}")
    
    if response.status_code == 200:
        result = response.json()
        print(f"✓ Success!")
        print(f"\nSandbox ID: {result.get('sbxId')}")
        print(f"Template: {result.get('template')}")
        
        if result.get('stdout'):
            print(f"\nStdout:")
            for line in result['stdout']:
                print(f"  {line}")
        
        if result.get('stderr'):
            print(f"\nStderr:")
            for line in result['stderr']:
                print(f"  {line}")
                
        if result.get('url'):
            print(f"\nPreview URL: {result['url']}")
    else:
        print(f"✗ Failed")
        print(f"Response: {response.text[:500]}")
        
except Exception as e:
    print(f"✗ Error: {str(e)}")

print("\n" + "=" * 50 + "\n")

# Test 2: Simple HTML page (web template)
print("Test 2: Simple HTML Page (Next.js)")
print("-" * 50)

payload2 = {
    "fragment": {
        "template": "nextjs-developer-dev",
        "code": [{
            "file_path": "/root/pages/index.tsx",
            "file_content": """export default function Home() {
  return (
    <div style={{ padding: '50px', textAlign: 'center', backgroundColor: '#f0f0f0' }}>
      <h1 style={{ color: '#333' }}>Hello from Fragments!</h1>
      <p>This is a simple test page</p>
      <button style={{ padding: '10px 20px', fontSize: '16px', backgroundColor: '#0070f3', color: 'white', border: 'none', borderRadius: '5px', cursor: 'pointer' }}>
        Click Me
      </button>
    </div>
  )
}"""
        }]
    },
    "userID": "test-user",
    "teamID": "test-team"
}

try:
    print("Creating Next.js sandbox (this may take 30-60 seconds)...")
    response = requests.post(
        f"{BASE_URL}/api/sandbox",
        json=payload2,
        headers={"Content-Type": "application/json"},
        timeout=120
    )
    
    print(f"Status Code: {response.status_code}")
    
    if response.status_code == 200:
        result = response.json()
        print(f"✓ Success!")
        print(f"\nSandbox ID: {result.get('sbxId')}")
        print(f"Template: {result.get('template')}")
        print(f"Preview URL: {result.get('url')}")
        print(f"\n🌐 Open this URL in your browser to see the preview!")
    else:
        print(f"✗ Failed")
        print(f"Response: {response.text[:500]}")
        
except Exception as e:
    print(f"✗ Error: {str(e)}")

print("\n" + "=" * 50)
print("✅ Testing complete!")
