package main

import (
	"context"
	"fmt"
	"log"
	"time"

	"github.com/google/uuid"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
	"google.golang.org/protobuf/types/known/emptypb"
	"google.golang.org/protobuf/types/known/timestamppb"

	pb "github.com/e2b-dev/infra/packages/shared/pkg/grpc/orchestrator"
)

func main() {
	// Connect to orchestrator
	conn, err := grpc.Dial("192.168.99.5:5008",
		grpc.WithTransportCredentials(insecure.NewCredentials()),
	)
	if err != nil {
		log.Fatalf("Failed to connect: %v", err)
	}
	defer conn.Close()

	client := pb.NewSandboxServiceClient(conn)
	fmt.Println("✓ Connected to orchestrator at 192.168.99.5:5008")

	// First, list existing sandboxes
	fmt.Println("\n=== Listing existing sandboxes ===")
	listResp, err := client.List(context.Background(), &emptypb.Empty{})
	if err != nil {
		log.Printf("Warning: Failed to list sandboxes: %v", err)
	} else {
		fmt.Printf("Found %d existing sandboxes\n", len(listResp.GetSandboxes()))
		for _, sb := range listResp.GetSandboxes() {
			if sb.GetConfig() != nil {
				fmt.Printf("  - %s (template: %s, team: %s)\n",
					sb.GetConfig().GetSandboxId(),
					sb.GetConfig().GetTemplateId(),
					sb.GetConfig().GetTeamId())
			}
		}
	}

	// Create new sandbox
	fmt.Println("\n=== Creating new sandbox ===")
	sandboxID := uuid.New().String()

	req := &pb.SandboxCreateRequest{
		Sandbox: &pb.SandboxConfig{
			TemplateId:         "base-template-000-0000-0000-000000000001",
			BuildId:            "9ac9c8b9-9b8b-476c-9238-8266af308c32",
			KernelVersion:      "vmlinux-6.1.158",
			FirecrackerVersion: "v1.12.1_d990331",
			SandboxId:          sandboxID,
			TeamId:             "dd233824-fc0d-4549-aff6-6d8b7bfd3b32",
			Vcpu:               2,
			RamMb:              512,
			TotalDiskSizeMb:    2048,
			MaxSandboxLength:   3600, // 1 hour
			EnvVars:            map[string]string{},
			Metadata:           map[string]string{"test": "grpc-direct"},
		},
		StartTime: timestamppb.Now(),
		EndTime:   timestamppb.New(time.Now().Add(1 * time.Hour)),
	}

	fmt.Printf("Creating sandbox:\n")
	fmt.Printf("  Sandbox ID: %s\n", sandboxID)
	fmt.Printf("  Template: %s\n", req.Sandbox.TemplateId)
	fmt.Printf("  Build ID: %s\n", req.Sandbox.BuildId)
	fmt.Printf("  Team ID: %s\n", req.Sandbox.TeamId)
	fmt.Printf("  Resources: %d vCPU, %d MB RAM\n", req.Sandbox.Vcpu, req.Sandbox.RamMb)

	createResp, err := client.Create(context.Background(), req)
	if err != nil {
		log.Fatalf("Failed to create sandbox: %v", err)
	}

	fmt.Println("\n✅ Sandbox created successfully!")
	fmt.Printf("  Client ID: %s\n", createResp.GetClientId())

	// List sandboxes again to confirm
	fmt.Println("\n=== Listing sandboxes after creation ===")
	listResp, err = client.List(context.Background(), &emptypb.Empty{})
	if err != nil {
		log.Printf("Warning: Failed to list sandboxes: %v", err)
	} else {
		fmt.Printf("Total sandboxes: %d\n", len(listResp.GetSandboxes()))
		for _, sb := range listResp.GetSandboxes() {
			if sb.GetConfig() != nil {
				fmt.Printf("  - %s (template: %s, team: %s)\n",
					sb.GetConfig().GetSandboxId(),
					sb.GetConfig().GetTemplateId(),
					sb.GetConfig().GetTeamId())
			}
		}
	}

	fmt.Println("\n🎉 VM creation completed!")
}
