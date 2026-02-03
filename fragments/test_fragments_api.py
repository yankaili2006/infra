#!/usr/bin/env python3
"""
Test Fragments Preview Functionality via API
"""
import requests
import json
import time

BASE_URL = "http://localhost:3001"

def test_fragments_preview():
    print("=== Testing Fragments Preview Functionality ===\n")
    
    # Step 1: Create a simple Python code fragment
    print("1. Creating a Python code fragment...")
    create_payload = {
        "code": "print('Hello from Fragments!')\nfor i in range(5):\n    print(f'Count: {i}')",
        "language": "python"
    }
    
    try:
        response = requests.post(
            f"{BASE_URL}/api/fragments",
            json=create_payload,
            headers={"Content-Type": "application/json"}
        )
        
        if response.status_code == 200 or response.status_code == 201:
            fragment_data = response.json()
            fragment_id = fragment_data.get('id')
            print(f"✓ Fragment created successfully!")
            print(f"  Fragment ID: {fragment_id}")
            print(f"  Response: {json.dumps(fragment_data, indent=2)}\n")
            
            # Step 2: Get fragment details
            print("2. Fetching fragment details...")
            get_response = requests.get(f"{BASE_URL}/api/fragments/{fragment_id}")
            if get_response.status_code == 200:
                print(f"✓ Fragment details retrieved!")
                print(f"  {json.dumps(get_response.json(), indent=2)}\n")
            
            # Step 3: Test preview endpoint
            print("3. Testing preview functionality...")
            preview_response = requests.get(f"{BASE_URL}/api/fragments/{fragment_id}/preview")
            if preview_response.status_code == 200:
                print(f"✓ Preview generated successfully!")
                print(f"  Preview data: {preview_response.text[:200]}...\n")
            else:
                print(f"✗ Preview failed: {preview_response.status_code}")
                print(f"  {preview_response.text}\n")
            
            # Step 4: Test execution
            print("4. Testing code execution...")
            exec_response = requests.post(f"{BASE_URL}/api/fragments/{fragment_id}/execute")
            if exec_response.status_code == 200:
                exec_data = exec_response.json()
                print(f"✓ Code executed successfully!")
                print(f"  Output: {exec_data.get('output', 'No output')}\n")
            else:
                print(f"✗ Execution failed: {exec_response.status_code}")
                print(f"  {exec_response.text}\n")
                
        else:
            print(f"✗ Failed to create fragment: {response.status_code}")
            print(f"  Response: {response.text}\n")
            
    except requests.exceptions.ConnectionError:
        print("✗ Cannot connect to Fragments service at", BASE_URL)
        print("  Please ensure the service is running.\n")
    except Exception as e:
        print(f"✗ Error: {str(e)}\n")

if __name__ == "__main__":
    test_fragments_preview()
