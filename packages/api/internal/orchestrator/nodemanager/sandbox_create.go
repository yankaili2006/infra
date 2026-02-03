package nodemanager

import (
	"context"

	"github.com/e2b-dev/infra/packages/shared/pkg/grpc/orchestrator"
)

func (n *Node) SandboxCreate(ctx context.Context, sbxRequest *orchestrator.SandboxCreateRequest) (*orchestrator.SandboxCreateResponse, error) {
	client, ctx := n.GetClient(ctx)
	resp, err := client.Sandbox.Create(n.GetSandboxCreateCtx(ctx, sbxRequest), sbxRequest)
	if err != nil {
		return nil, err
	}

	return resp, nil
}
