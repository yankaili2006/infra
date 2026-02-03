package network

import (
	"context"
	"fmt"
	"net"
	"os/exec"
	"time"

	"github.com/vishvananda/netns"
	"go.uber.org/zap"

	"github.com/e2b-dev/infra/packages/shared/pkg/logger"
)

const (
	// Guest envd service listens on this fixed address inside VM
	guestEnvdIP   = "169.254.0.21"
	guestEnvdPort = "49983"

	// Guest VNC service listens on this fixed address inside VM
	guestVNCPort = "5900"

	// Host binding port for accessing envd from outside
	// Each sandbox uses its unique slot HostIP (e.g., 10.11.0.1, 10.11.0.2, etc.)
	hostBindPort = "49983"

	// Host binding port for accessing VNC from outside
	hostVNCPort = "5900"

	// Timeout for socat process startup verification
	socatStartupTimeout = 3 * time.Second
)

// SocatBridge manages the network bridge between host and VM guest using native Go TCP proxies
// This replaces the previous implementation that relied on external socat processes
type SocatBridge struct {
	namespaceID    string
	vpeerIP        net.IP
	hostIP         net.IP    // Unique host IP for this sandbox (e.g., 10.11.0.1)
	layer1Proxy    *TCPProxy // Host TCP proxy (hostIP:49983 -> vpeerIP:49983)
	layer2Proxy    *TCPProxy // Namespace TCP proxy (vpeerIP:49983 -> 169.254.0.21:49983)
	vncLayer1Proxy *TCPProxy // Host VNC TCP proxy (hostIP:5900 -> vpeerIP:5900)
	vncLayer2Proxy *TCPProxy // Namespace VNC TCP proxy (vpeerIP:5900 -> 169.254.0.21:5900)
}

// NewSocatBridge creates a new socat bridge manager
func NewSocatBridge(namespaceID string, vpeerIP net.IP, hostIP net.IP) *SocatBridge {
	return &SocatBridge{
		namespaceID: namespaceID,
		vpeerIP:     vpeerIP,
		hostIP:      hostIP,
	}
}

// Setup establishes the dual-layer TCP proxy network tunnel
// Layer 2: Inside namespace (vpeerIP:49983 -> 169.254.0.21:49983)
// Layer 1: Host (hostIP:49983 -> vpeerIP:49983)
// Also sets up VNC port forwarding (5900)
func (sb *SocatBridge) Setup(ctx context.Context) error {
	logger.L().Info(ctx, "Setting up native Go TCP proxy network bridge",
		zap.String("namespace", sb.namespaceID),
		zap.String("vpeer_ip", sb.vpeerIP.String()),
		zap.String("host_ip", sb.hostIP.String()),
	)

	// Clean up any existing socat processes on the target port (legacy cleanup)
	if err := sb.cleanupExistingSocat(ctx); err != nil {
		logger.L().Warn(ctx, "Failed to cleanup existing socat processes", zap.Error(err))
	}

	// Layer 2: Namespace internal forwarding for envd
	if err := sb.setupLayer2(ctx); err != nil {
		return fmt.Errorf("failed to setup layer 2 TCP proxy: %w", err)
	}

	// Small delay to ensure Layer 2 is fully ready before Layer 1 connects to it
	time.Sleep(500 * time.Millisecond)

	// Layer 1: Host to namespace forwarding for envd
	if err := sb.setupLayer1(ctx); err != nil {
		// Cleanup layer 2 on failure
		sb.stopLayer2(ctx)
		return fmt.Errorf("failed to setup layer 1 TCP proxy: %w", err)
	}

	// Setup VNC port forwarding (Layer 2 then Layer 1)
	if err := sb.setupVNCLayer2(ctx); err != nil {
		logger.L().Warn(ctx, "Failed to setup VNC layer 2 proxy (VNC may not be available)", zap.Error(err))
		// Don't fail the entire setup if VNC fails - it's optional
	} else {
		time.Sleep(500 * time.Millisecond)
		if err := sb.setupVNCLayer1(ctx); err != nil {
			logger.L().Warn(ctx, "Failed to setup VNC layer 1 proxy (VNC may not be available)", zap.Error(err))
			sb.stopVNCLayer2(ctx)
			// Don't fail the entire setup if VNC fails - it's optional
		} else {
			logger.L().Info(ctx, "VNC port forwarding established",
				zap.String("vnc_url", sb.GetVNCURL()),
			)
		}
	}

	logger.L().Info(ctx, "Native Go TCP proxy network bridge established successfully",
		zap.String("access_url", fmt.Sprintf("http://%s:%s", sb.hostIP.String(), hostBindPort)),
	)

	return nil
}

