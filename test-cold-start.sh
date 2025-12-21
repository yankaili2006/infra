#!/bin/bash
# E2B VM Cold Start Test Script

set -e

BUILD_ID="9ac9c8b9-9b8b-476c-9238-8266af308c32"
TEMPLATE_ID="base"
KERNEL_VERSION="vmlinux-5.10.223"
FC_VERSION="v1.12.1_d990331"

echo "=== E2B VM Cold Start Test ==="
echo "Build ID: $BUILD_ID"
echo "Template ID: $TEMPLATE_ID"
echo ""

# Test using API (which should trigger cold start if snapshot not available)
echo "Testing via API..."
curl -X POST http://localhost:3000/sandboxes \
  -H "Content-Type: application/json" \
  -H "X-API-Key: e2b_53ae1fed82754c17ad8077fbc8bcdd90" \
  -d "{
    \"templateID\": \"base-template-000-0000-0000-000000000001\",
    \"timeout\": 300
  }"

echo ""
echo ""
echo "=== Checking for running Firecracker VMs (wait 5s) ==="
sleep 5
ps aux | grep firecracker | grep -v grep || echo "No Firecracker VMs running"

echo ""
echo "=== Checking orchestrator logs ==="
ALLOC_ID=$(nomad job allocs orchestrator | grep running | awk '{print $1}' | head -1)
nomad alloc logs $ALLOC_ID 2>&1 | tail -50
