package rootfs

import (
	"context"
	"fmt"
	"io"

	"github.com/e2b-dev/infra/packages/shared/pkg/storage/header"
)

// SimpleReadonlyProvider is a minimal provider that directly uses a file path
// without any overlay or NBD. Used for testing to isolate NBD issues.
type SimpleReadonlyProvider struct {
	path string
}

func NewSimpleReadonlyProvider(path string) (Provider, error) {
	return &SimpleReadonlyProvider{
		path: path,
	}, nil
}

func (o *SimpleReadonlyProvider) Start(ctx context.Context) error {
	// No-op: we're using the file directly
	return nil
}

func (o *SimpleReadonlyProvider) Path() (string, error) {
	return o.path, nil
}

func (o *SimpleReadonlyProvider) Close(ctx context.Context) error {
	// No-op: we don't own any resources
	return nil
}

func (o *SimpleReadonlyProvider) ExportDiff(ctx context.Context, out io.Writer, closeSandbox func(context.Context) error) (*header.DiffMetadata, error) {
	return nil, fmt.Errorf("ExportDiff not supported for SimpleReadonlyProvider")
}
