package main

import (
	"context"
	"fmt"
	"log"
	"time"

	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"

	"github.com/e2b-dev/infra/packages/shared/pkg/grpc/orchestrator"
)

func main() {
	// 连接到 Orchestrator
	conn, err := grpc.NewClient("127.0.0.1:5008", grpc.WithTransportCredentials(insecure.NewCredentials()))
	if err != nil {
		log.Fatalf("did not connect: %v", err)
	}
	defer conn.Close()

	c := orchestrator.NewSandboxServiceClient(conn)

	// 创建 VM 请求
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
	defer cancel()

	templateID := "9ac9c8b9-9b8b-476c-9238-8266af308c32"
	teamID := "cfee9a8f-dbbc-4970-9180-d0de5a28148f"
	sandboxID := "manual-vm-grpc-01"

	fmt.Printf("Creating Sandbox: %s (Template: %s, Team: %s)\n", sandboxID, templateID, teamID)

	// SandboxesCreate Request
	req := &orchestrator.SandboxCreateRequest{
		Sandbox: &orchestrator.SandboxConfig{
			TemplateId:         templateID,
			TeamId:             teamID,
			SandboxId:          sandboxID,
			KernelVersion:      "vmlinux-6.1.158",
			FirecrackerVersion: "v1.12.1_d990331",
			Metadata: map[string]string{
				"source": "manual-grpc",
			},
			EnvVars: map[string]string{
				"TEST_VAR": "hello",
			},
		},
	}

	resp, err := c.Create(ctx, req)
	if err != nil {
		log.Fatalf("could not create sandbox: %v", err)
	}

	fmt.Printf("Sandbox Created! ClientID: %s\n", resp.ClientId)
}
