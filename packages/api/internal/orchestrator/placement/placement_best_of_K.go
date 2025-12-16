package placement

import (
	"context"
	"fmt"
	"math"
	"math/rand"
	"sync"

	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"

	"github.com/e2b-dev/infra/packages/api/internal/api"
	"github.com/e2b-dev/infra/packages/api/internal/orchestrator/nodemanager"
	"github.com/e2b-dev/infra/packages/shared/pkg/machineinfo"
)

// BestOfKConfig holds the configuration parameters for the placement algorithm
type BestOfKConfig struct {
	// R is the cluster-wide max over-commit ratio
	R float64
	// Alpha is the weight for CPU usage in the score calculation
	Alpha float64
	// K is the number of candidate nodes sampled per placement ("power of K choices")
	K int
	// TooManyStarting determines whether to skip nodes that are starting more than maxStartingInstancesPerNode instances
	TooManyStarting bool
	// CanFit determines whether to skip the node CanFit check
	CanFit bool
}

// DefaultBestOfKConfig returns the default placement configuration
func DefaultBestOfKConfig() BestOfKConfig {
	return BestOfKConfig{
		R:     4,
		K:     3,
		Alpha: 0.5,
	}
}

// Score calculates the placement score for this node
func (b *BestOfK) Score(node *nodemanager.Node, resources nodemanager.SandboxResources, config BestOfKConfig) float64 {
	metrics := node.Metrics()
	reserved := metrics.CpuAllocated

	// 1 CPU used = 100% CPU percept
	usageAvg := float64(metrics.CpuPercent) / 100

	// to avoid division by zero
	cpuCount := float64(metrics.CpuCount)
	if cpuCount == 0 {
		return math.MaxFloat64
	}

	totalCapacity := config.R * cpuCount

	cpuRequested := float64(resources.CPUs)

	return (cpuRequested + float64(reserved) + config.Alpha*usageAvg) / totalCapacity
}

// CanFit checks if the node can fit a new VM with the given quota
func (b *BestOfK) CanFit(node *nodemanager.Node, sandboxResources nodemanager.SandboxResources, config BestOfKConfig) bool {
	metrics := node.Metrics()

	reserved := metrics.CpuAllocated

	// If the node has no CPUs, there's probably a problem
	cpuCount := float64(metrics.CpuCount)
	if cpuCount == 0 {
		return false
	}

	totalCapacity := config.R * cpuCount

	return float64(reserved+uint32(sandboxResources.CPUs)) <= totalCapacity
}

// BestOfK implements the fit-score-place algorithm
type BestOfK struct {
	config BestOfKConfig
	mu     sync.RWMutex
}

var _ Algorithm = &BestOfK{}

// NewBestOfK creates a new placement algorithm with the given config
func NewBestOfK(config BestOfKConfig) Algorithm {
	return &BestOfK{
		config: config,
	}
}

func (b *BestOfK) getConfig() BestOfKConfig {
	b.mu.RLock()
	defer b.mu.RUnlock()

	return b.config
}

// UpdateConfig updates the BestOfK algorithm configuration
func (b *BestOfK) UpdateConfig(config BestOfKConfig) {
	b.mu.Lock()
	defer b.mu.Unlock()
	b.config = config
}

func (b *BestOfK) excludeNode(err error) bool {
	st, ok := status.FromError(err)
	// If the node is just exhausted, keep it
	if ok && st.Code() == codes.ResourceExhausted {
		return false
	}

	return true
}

// chooseNode selects the best node for placing a VM with the given quota
func (b *BestOfK) chooseNode(_ context.Context, nodes []*nodemanager.Node, excludedNodes map[string]struct{}, resources nodemanager.SandboxResources, buildMachineInfo machineinfo.MachineInfo) (bestNode *nodemanager.Node, err error) {
	// Fix the config, we want to dynamically update it
	config := b.getConfig()

	fmt.Printf("DEBUG: chooseNode starting with %d nodes\n", len(nodes))

	// Filter eligible nodes
	candidates := b.sample(nodes, config, excludedNodes, resources, buildMachineInfo)

	fmt.Printf("DEBUG: chooseNode got %d candidates from sample\n", len(candidates))

	// Find the best node among candidates
	bestScore := math.MaxFloat64

	for _, node := range candidates {
		// Calculate score
		score := b.Score(node, resources, config)

		fmt.Printf("DEBUG: Node %s has score %f\n", node.ID, score)

		if score < bestScore {
			bestNode = node
			bestScore = score
			fmt.Printf("DEBUG: Node %s is now best with score %f\n", node.ID, score)
		}
	}

	if bestNode == nil {
		fmt.Printf("DEBUG: No best node selected, returning error\n")
		return nil, fmt.Errorf("no node available")
	}

	fmt.Printf("DEBUG: Selected best node %s with score %f\n", bestNode.ID, bestScore)
	return bestNode, nil
}

// sample returns up to k items chosen uniformly from those passing ok.
func (b *BestOfK) sample(items []*nodemanager.Node, config BestOfKConfig, excludedNodes map[string]struct{}, resources nodemanager.SandboxResources, buildMachineInfo machineinfo.MachineInfo) []*nodemanager.Node {
	if config.K <= 0 || len(items) == 0 {
		return nil
	}

	// Debug logging for placement
	fmt.Printf("DEBUG: Starting sample with %d nodes, config: K=%d, CanFit=%t, TooManyStarting=%t\n",
		len(items), config.K, config.CanFit, config.TooManyStarting)

	indices := make([]int, len(items))
	for i := range indices {
		indices[i] = i
	}

	candidates := make([]*nodemanager.Node, 0, config.K)
	remaining := len(indices) // active pool is indices[:remaining]

	for len(candidates) < config.K && remaining > 0 {
		// pick from the active pool
		j := rand.Intn(remaining)
		pick := indices[j]

		// remove j from pool
		indices[j], indices[remaining-1] = indices[remaining-1], indices[j]
		remaining--

		n := items[pick]

		fmt.Printf("DEBUG: Evaluating node %s (ID: %s, Status: %s)\n", n.ID, n.ID, n.Status())

		// Excluded filter
		if _, ok := excludedNodes[n.ID]; ok {
			fmt.Printf("DEBUG: Node %s excluded\n", n.ID)
			continue
		}

		// If the node is not ready, skip it
		if n.Status() != api.NodeStatusReady {
			fmt.Printf("DEBUG: Node %s not ready, status: %s\n", n.ID, n.Status())
			continue
		}

		// Skip if node is not CPU compatible
		if !isNodeCPUCompatible(n, buildMachineInfo) {
			fmt.Printf("DEBUG: Node %s not CPU compatible\n", n.ID)
			continue
		}

		if config.CanFit {
			if !b.CanFit(n, resources, config) {
				fmt.Printf("DEBUG: Node %s cannot fit resources\n", n.ID)
				continue
			}
		}

		if config.TooManyStarting {
			// To prevent overloading the node
			if n.PlacementMetrics.InProgressCount() > maxStartingInstancesPerNode {
				fmt.Printf("DEBUG: Node %s has too many starting instances\n", n.ID)
				continue
			}
		}

		fmt.Printf("DEBUG: Node %s added to candidates\n", n.ID)
		candidates = append(candidates, n)
	}

	fmt.Printf("DEBUG: Sample completed, found %d candidates\n", len(candidates))
	return candidates
}