// setupLayer2 creates TCP proxy inside the network namespace
// Note: This still uses exec to run a command in the namespace, but we use a simpler
// socat command with better error handling. A future optimization could use a Go-based
// namespace helper binary.
func (sb *SocatBridge) setupLayer2(ctx context.Context) error {
	bindAddr := fmt.Sprintf("%s:%s", sb.vpeerIP.String(), guestEnvdPort)
	guestAddr := fmt.Sprintf("%s:%s", guestEnvdIP, guestEnvdPort)

	logger.L().Info(ctx, "Starting Layer 2 proxy in namespace (using socat for namespace isolation)",
		zap.String("namespace", sb.namespaceID),
		zap.String("bind", bindAddr),
		zap.String("target", guestAddr),
	)

	// For Layer 2, we still use socat via ip netns exec because running Go code
	// inside a network namespace requires complex process management.
	// This is acceptable because:
	// 1. Layer 1 (the main bottleneck) is now pure Go
	// 2. Layer 2 runs in an isolated namespace anyway
	// 3. We now have better error handling

	// NOTE: We removed "-d -d" debug flags and StderrPipe to prevent SIGPIPE issues.
	// When the function returns, the stderrPipe would go out of scope and get GCed,
	// causing the pipe to close. socat with "-d -d" continuously writes to stderr,
	// and when the pipe closes, socat receives SIGPIPE and dies.
	// Without debug flags, socat doesn't write to stderr and runs indefinitely.
	cmd := exec.Command(
		"ip", "netns", "exec", sb.namespaceID,
		"socat",
		fmt.Sprintf("TCP4-LISTEN:%s,bind=%s,reuseaddr,fork", guestEnvdPort, sb.vpeerIP.String()),
		fmt.Sprintf("TCP4:%s", guestAddr),
	)

	// Redirect stdin/stdout/stderr to /dev/null to prevent pipe issues
	cmd.Stdin = nil
	cmd.Stdout = nil
	cmd.Stderr = nil

	// Start the process
	if err := cmd.Start(); err != nil {
		return fmt.Errorf("failed to start layer 2 socat in namespace: %w", err)
	}

	// Use a channel to capture early exit errors
	exitChan := make(chan error, 1)
	go func() {
		err := cmd.Wait()
		exitChan <- err
	}()

	// Wait for either socat to start listening or fail
	select {
	case err := <-exitChan:
		// socat exited early
		logger.L().Error(ctx, "Layer 2 socat exited immediately",
			zap.Error(err),
			zap.String("namespace", sb.namespaceID),
			zap.String("bind", bindAddr),
		)
		return fmt.Errorf("layer 2 socat failed: %w", err)
	case <-time.After(1 * time.Second):
		// socat is still running after 1 second - check if it's actually listening
		// Verify by checking if the process is still alive
		if cmd.Process == nil {
			return fmt.Errorf("layer 2 socat process is nil")
		}
		logger.L().Info(ctx, "Layer 2 proxy started in namespace",
			zap.Int("pid", cmd.Process.Pid),
			zap.String("bind", bindAddr),
			zap.String("target", guestAddr),
		)
	}

	// Note: We don't store the cmd because we don't manage its lifecycle
	// It will be cleaned up when the namespace is destroyed

	return nil
}

// setupLayer1 creates native Go TCP proxy on the host
// This is the main optimization - replacing external socat with pure Go code
func (sb *SocatBridge) setupLayer1(ctx context.Context) error {
	bindAddr := fmt.Sprintf("%s:%s", sb.hostIP.String(), hostBindPort)
	targetAddr := fmt.Sprintf("%s:%s", sb.vpeerIP.String(), guestEnvdPort)

	logger.L().Info(ctx, "Starting Layer 1 native Go TCP proxy on host",
		zap.String("bind", bindAddr),
		zap.String("target", targetAddr),
	)

	// Create native Go TCP proxy
	proxy := NewTCPProxy("Layer1", bindAddr, targetAddr)

	// Start the proxy (non-blocking)
	if err := proxy.Start(ctx); err != nil {
		return fmt.Errorf("failed to start layer 1 TCP proxy: %w", err)
	}

	sb.layer1Proxy = proxy

	// Verify proxy is healthy
	if !proxy.IsHealthy() {
		return fmt.Errorf("layer 1 TCP proxy health check failed")
	}

	activeConns, totalConns, _, _ := proxy.GetStats()
	logger.L().Info(ctx, "Layer 1 native Go TCP proxy started successfully",
		zap.String("bind", bindAddr),
		zap.String("target", targetAddr),
		zap.Int64("active_connections", activeConns),
		zap.Int64("total_connections", totalConns),
	)

	return nil
}

