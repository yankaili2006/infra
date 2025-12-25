# E2B Network Diagnosis Report
**Generated:** 2025-12-24 02:32 UTC
**Status:** Network connectivity issue identified

## 🎯 Executive Summary

E2B infrastructure services (API, Orchestrator) are running correctly. Firecracker microVMs start successfully, but **network connectivity between the host and guest VMs is broken**, preventing envd daemon communication.

## ✅ Successfully Completed

### 1. Code Improvements
- **KernelLogs enabled** in `sandbox.go:555` (set to `true`)
- **Go 1.22 compatibility fix** in `buildlogger/log_entry_logger.go`
  - Changed `bytes.SplitSeq()` (Go 1.23) to `bytes.Split()` (Go 1.22)
- **Orchestrator recompiled** with Go 1.25.4 (96MB binary created)

### 2. Service Health
```
✅ API Service:          http://localhost:3000/health - Healthy
✅ Orchestrator Service: http://localhost:5008/health - Healthy
✅ PostgreSQL Database:  Running
✅ Nomad Scheduler:      Running (orchestrator job active)
```

### 3. VM Discovery
Found 2 running Firecracker processes:
```bash
PID: 3916206 - Socket: /tmp/fc-ix7hj8hustuvlxiqc0g0u-5v46qx8woej5mafpjhog.sock
PID: 3943930 - Socket: /tmp/fc-i2fewa6azuz8dedm8btll-uur67n8z1artmx5wym8s.sock
```

## ❌ Critical Issue: Network Connectivity

### Error Signature
```
failed to create sandbox: failed to wait for sandbox start:
failed to init new envd: failed to init envd:
context deadline exceeded with cause: request timed out (60s)
```

### Root Cause Analysis

**Symptom:** orchestrator cannot connect to envd (port 49983) inside VM

**Expected Flow:**
```
1. Firecracker creates VM with tap network interface
2. tap interface bridges to host network
3. VM boots with IP on 169.254.0.x network
4. envd starts on port 49983 inside VM
5. Orchestrator connects to VM_IP:49983 from host
```

**Actual Flow:**
```
1. Firecracker creates VM ✅
2. tap interface NOT created ❌
3. VM boots but has no network ⚠️
4. envd cannot be reached 🔴
5. Orchestrator times out after 60s 💥
```

### Network Interface Status

**Expected:**
- tap0, tap1, tap2... (one per VM)
- Configured with 169.254.0.x/16 network
- State: UP

**Actual:**
- No tap interfaces found
- Only veth* (Docker) and br-* (bridges) present
- Network namespace isolation issue suspected

### Technical Details

**Missing Components:**
1. TAP device creation in Firecracker launch
2. Network routing rules (iptables/nftables)
3. IP assignment to VM guest interface

**Potential Causes:**
1. `/dev/net/tun` permissions issue
2. Orchestrator running without network capabilities
3. Network namespace configuration错误
4. Firecracker network config not applied

## 🔍 Diagnostic Commands Run

```bash
# Service health checks
curl http://localhost:3000/health  # ✅ OK
curl http://localhost:5008/health  # ✅ OK

# Process discovery
ps aux | grep firecracker          # ✅ Found 2 VMs

# Network interface check
ip link show | grep tap            # ❌ None found
ip addr show | grep "169.254"      # ❌ No VM network

# Orchestrator logs
nomad alloc logs e2f9ef00          # Shows timeout error
```

## 🔧 Recommended Fix (Priority Order)

### Option 1: Check /dev/net/tun Permissions
```bash
# Verify TUN/TAP device exists
ls -la /dev/net/tun

# Expected output:
# crw-rw-rw- 1 root root 10, 200 /dev/net/tun

# Fix if needed:
sudo chmod 666 /dev/net/tun
```

### Option 2: Verify Orchestrator Capabilities
```bash
# Check if orchestrator has NET_ADMIN capability
getcap /home/primihub/pcloud/infra/packages/orchestrator/bin/orchestrator

# If missing, add:
sudo setcap cap_net_admin+ep bin/orchestrator
```

### Option 3: Review Firecracker Network Config
```bash
# Check Firecracker API socket configuration
sudo ls -la /tmp/fc-*.sock

# Read VM configuration
sudo cat /tmp/fc-ix7hj8hustuvlxiqc0g0u-5v46qx8woej5mafpjhog.sock
```

### Option 4: Enable Kernel Logging to See Boot Messages
Even though KernelLogs is enabled in code, we need to verify it's working:
```bash
# Create new VM and capture kernel output
# This will show if VM network interface is configured

# Expected kernel messages:
# [    0.123] virtio_net virtio1: detected
# [    0.456] eth0: assigned IP 169.254.0.21
```

### Option 5: Manual Network Setup
If automatic networking fails, set up manually:
```bash
# Create tap interface
sudo ip tuntap add dev tap0 mode tap

# Bring it up
sudo ip link set tap0 up

# Assign host-side IP
sudo ip addr add 169.254.1.1/16 dev tap0

# Enable IP forwarding
sudo sysctl -w net.ipv4.ip_forward=1

# Setup NAT (if needed for internet access)
sudo iptables -t nat -A POSTROUTING -o eno1 -j MASQUERADE
sudo iptables -A FORWARD -i tap0 -j ACCEPT
```

## 📋 Next Steps

1. **Immediate Action:** Check `/dev/net/tun` permissions
2. **Short Term:** Review orchestrator network configuration code in `sandbox/network/`
3. **Medium Term:** Implement network setup verification in pre-flight checks
4. **Long Term:** Add automated network health monitoring

## 📚 Related Documentation

- Firecracker Network Setup: `/home/primihub/pcloud/infra/CLAUDE.md`
- Orchestrator Network Code: `/home/primihub/pcloud/infra/packages/orchestrator/internal/sandbox/network/`
- E2B VM Creation Guide: `/home/primihub/pcloud/infra/TROUBLESHOOTING.md`

## 🎓 Key Learnings

1. ⭐ **KernelLogs must be true** - Without it, VM boot failures are invisible
2. ⭐ **Network is separate from VM boot** - Firecracker can start but network can fail independently
3. ⭐ **60s timeout is too long** - Should fail faster or provide incremental feedback
4. ⭐ **envd connection ≠ VM health** - VM may be running fine but unreachable

---

**Status:** Ready for network configuration debugging
**Blocker:** TAP network interface creation
**Owner:** Infrastructure team
