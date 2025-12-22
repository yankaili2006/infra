package main

import (
	"context"
	"fmt"
	"io"
	"os"
	"os/signal"
	"syscall"

	"connectrpc.com/connect"
	"golang.org/x/term"

	"github.com/e2b-dev/infra/packages/shared/pkg/grpc/envd/process"
	"github.com/e2b-dev/infra/packages/shared/pkg/grpc/envd/process/processconnect"
)

// E2B Interactive Shell Client
// 通过envd提供类似SSH的交互式终端体验

const (
	defaultEnvdURL = "http://10.11.13.173:49983" // VM内部envd地址
	defaultShell   = "/bin/sh"
)

type ShellClient struct {
	client processconnect.ProcessServiceClient
	ctx    context.Context
}

func NewShellClient(envdURL string) *ShellClient {
	client := processconnect.NewProcessServiceClient(
		nil, // TODO: 添加HTTP客户端
		envdURL,
	)

	return &ShellClient{
		client: client,
		ctx:    context.Background(),
	}
}

// StartInteractiveShell 启动交互式shell
func (c *ShellClient) StartInteractiveShell() error {
	// 获取终端大小
	width, height, err := term.GetSize(int(os.Stdin.Fd()))
	if err != nil {
		return fmt.Errorf("failed to get terminal size: %w", err)
	}

	// 设置终端为raw模式
	oldState, err := term.MakeRaw(int(os.Stdin.Fd()))
	if err != nil {
		return fmt.Errorf("failed to set terminal raw mode: %w", err)
	}
	defer term.Restore(int(os.Stdin.Fd()), oldState)

	// 创建PTY配置
	req := connect.NewRequest(&process.StartRequest{
		Process: &process.ProcessConfig{
			Cmd:  defaultShell,
			Args: []string{},
			Envs: map[string]string{
				"TERM": "xterm-256color",
				"HOME": "/root",
				"USER": "root",
			},
		},
		Pty: &process.PTY{
			Size: &process.PTY_Size{
				Cols: uint32(width),
				Rows: uint32(height),
			},
		},
		Stdin: func() *bool { b := true; return &b }(),
	})

	// 启动shell进程
	stream, err := c.client.Start(c.ctx, req)
	if err != nil {
		return fmt.Errorf("failed to start shell: %w", err)
	}
	defer stream.Close()

	// 处理终端大小变化
	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGWINCH)
	go func() {
		for range sigCh {
			w, h, _ := term.GetSize(int(os.Stdin.Fd()))
			// TODO: 发送UpdateRequest更新终端大小
			_ = w
			_ = h
		}
	}()

	// 启动输入goroutine
	inputCh := make(chan []byte)
	go func() {
		buf := make([]byte, 1024)
		for {
			n, err := os.Stdin.Read(buf)
			if err != nil {
				if err != io.EOF {
					fmt.Fprintf(os.Stderr, "stdin read error: %v\n", err)
				}
				close(inputCh)
				return
			}
			inputCh <- buf[:n]
		}
	}()

	// 主循环：处理输出和输入
	var pid uint32
	for {
		select {
		case input, ok := <-inputCh:
			if !ok {
				return nil
			}
			// 发送输入到shell
			sendReq := connect.NewRequest(&process.SendInputRequest{
				Process: &process.ProcessSelector{
					Selector: &process.ProcessSelector_Pid{
						Pid: pid,
					},
				},
				Input: &process.ProcessInput{
					Input: &process.ProcessInput_Pty{
						Pty: input,
					},
				},
			})
			_, err := c.client.SendInput(c.ctx, sendReq)
			if err != nil {
				return fmt.Errorf("failed to send input: %w", err)
			}

		default:
			// 接收shell输出
			if !stream.Receive() {
				if err := stream.Err(); err != nil {
					return fmt.Errorf("stream error: %w", err)
				}
				return nil
			}

			msg := stream.Msg()
			event := msg.GetEvent()

			if start := event.GetStart(); start != nil {
				pid = start.GetPid()
			}

			if data := event.GetData(); data != nil {
				if ptyData := data.GetPty(); ptyData != nil {
					os.Stdout.Write(ptyData)
				}
			}

			if end := event.GetEnd(); end != nil {
				if end.GetExitCode() != 0 {
					return fmt.Errorf("shell exited with code: %d", end.GetExitCode())
				}
				return nil
			}
		}
	}
}

func main() {
	if len(os.Args) < 2 {
		fmt.Println("Usage: e2b-shell <sandbox-id>")
		fmt.Println("Example: e2b-shell itzzutamgzsz4dpf7tjbq")
		os.Exit(1)
	}

	sandboxID := os.Args[1]

	// TODO: 通过API获取sandbox的envd地址
	fmt.Printf("Connecting to VM %s...\n", sandboxID)
	fmt.Println("Press Ctrl+D or type 'exit' to disconnect")
	fmt.Println()

	client := NewShellClient(defaultEnvdURL)
	if err := client.StartInteractiveShell(); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
}
