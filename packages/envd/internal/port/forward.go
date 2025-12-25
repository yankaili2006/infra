// portf (port forward) periodaically scans opened TCP ports on the 127.0.0.1 (or localhost)
// and launches `socat` process for every such port in the background.
// socat forward traffic from `sourceIP`:port to the 127.0.0.1:port.

// WARNING: portf isn't thread safe!

package port

import (
	"context"
	"fmt"
	"net"
	"os"
	"os/exec"
	"syscall"

	"github.com/rs/zerolog"

	"github.com/e2b-dev/infra/packages/envd/internal/services/cgroups"
)

type PortState string

const (
	PortStateForward PortState = "FORWARD"
	PortStateDelete  PortState = "DELETE"
)

// REVERT: Changed back to .21 (guest side) - 2025-12-25
// envd runs INSIDE the guest VM, so socat must bind to the guest's own IP (169.254.0.21)
// NOT to the host side of tap0 (169.254.0.22) which is not accessible from inside the guest
var defaultGatewayIP = net.IPv4(169, 254, 0, 21)

type PortToForward struct {
	socat *exec.Cmd
	// Process ID of the process that's listening on port.
	pid int32
	// family version of the ip.
	family uint32
	state  PortState
	port   uint32
}

type Forwarder struct {
	logger        *zerolog.Logger
	cgroupManager cgroups.Manager
	// Map of ports that are being currently forwarded.
	ports             map[string]*PortToForward
	scannerSubscriber *ScannerSubscriber
	sourceIP          net.IP
}

func NewForwarder(
	logger *zerolog.Logger,
	scanner *Scanner,
	cgroupManager cgroups.Manager,
) *Forwarder {
	scannerSub := scanner.AddSubscriber(
		logger,
		"port-forwarder",
		// We only want to forward ports that are actively listening on localhost.
		// CRITICAL FIX 2025-12-25: Removed "::" from filter
		// "::" means "all IPv6 interfaces" (like 0.0.0.0 for IPv4), NOT localhost
		// Services listening on all interfaces (0.0.0.0 or ::) should NOT be forwarded
		// because they're already accessible from outside. Only forward localhost-only services.
		&ScannerFilter{
			IPs:   []string{"127.0.0.1", "localhost", "::1"},
			State: "LISTEN",
		},
	)

	return &Forwarder{
		logger:            logger,
		sourceIP:          defaultGatewayIP,
		ports:             make(map[string]*PortToForward),
		scannerSubscriber: scannerSub,
		cgroupManager:     cgroupManager,
	}
}

func (f *Forwarder) StartForwarding(ctx context.Context) {
	if f.scannerSubscriber == nil {
		f.logger.Error().Msg("Cannot start forwarding because scanner subscriber is nil")

		return
	}

	for {
		// procs is an array of currently opened ports.
		if procs, ok := <-f.scannerSubscriber.Messages; ok {
			// Now we are going to refresh all ports that are being forwarded in the `ports` map. Maybe add new ones
			// and maybe remove some.

			// Go through the ports that are currently being forwarded and set all of them
			// to the `DELETE` state. We don't know yet if they will be there after refresh.
			for _, v := range f.ports {
				v.state = PortStateDelete
			}

			// Let's refresh our map of currently forwarded ports and mark the currently opened ones with the "FORWARD" state.
			// This will make sure we won't delete them later.
			for _, p := range procs {
				key := fmt.Sprintf("%d-%d", p.Pid, p.Laddr.Port)

				// We check if the opened port is in our map of forwarded ports.
				val, portOk := f.ports[key]
				if portOk {
					// Just mark the port as being forwarded so we don't delete it.
					// The actual socat process that handles forwarding should be running from the last iteration.
					val.state = PortStateForward
				} else {
					f.logger.Debug().
						Str("ip", p.Laddr.IP).
						Uint32("port", p.Laddr.Port).
						Uint32("family", familyToIPVersion(p.Family)).
						Str("state", p.Status).
						Msg("Detected new opened port on localhost that is not forwarded")

					// The opened port wasn't in the map so we create a new PortToForward and start forwarding.
					ptf := &PortToForward{
						pid:    p.Pid,
						port:   p.Laddr.Port,
						state:  PortStateForward,
						family: familyToIPVersion(p.Family),
					}
					f.ports[key] = ptf
					f.startPortForwarding(ctx, ptf)
				}
			}

			// We go through the ports map one more time and stop forwarding all ports
			// that stayed marked as "DELETE".
			for _, v := range f.ports {
				if v.state == PortStateDelete {
					f.stopPortForwarding(v)
				}
			}
		}
	}
}

