package fc

import (
	"path/filepath"

	"github.com/e2b-dev/infra/packages/orchestrator/internal/cfg"
)

const (
	SandboxKernelFile = "vmlinux.bin"

	FirecrackerBinaryName = "firecracker"

	buildDirName = "builds"
)

const (
	// envsDisk is the base path for Firecracker VM environments
	// This is where tmpfs mounts are created for sandbox rootfs symlinks
	envsDisk = "/mnt/data1/fc-envs/v1"

	SandboxRootfsFile = "rootfs.ext4"
)

var (
	entropyBytesSize    int64 = 1024 // 1 KB
	entropyRefillTime   int64 = 100
	entropyOneTimeBurst int64 = 0
)

type FirecrackerVersions struct {
	KernelVersion      string
	FirecrackerVersion string
}

func (t FirecrackerVersions) SandboxKernelDir() string {
	return t.KernelVersion
}

func (t FirecrackerVersions) HostKernelPath(config cfg.BuilderConfig) string {
	return filepath.Join(config.HostKernelsDir, t.KernelVersion, SandboxKernelFile)
}

func (t FirecrackerVersions) FirecrackerPath(config cfg.BuilderConfig) string {
	return filepath.Join(config.FirecrackerVersionsDir, t.FirecrackerVersion, FirecrackerBinaryName)
}

type RootfsPaths struct {
	TemplateVersion uint64
	TemplateID      string
	BuildID         string
}

var ConstantRootfsPaths = RootfsPaths{
	// The version is always 2 for the constant rootfs paths format change.
	TemplateVersion: 2,
}

// Deprecated: Use static rootfs path instead.
func (t RootfsPaths) DeprecatedSandboxRootfsDir() string {
	return filepath.Join(envsDisk, t.TemplateID, buildDirName, t.BuildID)
}
