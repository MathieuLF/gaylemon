package background

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"time"

	"github.com/riverqueue/river"
)

const databaseMaintenanceKind = "database_maintenance"

// Maintainer is implemented by the PostgreSQL repository. Keeping the worker
// on this small contract makes its retry and scheduling behavior testable.
type Maintainer interface {
	Maintain(context.Context) (json.RawMessage, error)
}

type databaseMaintenanceArgs struct{}

func (databaseMaintenanceArgs) Kind() string { return databaseMaintenanceKind }

type databaseMaintenanceWorker struct {
	river.WorkerDefaults[databaseMaintenanceArgs]

	maintainer Maintainer
	logger     *slog.Logger
}

func (w *databaseMaintenanceWorker) Timeout(*river.Job[databaseMaintenanceArgs]) time.Duration {
	return 5 * time.Minute
}

func (w *databaseMaintenanceWorker) Work(ctx context.Context, _ *river.Job[databaseMaintenanceArgs]) error {
	result, err := w.maintainer.Maintain(ctx)
	if err != nil {
		return fmt.Errorf("entretien PostgreSQL: %w", err)
	}
	w.logger.InfoContext(ctx, "entretien PostgreSQL terminé", "result", string(result))
	return nil
}

func maintenancePeriodicJob() *river.PeriodicJob {
	return river.NewPeriodicJob(
		river.PeriodicInterval(maintenanceInterval),
		func() (river.JobArgs, *river.InsertOpts) {
			return databaseMaintenanceArgs{}, maintenanceInsertOpts()
		},
		&river.PeriodicJobOpts{
			ID:         "daily_database_maintenance",
			RunOnStart: true,
		},
	)
}

func maintenanceInsertOpts() *river.InsertOpts {
	return &river.InsertOpts{
		MaxAttempts: 3,
		Queue:       maintenanceQueue,
		UniqueOpts: river.UniqueOpts{
			ByPeriod: maintenanceInterval,
			ByQueue:  true,
		},
	}
}