func (f *Forwarder) startPortForwarding(ctx context.Context, p *PortToForward) {
	// ***** DIAGNOSTIC CODE - CLAUDE 2025-12-23 *****
	f.logger.Error().
		Str("VERSION_CHECK", "CLAUDE_MODIFIED_VERSION_2025-12-23-20-35").
		Msg(">>>>> PORT FORWARDING FUNCTION ENTRY - IF YOU SEE THIS, NEW CODE IS RUNNING <<<<<")
	// ***** END DIAGNOSTIC CODE *****

	// https://unix.stackexchange.com/questions/311492/redirect-application-listening-on-localhost-to-listening-on-external-interface
	// socat -d -d TCP4-LISTEN:4000,bind=169.254.0.21,fork TCP4:localhost:4000
	// reuseaddr is used to fix the "Address already in use" error when restarting socat quickly.

	// Try to find socat - first check absolute path, then PATH
	socatPath := "/usr/bin/socat"
	statInfo, statErr := os.Stat(socatPath)
	if os.IsNotExist(statErr) {
		f.logger.Warn().
			Str("path", socatPath).
			Msg("socat not found at /usr/bin/socat, trying PATH")

		// If /usr/bin/socat doesn't exist, try looking in PATH
		foundPath, lookErr := exec.LookPath("socat")
		if lookErr != nil {
			f.logger.
				Error().
				Err(lookErr).
				Str("attempted_path", socatPath).
				Msg("Failed to find socat binary")
			return
		}
		socatPath = foundPath
		f.logger.Info().
			Str("found_path", socatPath).
			Msg("Found socat via PATH")
	} else if statErr != nil {
		f.logger.Error().
			Err(statErr).
			Str("path", socatPath).
			Msg("Error stating socat")
		return
	} else {
		f.logger.Info().
			Str("path", socatPath).
			Int64("size", statInfo.Size()).
			Str("mode", statInfo.Mode().String()).
			Msg("socat found at /usr/bin/socat")
	}

	cmd := exec.CommandContext(ctx,
		socatPath, "-d", "-d", "-d",
		fmt.Sprintf("TCP4-LISTEN:%v,bind=%s,reuseaddr,fork", p.port, f.sourceIP.To4()),
		fmt.Sprintf("TCP%d:localhost:%v", p.family, p.port),
	)

	cgroupFD, ok := f.cgroupManager.GetFileDescriptor(cgroups.ProcessTypeSocat)

	cmd.SysProcAttr = &syscall.SysProcAttr{
		Setpgid:     true,
		CgroupFD:    cgroupFD,
		UseCgroupFD: ok,
	}

	f.logger.Debug().
		Str("socatCmd", cmd.String()).
		Int32("pid", p.pid).
		Uint32("family", p.family).
		IPAddr("sourceIP", f.sourceIP.To4()).
		Uint32("port", p.port).
		Msg("About to start port forwarding")

	if err := cmd.Start(); err != nil {
		f.logger.
			Error().
			Str("socatCmd", cmd.String()).
			Err(err).
			Msg("Failed to start port forwarding - failed to start socat")

		return
	}

	go func() {
		if err := cmd.Wait(); err != nil {
			f.logger.
				Debug().
				Str("socatCmd", cmd.String()).
				Err(err).
				Msg("Port forwarding socat process exited")
		}
	}()

	p.socat = cmd
}

func (f *Forwarder) stopPortForwarding(p *PortToForward) {
	if p.socat == nil {
		return
	}

	defer func() { p.socat = nil }()

	logger := f.logger.With().
		Str("socatCmd", p.socat.String()).
		Int32("pid", p.pid).
		Uint32("family", p.family).
		IPAddr("sourceIP", f.sourceIP.To4()).
		Uint32("port", p.port).
		Logger()

	logger.Debug().Msg("Stopping port forwarding")

	if err := syscall.Kill(-p.socat.Process.Pid, syscall.SIGKILL); err != nil {
		logger.Error().Err(err).Msg("Failed to kill process group")

		return
	}

	logger.Debug().Msg("Stopped port forwarding")
}

func familyToIPVersion(family uint32) uint32 {
	switch family {
	case syscall.AF_INET:
		return 4
	case syscall.AF_INET6:
		return 6
	default:
		return 0 // Unknown or unsupported family
	}
}