// Teardown stops all proxy processes
func (sb *SocatBridge) Teardown(ctx context.Context) error {
	logger.L().Info(ctx, "Tearing down TCP proxy network bridge",
		zap.String("namespace", sb.namespaceID),
	)

	var errs []error

	if err := sb.stopLayer1(ctx); err != nil {
		errs = append(errs, err)
	}

	if err := sb.stopLayer2(ctx); err != nil {
		errs = append(errs, err)
	}

	// Stop VNC proxies
	if err := sb.stopVNCLayer1(ctx); err != nil {
		errs = append(errs, err)
	}

	if err := sb.stopVNCLayer2(ctx); err != nil {
		errs = append(errs, err)
	}

	if len(errs) > 0 {
		return fmt.Errorf("errors during teardown: %v", errs)
	}

	return nil
}

// stopLayer1 stops the host TCP proxy
func (sb *SocatBridge) stopLayer1(ctx context.Context) error {
	if sb.layer1Proxy == nil {
		return nil
	}

	if err := sb.layer1Proxy.Stop(ctx); err != nil {
		return fmt.Errorf("failed to stop layer 1 proxy: %w", err)
	}

	logger.L().Info(ctx, "Layer 1 native Go TCP proxy stopped")
	return nil
}

// stopLayer2 stops the namespace socat process
// Note: Layer 2 still uses socat, so we just clean it up via pkill
func (sb *SocatBridge) stopLayer2(ctx context.Context) error {
	// Kill any socat process in the namespace
	// Use vpeerIP to be specific to THIS namespace's socat process
	cmd := exec.Command(
		"ip", "netns", "exec", sb.namespaceID,
		"pkill", "-f", fmt.Sprintf("socat.*bind=%s", sb.vpeerIP.String()),
	)
	_ = cmd.Run() // Ignore errors - process might already be gone

	logger.L().Info(ctx, "Layer 2 socat stopped")
	return nil
}

// cleanupExistingSocat kills any existing socat processes that might conflict
func (sb *SocatBridge) cleanupExistingSocat(ctx context.Context) error {
	// Kill host socat processes on this sandbox's host IP and port (envd)
	cmd := exec.Command("pkill", "-f", fmt.Sprintf("socat.*%s:%s", sb.hostIP.String(), hostBindPort))
	_ = cmd.Run() // Ignore errors if no processes found

	// Kill host socat processes on this sandbox's host IP and port (VNC)
	vncCmd := exec.Command("pkill", "-f", fmt.Sprintf("socat.*%s:%s", sb.hostIP.String(), hostVNCPort))
	_ = vncCmd.Run() // Ignore errors if no processes found

	// Kill namespace socat processes (envd)
	// IMPORTANT: Use vpeerIP in pattern to only match THIS namespace's socat process
	// (guestEnvdIP is the same for all namespaces, so we need to be more specific)
	nsCmd := exec.Command(
		"ip", "netns", "exec", sb.namespaceID,
		"pkill", "-f", fmt.Sprintf("socat.*bind=%s.*%s:%s", sb.vpeerIP.String(), guestEnvdIP, guestEnvdPort),
	)
	_ = nsCmd.Run() // Ignore errors if no processes found

	// Kill namespace socat processes (VNC)
	nsVNCCmd := exec.Command(
		"ip", "netns", "exec", sb.namespaceID,
		"pkill", "-f", fmt.Sprintf("socat.*bind=%s.*%s:%s", sb.vpeerIP.String(), guestEnvdIP, guestVNCPort),
	)
	_ = nsVNCCmd.Run() // Ignore errors if no processes found

	time.Sleep(500 * time.Millisecond) // Brief pause to let processes fully terminate

	return nil
}

// GetAccessURL returns the URL to access the VM's envd service
func (sb *SocatBridge) GetAccessURL() string {
	return fmt.Sprintf("http://%s:%s", sb.hostIP.String(), hostBindPort)
}

// GetVNCURL returns the URL to access the VM's VNC service
func (sb *SocatBridge) GetVNCURL() string {
	return fmt.Sprintf("vnc://%s:%s", sb.hostIP.String(), hostVNCPort)
}

