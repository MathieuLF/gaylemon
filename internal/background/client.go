package background

import (
	"context"
	"fmt"
	"log/slog"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/riverqueue/river"
	"github.com/riverqueue/river/riverdriver/riverpgxv5"
	"github.com/riverqueue/river/rivermigrate"
)

const (
	schemaName          = "gaylemon_ops"
	maintenanceQueue    = "maintenance"
	maintenanceInterval = 24 * time.Hour
)

// Migrate applies and validates the database migrations required by the
// background job queue in Gaylémon's operational schema.
func Migrate(ctx context.Context, pool *pgxpool.Pool, logger *slog.Logger) error {
	migrator, err := rivermigrate.New(riverpgxv5.New(pool), &rivermigrate.Config{
		Logger: logger,
		Schema: schemaName,
	})
	if err != nil {
		return fmt.Errorf("préparation des migrations de travaux: %w", err)
	}
	if _, err := migrator.Migrate(ctx, rivermigrate.DirectionUp, nil); err != nil {
		return fmt.Errorf("application des migrations de travaux: %w", err)
	}
	validation, err := migrator.Validate(ctx, nil)
	if err != nil {
		return fmt.Errorf("validation des migrations de travaux: %w", err)
	}
	if !validation.OK {
		return fmt.Errorf("migrations de travaux incomplètes: %s", strings.Join(validation.Messages, "; "))
	}
	return nil
}

// NewClient configures the database-backed background work handled by the web
// service. A single worker keeps maintenance bounded on the production VPS.
func NewClient(pool *pgxpool.Pool, maintainer Maintainer, logger *slog.Logger) (*river.Client[pgx.Tx], error) {
	workers := river.NewWorkers()
	if err := river.AddWorkerSafely(workers, &databaseMaintenanceWorker{
		maintainer: maintainer,
		logger:     logger,
	}); err != nil {
		return nil, fmt.Errorf("enregistrement du travail d'entretien: %w", err)
	}

	client, err := river.NewClient(riverpgxv5.New(pool), &river.Config{
		Logger: logger,
		PeriodicJobs: []*river.PeriodicJob{
			maintenancePeriodicJob(),
		},
		Queues: map[string]river.QueueConfig{
			maintenanceQueue: {MaxWorkers: 1},
		},
		Schema:          schemaName,
		SoftStopTimeout: 15 * time.Second,
		Workers:         workers,
	})
	if err != nil {
		return nil, fmt.Errorf("configuration des travaux d'arrière-plan: %w", err)
	}
	return client, nil
}
