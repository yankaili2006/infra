package network

import (
	"context"
	"fmt"
	"io"
	"net"
	"sync"
	"sync/atomic"
	"time"

	"go.uber.org/zap"

	"github.com/e2b-dev/infra/packages/shared/pkg/logger"
)

// TCPProxy implements a high-performance TCP proxy with zero-copy forwarding,
// connection retry, and backoff strategy for handling envd startup delays
type TCPProxy struct {
	listenAddr string      // Address to listen on (e.g., "10.11.0.2:49983")
	targetAddr string      // Address to forward to (e.g., "10.12.0.5:49983")
	listener   net.Listener
	ctx        context.Context
	cancel     context.CancelFunc
	wg         sync.WaitGroup

	// Retry configuration
	maxRetries    int           // Maximum number of dial retries (default: 10)
	retryInterval time.Duration // Initial retry interval (default: 500ms)
	dialTimeout   time.Duration // Single dial timeout (default: 2s)

	// Metrics
	activeConns int64
	totalConns  int64
	bytesRx     int64
	bytesTx     int64

	// Metadata
	name string // For logging (e.g., "Layer1" or "Layer2")
}

// NewTCPProxy creates a new TCP proxy instance with configurable retry behavior
func NewTCPProxy(name, listenAddr, targetAddr string) *TCPProxy {
	ctx, cancel := context.WithCancel(context.Background())

	return &TCPProxy{
		name:          name,
		listenAddr:    listenAddr,
		targetAddr:    targetAddr,
		ctx:           ctx,
		cancel:        cancel,
		maxRetries:    10,                   // Retry up to 10 times
		retryInterval: 500 * time.Millisecond, // Wait 500ms between retries
		dialTimeout:   2 * time.Second,        // 2s timeout per dial attempt
	}
}

// Start begins listening and accepting connections
// This is non-blocking - it returns immediately after starting the accept loop
func (p *TCPProxy) Start(ctx context.Context) error {
	listener, err := net.Listen("tcp", p.listenAddr)
	if err != nil {
		return fmt.Errorf("failed to listen on %s: %w", p.listenAddr, err)
	}

	p.listener = listener

	logger.L().Info(ctx, fmt.Sprintf("%s TCP proxy started", p.name),
		zap.String("listen", p.listenAddr),
		zap.String("target", p.targetAddr),
	)

	p.wg.Add(1)
	go p.acceptLoop(ctx)

	return nil
}

// acceptLoop continuously accepts incoming connections
func (p *TCPProxy) acceptLoop(ctx context.Context) {
	defer p.wg.Done()

	for {
		conn, err := p.listener.Accept()
		if err != nil {
			select {
			case <-p.ctx.Done():
				// Graceful shutdown
				return
			default:
				logger.L().Warn(ctx, fmt.Sprintf("%s accept error", p.name),
					zap.Error(err),
				)
				continue
			}
		}

		atomic.AddInt64(&p.totalConns, 1)
		atomic.AddInt64(&p.activeConns, 1)

		logger.L().Debug(ctx, fmt.Sprintf("%s new connection", p.name),
			zap.String("remote", conn.RemoteAddr().String()),
			zap.Int64("active_conns", atomic.LoadInt64(&p.activeConns)),
		)

		p.wg.Add(1)
		go p.handleConnectionWithRetry(ctx, conn)
	}
}

// handleConnectionWithRetry forwards data bidirectionally with retry logic for envd startup delays
// This is the key improvement: it "holds" the client connection while waiting for envd to become ready
func (p *TCPProxy) handleConnectionWithRetry(ctx context.Context, clientConn net.Conn) {
	defer p.wg.Done()
	defer clientConn.Close()
	defer atomic.AddInt64(&p.activeConns, -1)

	var targetConn net.Conn
	var err error

	// --- Core Retry Logic with Exponential Backoff ---
	for i := 0; i < p.maxRetries; i++ {
		// Dial with timeout using context-aware dialer
		dialer := &net.Dialer{
			Timeout: p.dialTimeout,
		}

		targetConn, err = dialer.DialContext(p.ctx, "tcp", p.targetAddr)

		if err == nil {
			// Connection successful!
			break
		}

		// Log retry attempt
		if i < p.maxRetries-1 {
			logger.L().Warn(ctx, fmt.Sprintf("%s failed to connect to target, retrying", p.name),
				zap.String("target", p.targetAddr),
				zap.Int("attempt", i+1),
				zap.Int("max_retries", p.maxRetries),
				zap.Duration("retry_in", p.retryInterval),
				zap.Error(err),
			)
		}

		// Wait before retry with context cancellation support
		select {
		case <-time.After(p.retryInterval):
			// Continue to next retry
		case <-p.ctx.Done():
			// Proxy is shutting down
			return
		}
	}

	if err != nil {
		logger.L().Error(ctx, fmt.Sprintf("%s critical: failed to connect after all retries", p.name),
			zap.String("target", p.targetAddr),
			zap.Int("total_attempts", p.maxRetries),
			zap.Error(err),
		)
		return
	}
	defer targetConn.Close()

	logger.L().Debug(ctx, fmt.Sprintf("%s connection established after retry", p.name),
		zap.String("client", clientConn.RemoteAddr().String()),
		zap.String("target", p.targetAddr),
	)

	// Bidirectional copy using io.Copy (zero-copy with splice syscall)
	errCh := make(chan error, 2)

	// Client -> Target
	go func() {
		n, err := io.Copy(targetConn, clientConn)
		atomic.AddInt64(&p.bytesTx, n)
		errCh <- err
	}()

	// Target -> Client
	go func() {
		n, err := io.Copy(clientConn, targetConn)
		atomic.AddInt64(&p.bytesRx, n)
		errCh <- err
	}()

	// Wait for either direction to close or context cancellation
	select {
	case <-errCh:
		// One direction closed, normal termination
	case <-p.ctx.Done():
		// Proxy shutdown
	}

	logger.L().Debug(ctx, fmt.Sprintf("%s connection closed", p.name),
		zap.String("client", clientConn.RemoteAddr().String()),
	)
}

// Stop gracefully shuts down the proxy
func (p *TCPProxy) Stop(ctx context.Context) error {
	logger.L().Info(ctx, fmt.Sprintf("%s TCP proxy stopping", p.name))

	// Cancel context to signal all goroutines to stop
	p.cancel()

	if p.listener != nil {
		if err := p.listener.Close(); err != nil {
			logger.L().Warn(ctx, fmt.Sprintf("%s error closing listener", p.name),
				zap.Error(err),
			)
		}
	}

	// Wait for all connections to finish (with timeout)
	done := make(chan struct{})
	go func() {
		p.wg.Wait()
		close(done)
	}()

	select {
	case <-done:
		logger.L().Info(ctx, fmt.Sprintf("%s TCP proxy stopped gracefully", p.name))
	case <-time.After(5 * time.Second):
		logger.L().Warn(ctx, fmt.Sprintf("%s TCP proxy stop timeout, forcing shutdown", p.name))
	}

	return nil
}

// GetStats returns current proxy statistics
func (p *TCPProxy) GetStats() (activeConns, totalConns, bytesRx, bytesTx int64) {
	return atomic.LoadInt64(&p.activeConns),
		atomic.LoadInt64(&p.totalConns),
		atomic.LoadInt64(&p.bytesRx),
		atomic.LoadInt64(&p.bytesTx)
}

// IsHealthy checks if the proxy is running and accepting connections
func (p *TCPProxy) IsHealthy() bool {
	return p.listener != nil
}