// setupVNCLayer2 creates VNC TCP proxy inside the network namespace
func (sb *SocatBridge) setupVNCLayer2(ctx context.Context) error {
	bindAddr := fmt.Sprintf("%s:%s", sb.vpeerIP.String(), guestVNCPort)
	guestAddr := fmt.Sprintf("%s:%s", guestEnvdIP, guestVNCPort)

	logger.L().Info(ctx, "Starting VNC Layer 2 proxy in namespace (using socat for namespace isolation)",
		zap.String("namespace", sb.namespaceID),
		zap.String("bind", bindAddr),
		zap.String("target", guestAddr),
	)

	cmd := exec.Command(
		"ip", "netns", "exec", sb.namespaceID,
		"socat",
		fmt.Sprintf("TCP4-LISTEN:%s,bind=%s,reuseaddr,fork", guestVNCPort, sb.vpeerIP.String()),
		fmt.Sprintf("TCP4:%s", guestAddr),
	)

	cmd.Stdin = nil
	cmd.Stdout = nil
	cmd.Stderr = nil

	if err := cmd.Start(); err != nil {
		return fmt.Errorf("failed to start VNC layer 2 socat in namespace: %w", err)
	}

	exitChan := make(chan error, 1)
	go func() {
		err := cmd.Wait()
		exitChan <- err
	}()

	select {
	case err := <-exitChan:
		logger.L().Error(ctx, "VNC Layer 2 socat exited immediately",
			zap.Error(err),
			zap.String("namespace", sb.namespaceID),
			zap.String("bind", bindAddr),
		)
		return fmt.Errorf("VNC layer 2 socat failed: %w", err)
	case <-time.After(1 * time.Second):
		if cmd.Process == nil {
			return fmt.Errorf("VNC layer 2 socat process is nil")
		}
		logger.L().Info(ctx, "VNC Layer 2 proxy started in namespace",
			zap.Int("pid", cmd.Process.Pid),
			zap.String("bind", bindAddr),
			zap.String("target", guestAddr),
		)
	}

	return nil
}

// setupVNCLayer1 creates native Go VNC TCP proxy on the host
func (sb *SocatBridge) setupVNCLayer1(ctx context.Context) error {
	bindAddr := fmt.Sprintf("%s:%s", sb.hostIP.String(), hostVNCPort)
	targetAddr := fmt.Sprintf("%s:%s", sb.vpeerIP.String(), guestVNCPort)

	logger.L().Info(ctx, "Starting VNC Layer 1 native Go TCP proxy on host",
		zap.String("bind", bindAddr),
		zap.String("target", targetAddr),
	)

	proxy := NewTCPProxy("VNCLayer1", bindAddr, targetAddr)

	if err := proxy.Start(ctx); err != nil {
		return fmt.Errorf("failed to start VNC layer 1 TCP proxy: %w", err)
	}

	sb.vncLayer1Proxy = proxy

	if !proxy.IsHealthy() {
		return fmt.Errorf("VNC layer 1 TCP proxy health check failed")
	}

	activeConns, totalConns, _, _ := proxy.GetStats()
	logger.L().Info(ctx, "VNC Layer 1 native Go TCP proxy started successfully",
		zap.String("bind", bindAddr),
		zap.String("target", targetAddr),
		zap.Int64("active_connections", activeConns),
		zap.Int64("total_connections", totalConns),
	)

	return nil
}

// stopVNCLayer1 stops the host VNC TCP proxy
func (sb *SocatBridge) stopVNCLayer1(ctx context.Context) error {
	if sb.vncLayer1Proxy == nil {
		return nil
	}

	if err := sb.vncLayer1Proxy.Stop(ctx); err != nil {
		return fmt.Errorf("failed to stop VNC layer 1 proxy: %w", err)
	}

	logger.L().Info(ctx, "VNC Layer 1 native Go TCP proxy stopped")
	return nil
}

// stopVNCLayer2 stops the namespace VNC socat process
func (sb *SocatBridge) stopVNCLayer2(ctx context.Context) error {
	cmd := exec.Command(
		"ip", "netns", "exec", sb.namespaceID,
		"pkill", "-f", fmt.Sprintf("socat.*bind=%s.*%s", sb.vpeerIP.String(), guestVNCPort),
	)
	_ = cmd.Run() // Ignore errors - process might already be gone

	logger.L().Info(ctx, "VNC Layer 2 socat stopped")
	return nil
}

// Helper function to check if we're in a network namespace
func isInNetworkNamespace(nsName string) (bool, error) {
	currentNS, err := netns.Get()
	if err != nil {
		return false, err
	}
	defer currentNS.Close()

	targetNS, err := netns.GetFromName(nsName)
	if err != nil {
		return false, err
	}
	defer targetNS.Close()

	return currentNS.Equal(targetNS), nil
}
