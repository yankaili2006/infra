# Node Discovery Bug Fix - January 2026

## 🎯 Quick Reference

**Issue**: "Failed to place sandbox" - nodes discovered but immediately closed
**Status**: ✅ RESOLVED
**Date**: January 11, 2026
**Severity**: Critical (blocked all VM creation)

## 📋 Summary

Two critical bugs in API's node discovery mechanism prevented VM creation in local development mode:

1. **Hardcoded Node ID** - Used `"local-node-001"` instead of actual Nomad node ID
2. **Go Slice Pass-by-Value** - Modifications to slice didn't persist to parent function

## 🔧 Quick Fix

**File**: `/home/primihub/pcloud/infra/packages/api/internal/orchestrator/cache.go`

### Change 1: Line 76
```go
// BEFORE
o.syncLocalDiscoveredNodes(spanCtx, nomadNodes)

// AFTER
o.syncLocalDiscoveredNodes(spanCtx, &nomadNodes)
```

### Change 2: Line 119 - Function Signature
```go
// BEFORE
func (o *Orchestrator) syncLocalDiscoveredNodes(ctx context.Context, discovered []nodemanager.NomadServiceDiscovery)

// AFTER
func (o *Orchestrator) syncLocalDiscoveredNodes(ctx context.Context, discovered *[]nodemanager.NomadServiceDiscovery)
```

### Change 3: Lines 129-148 - Use Pointer and Real Node ID
```go
// BEFORE
if len(discovered) == 0 {
    orchestratorURL := os.Getenv("ORCHESTRATOR_URL")
    if orchestratorURL != "" {
        discovered = append(discovered, nodemanager.NomadServiceDiscovery{
            NomadNodeShortID:    "local-node-001",  // ❌ Hardcoded
            OrchestratorAddress: orchestratorURL,
            IPAddress:           "127.0.0.1",
        })
    }
}

for _, n := range discovered {
    // ...
}

// AFTER
if len(*discovered) == 0 {
    orchestratorURL := os.Getenv("ORCHESTRATOR_URL")
    if orchestratorURL != "" {
        // Get real node ID
        nodeID := os.Getenv("NODE_ID")
        nodeShortID := "local-node-001" // Fallback
        if nodeID != "" && len(nodeID) >= 8 {
            nodeShortID = nodeID[:8]  // ✅ Extract short ID
        }
        logger.L().Info(ctx, "No nodes discovered via Nomad, manually adding local orchestrator",
            zap.String("url", orchestratorURL),
            zap.String("node_short_id", nodeShortID))
        *discovered = append(*discovered, nodemanager.NomadServiceDiscovery{
            NomadNodeShortID:    nodeShortID,  // ✅ Real ID
            OrchestratorAddress: orchestratorURL,
            IPAddress:           "127.0.0.1",
        })
    }
}

for _, n := range *discovered {
    // ...
}
```

## 🚀 Apply Fix

```bash
# 1. Navigate to API package
cd /home/primihub/pcloud/infra/packages/api

# 2. Rebuild
go build -o bin/api ./main.go

# 3. Restart service
nomad job stop api && sleep 3
nomad job run /home/primihub/pcloud/infra/local-deploy/jobs/api.hcl

# 4. Wait for sync
sleep 30

# 5. Test
curl -X POST http://localhost:3000/sandboxes \
  -H "Content-Type: application/json" \
  -H "X-API-Key: e2b_53ae1fed82754c17ad8077fbc8bcdd90" \
  -d '{"templateID": "base", "timeout": 300}'

# Expected: HTTP 201 with sandbox ID
```

## 🔍 Verify Fix

```bash
# Check API is healthy
curl http://localhost:3000/health
# Expected: "Health check successful"

# Check Firecracker VM running
ps aux | grep firecracker | grep -v grep
# Expected: See firecracker process

# Use diagnostic script
python3 /home/primihub/pcloud/diagnose_vm_creation.py
# Expected: HTTP_CODE:201, sandbox ID returned
```

## 📚 Root Cause - Go Slice Mechanics

**Problem**: In Go, slices are structs `{ptr *array, len int, cap int}`

When passing by value:
- Function receives a **copy** of the slice struct
- `append()` may allocate new array and **always returns new struct**
- Modifications only affect the local copy
- Parent function's slice remains unchanged

**Solution**: Pass pointer `*[]T` so modifications affect original slice struct

## 🎓 Key Takeaways

1. **Always use `*[]T` for functions that modify slices**
2. **Never hardcode node IDs** - read from environment/API
3. **Test local development mode explicitly** - different code paths
4. **Log actual vs expected IDs** - helps diagnose mismatches

## 📖 Full Documentation

See `/home/primihub/pcloud/infra/CLAUDE.md` section "Critical Issue: Node Discovery Failure" for complete analysis.

---

**Resolution Date**: January 11, 2026
**Fixed By**: Claude Sonnet 4.5
**Verified**: VM creation working ✅
