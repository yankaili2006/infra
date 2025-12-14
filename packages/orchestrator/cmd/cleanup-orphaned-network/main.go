package main

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"regexp"
	"strings"

	"go.uber.org/zap"

	"github.com/e2b-dev/infra/packages/shared/pkg/logger"
)

// Cleanup orphaned network namespaces created by the orchestrator
// These can accumulate if the orchestrator is killed before async cleanup completes
func main() {
	ctx := context.Background()

	logger.L().Info(ctx, "Starting orphaned network namespace cleanup")

	// Get list of all network namespaces matching pattern ns-*
	cmd := exec.Command("ip", "netns", "list")
	output, err := cmd.Output()
	if err != nil {
		logger.L().Error(ctx, "Failed to list network namespaces", zap.Error(err))
		os.Exit(1)
	}

	// Parse namespaces
	nsPattern := regexp.MustCompile(`^ns-\d+`)
	lines := strings.Split(string(output), "\n")
	var namespaces []string

	for _, line := range lines {
		line = strings.TrimSpace(line)
		if nsPattern.MatchString(line) {
			// Extract just the namespace name (first field)
			fields := strings.Fields(line)
			if len(fields) > 0 {
				namespaces = append(namespaces, fields[0])
			}
		}
	}

	if len(namespaces) == 0 {
		logger.L().Info(ctx, "No orphaned namespaces found")
		return
	}

	logger.L().Info(ctx, "Found orphaned namespaces", zap.Int("count", len(namespaces)))

	// Get list of currently running firecracker processes to avoid cleaning active namespaces
	// In a production system, you might want to check against a registry of active sandboxes
	fcCmd := exec.Command("pgrep", "-f", "firecracker")
	fcOutput, _ := fcCmd.Output() // Ignore error as pgrep returns non-zero if no processes found

	activeProcesses := len(strings.Split(strings.TrimSpace(string(fcOutput)), "\n"))
	if activeProcesses > 0 && string(fcOutput) != "" {
		logger.L().Warn(ctx, "Active firecracker processes detected, some namespaces may be in use",
			zap.Int("active_processes", activeProcesses))
	}

	// Clean up namespaces
	cleaned := 0
	failed := 0

	for i, ns := range namespaces {
		// Unmount the namespace first
		umountCmd := exec.Command("umount", fmt.Sprintf("/run/netns/%s", ns))
		_ = umountCmd.Run() // Ignore errors

		// Delete the namespace file
		removeCmd := exec.Command("rm", "-f", fmt.Sprintf("/run/netns/%s", ns))
		err := removeCmd.Run()
		if err != nil {
			logger.L().Error(ctx, "Failed to remove namespace",
				zap.String("namespace", ns),
				zap.Error(err))
			failed++
		} else {
			cleaned++
		}

		// Log progress every 1000 namespaces
		if (i+1)%1000 == 0 {
			logger.L().Info(ctx, "Cleanup progress",
				zap.Int("processed", i+1),
				zap.Int("total", len(namespaces)))
		}
	}

	// Clean up orphaned veth devices
	vethCmd := exec.Command("sh", "-c", "ip link show | grep -o '^[0-9]*: veth[^@:]*' | awk '{print $2}'")
	vethOutput, err := vethCmd.Output()
	if err == nil && len(vethOutput) > 0 {
		veths := strings.Split(strings.TrimSpace(string(vethOutput)), "\n")
		for _, veth := range veths {
			if veth == "" {
				continue
			}
			delCmd := exec.Command("ip", "link", "delete", veth)
			_ = delCmd.Run() // Ignore errors
		}
		logger.L().Info(ctx, "Cleaned up orphaned veth devices", zap.Int("count", len(veths)))
	}

	logger.L().Info(ctx, "Cleanup complete",
		zap.Int("cleaned", cleaned),
		zap.Int("failed", failed))

	if failed > 0 {
		os.Exit(1)
	}
}
