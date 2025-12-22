#!/bin/sh
exec > /dev/ttyS0 2>&1

echo "========================================="
echo "=== E2B Guest Network Diagnostic ===" 
echo "========================================="

echo "--- [1] Kernel Command Line ---"
cat /proc/cmdline  
echo

echo "--- [2] Network Interfaces ---"
ip addr show
echo

echo "--- [3] Activating eth0 ---"
ip link set lo up
ip link set eth0 up
sleep 2
echo

echo "--- [4] Post-Activation Network ---"
ip addr show
echo

echo "--- [5] Routing Table ---"
ip route
echo

echo "--- [6] Testing Gateway ---"
ping -c 3 169.254.0.22 || echo "FAILED"
echo

echo "--- [7] Sleep Loop ---"
while true; do sleep 60; done
