#!/bin/bash
# Fix Orchestrator Sudo Environment Preservation Issue
# Date: 2026-02-04
# Issue: Orchestrator fails to start with "sudo: sorry, you are not allowed to preserve the environment"
# Solution: Remove -E flag from sudo command in orchestrator.hcl
#
# This script is idempotent - safe to run multiple times

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HCL_FILE="$SCRIPT_DIR/../jobs/orchestrator.hcl"

echo "=== Orchestrator Sudo Fix Script ==="
echo "Date: $(date)"
echo "Version: 1.1 (Idempotent)"
echo ""

# Step 1: Check if fix is already applied
echo "Step 1: Checking if fix is already applied..."
if ! grep -q 'args.*=.*\["-E"' "$HCL_FILE"; then
    echo "✓ Fix already applied - no -E flag found in HCL file"
    echo ""
    echo "Current configuration:"
    grep -A 1 'command = "sudo"' "$HCL_FILE" | grep 'args'
    echo ""

    # Check if orchestrator is running
    if nomad job status orchestrator 2>/dev/null | grep -q "Status.*running"; then
        echo "✓ Orchestrator is running normally"
        echo ""
        echo "System is healthy. No action needed."
        exit 0
    else
        echo "⚠ Orchestrator is not running, but fix is already applied"
        echo "This may be a different issue. Check logs:"
        echo "  nomad job status orchestrator"
        ALLOC_ID=$(nomad job allocs orchestrator 2>/dev/null | grep -v "ID" | head -1 | awk '{print $1}')
        if [ -n "$ALLOC_ID" ]; then
            echo "  nomad alloc logs $ALLOC_ID orchestrator 2>&1"
        fi
        exit 1
    fi
fi

echo "⚠ -E flag found - fix needs to be applied"

# Step 2: Check orchestrator status
echo ""
echo "Step 2: Checking orchestrator status..."
if nomad job status orchestrator 2>/dev/null | grep -q "Status.*running"; then
    echo "✓ Orchestrator is currently running"
    echo "⚠ Applying fix will restart the service"
    read -p "Continue? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Exiting without changes"
        exit 0
    fi
else
    echo "⚠ Orchestrator is not running or has issues"
    echo "Applying fix to resolve the issue..."
fi

# Step 3: Backup HCL file (only if not already backed up recently)
echo ""
echo "Step 3: Creating backup of orchestrator.hcl..."
BACKUP_FILE="${HCL_FILE}.backup.$(date +%Y%m%d_%H%M%S)"

# Check if a recent backup exists (within last hour)
RECENT_BACKUP=$(find "$(dirname "$HCL_FILE")" -name "orchestrator.hcl.backup.*" -mmin -60 2>/dev/null | head -1)
if [ -n "$RECENT_BACKUP" ]; then
    echo "ℹ Recent backup found: $RECENT_BACKUP"
    echo "  Skipping new backup to avoid clutter"
    BACKUP_FILE="$RECENT_BACKUP"
else
    cp "$HCL_FILE" "$BACKUP_FILE"
    echo "✓ Backup created: $BACKUP_FILE"
fi

# Step 4: Remove -E flag
echo ""
echo "Step 4: Removing -E flag from sudo command..."
# Replace: args = ["-E", "/path/to/script"]
# With:    args = ["/path/to/script"]
# Use a more robust sed pattern that handles various whitespace
sed -i.tmp 's/args[[:space:]]*=[[:space:]]*\["-E",[[:space:]]*/args    = [/' "$HCL_FILE"
rm -f "${HCL_FILE}.tmp"
echo "✓ Removed -E flag from HCL file"

# Step 5: Verify the change
echo ""
echo "Step 5: Verifying the change..."
echo "New args line:"
grep -A 1 'command = "sudo"' "$HCL_FILE" | grep 'args'

# Double-check that -E is really gone
if grep -q 'args.*=.*\["-E"' "$HCL_FILE"; then
    echo "✗ ERROR: -E flag still present after modification"
    echo "  Manual intervention required"
    exit 1
fi
echo "✓ Verification passed - no -E flag found"

# Step 6: Restart orchestrator service
echo ""
echo "Step 6: Restarting orchestrator service..."

# Stop the service gracefully
echo "  Stopping orchestrator..."
nomad job stop orchestrator 2>/dev/null || echo "  (Service was not running)"

# Wait a bit for cleanup
sleep 3

# Start the service with updated configuration
echo "  Starting orchestrator with fixed configuration..."
nomad job run "$HCL_FILE"
echo "✓ Orchestrator job restarted"

# Step 7: Wait for service to start
echo ""
echo "Step 7: Waiting for orchestrator to start (15 seconds)..."
sleep 15

# Step 8: Check service status
echo ""
echo "Step 8: Checking orchestrator status..."
if nomad job status orchestrator 2>/dev/null | grep -q "Status.*running"; then
    echo "✓ Orchestrator is running"

    # Get the latest allocation ID
    ALLOC_ID=$(nomad job allocs orchestrator 2>/dev/null | grep running | head -1 | awk '{print $1}')

    if [ -n "$ALLOC_ID" ]; then
        echo ""
        echo "Step 9: Checking logs for errors..."
        echo "Allocation ID: $ALLOC_ID"

        # Wait a bit more for logs to accumulate
        sleep 5

        # Check for sudo errors in logs
        if nomad alloc logs "$ALLOC_ID" orchestrator 2>&1 | grep -q "sudo.*not allowed\|sudo.*environment"; then
            echo "✗ Still seeing sudo errors in logs"
            echo "Please check logs manually: nomad alloc logs $ALLOC_ID orchestrator 2>&1"
            exit 1
        else
            echo "✓ No sudo errors found in logs"
        fi

        # Show last few log lines
        echo ""
        echo "Recent log entries (last 10 lines):"
        nomad alloc logs "$ALLOC_ID" orchestrator 2>&1 | tail -10
    fi
else
    echo "✗ Orchestrator is not running"
    echo ""
    echo "Troubleshooting steps:"
    echo "  1. Check job status: nomad job status orchestrator"
    echo "  2. Check recent allocations: nomad job allocs orchestrator"
    ALLOC_ID=$(nomad job allocs orchestrator 2>/dev/null | grep -v "ID" | head -1 | awk '{print $1}')
    if [ -n "$ALLOC_ID" ]; then
        echo "  3. Check logs: nomad alloc logs $ALLOC_ID orchestrator 2>&1"
    fi
    exit 1
fi

echo ""
echo "=== Fix completed successfully! ==="
echo ""
echo "Summary:"
echo "  - Backup file: $BACKUP_FILE"
echo "  - Modified file: $HCL_FILE"
echo "  - Orchestrator status: Running"
echo "  - Sudo errors: None detected"
echo ""
echo "To verify Fragments preview works:"
echo "  curl -X POST http://localhost:3001/api/sandbox \\"
echo "    -H 'Content-Type: application/json' \\"
echo "    -d '{\"fragment\":{\"template\":\"code-interpreter-v1\",\"code\":\"print(\\\"Hello World\\\")\"}}'"
echo ""
echo "Note: This script is idempotent and safe to run multiple times."
