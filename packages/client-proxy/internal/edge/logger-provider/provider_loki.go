package logger_provider

import (
	"context"
	"time"

	"github.com/e2b-dev/infra/packages/shared/pkg/logs"
)

type LokiQueryProvider struct {
}

func NewLokiQueryProvider(config any) (*LokiQueryProvider, error) {
	return &LokiQueryProvider{}, nil
}

func (l *LokiQueryProvider) QueryBuildLogs(ctx context.Context, templateID string, buildID string, start time.Time, end time.Time, limit int, offset int32, level *logs.LogLevel, direction any) ([]logs.LogEntry, error) {
	return make([]logs.LogEntry, 0), nil
}

func (l *LokiQueryProvider) QuerySandboxLogs(ctx context.Context, teamID string, sandboxID string, start time.Time, end time.Time, limit int) ([]logs.LogEntry, error) {
	return make([]logs.LogEntry, 0), nil
}
