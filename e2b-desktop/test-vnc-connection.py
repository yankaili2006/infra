#!/usr/bin/env python3
"""Test VNC connection to desktop sandbox"""

import grpc
from e2b.sandbox.sandbox_api_pb2 import SandboxCreateRequest
from e2b.sandbox.sandbox_api_pb2_grpc import SandboxServiceStub

def test_desktop_sandbox():
    channel = grpc.insecure_channel('localhost:50051')
    stub = SandboxServiceStub(channel)

    request = SandboxCreateRequest(
        template_id="desktop-template-000-0000-0000-000000000001"
    )

    print("Creating desktop sandbox...")
    response = stub.Create(request)

    print(f"\n✅ Sandbox created successfully!")
    print(f"Sandbox ID: {response.sandbox_id}")
    print(f"VNC URL: vnc://{response.host}:5900")
    print(f"Access URL: http://{response.host}:49983")
    print(f"\nConnect with: vncviewer {response.host}:5900")

    return response

if __name__ == "__main__":
    test_desktop_sandbox()
