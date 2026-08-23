package background

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"testing"
	"time"
)

type fakeMaintainer struct {
	result json.RawMessage
	err    error
	calls  int
}

func (m *fakeMaintainer) Maintain(context.Context) (json.RawMessage, error) {
	m.calls++
	return m.result, m.err
}

func TestDatabaseMaintenanceWorker(t *testing.T) {
	t.Parallel()
	maintainer := &fakeMaintainer{result: json.RawMessage(`{"deleted":2}`)}
	worker := &databaseMaintenanceWorker{
		maintainer: maintainer,
		logger:     slog.New(slog.NewTextHandler(io.Discard, nil)),
	}

	if err := worker.Work(context.Background(), nil); err != nil {
		t.Fatalf("Work() error = %v", err)
	}
	if maintainer.calls != 1 {
		t.Fatalf("Maintain() calls = %d, want 1", maintainer.calls)
	}
	if got := worker.Timeout(nil); got != 5*time.Minute {
		t.Fatalf("Timeout() = %s, want 5m", got)
	}
}

func TestDatabaseMaintenanceWorkerReturnsRepositoryError(t *testing.T) {
	t.Parallel()
	maintainer := &fakeMaintainer{err: errors.New("indisponible")}
	worker := &databaseMaintenanceWorker{
		maintainer: maintainer,
		logger:     slog.New(slog.NewTextHandler(io.Discard, nil)),
	}

	err := worker.Work(context.Background(), nil)
	if err == nil || !errors.Is(err, maintainer.err) {
		t.Fatalf("Work() error = %v, want wrapped repository error", err)
	}
}

func TestMaintenanceInsertionPolicy(t *testing.T) {
	t.Parallel()
	opts := maintenanceInsertOpts()
	if opts.Queue != maintenanceQueue {
		t.Fatalf("Queue = %q, want %q", opts.Queue, maintenanceQueue)
	}
	if opts.MaxAttempts != 3 {
		t.Fatalf("MaxAttempts = %d, want 3", opts.MaxAttempts)
	}
	if opts.UniqueOpts.ByPeriod != 24*time.Hour || !opts.UniqueOpts.ByQueue {
		t.Fatalf("UniqueOpts = %+v, want daily uniqueness by queue", opts.UniqueOpts)
	}
	if got := (databaseMaintenanceArgs{}).Kind(); got != databaseMaintenanceKind {
		t.Fatalf("Kind() = %q, want %q", got, databaseMaintenanceKind)
	}
}
