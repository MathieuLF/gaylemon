package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/MathieuLF/gaylemon/internal/config"
	"github.com/MathieuLF/gaylemon/internal/store"
	webapp "github.com/MathieuLF/gaylemon/internal/web"
)

var (
	version = "dev"
	commit  = "unknown"
	channel = "development"
)

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelInfo}))
	if len(os.Args) > 1 && os.Args[1] == "version" {
		_, _ = os.Stdout.WriteString(version + "\n")
		return
	}
	cfg, err := config.WebFromEnv()
	if err != nil {
		logger.Error("configuration invalide", "error", err)
		os.Exit(1)
	}
	if err := cfg.Validate(); err != nil {
		logger.Error("configuration incomplète", "error", err)
		os.Exit(1)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	repo, err := store.OpenPostgres(ctx, cfg.DatabaseURL)
	cancel()
	if err != nil {
		logger.Error("connexion PostgreSQL impossible", "error", err)
		os.Exit(1)
	}
	defer repo.Close()
	ctx, cancel = context.WithTimeout(context.Background(), 30*time.Second)
	err = repo.Migrate(ctx)
	cancel()
	if err != nil {
		logger.Error("migration PostgreSQL impossible", "error", err)
		os.Exit(1)
	}
	maintenanceContext, stopMaintenance := context.WithCancel(context.Background())
	defer stopMaintenance()
	go runMaintenance(maintenanceContext, repo, logger)

	server := &http.Server{
		Addr: cfg.ListenAddress,
		Handler: webapp.NewServerWithRelease(cfg, repo, logger, webapp.ReleaseInfo{
			Product: "gaylemon-microsite",
			Version: version,
			Commit:  commit,
			Channel: channel,
		}).Handler(),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       75 * time.Second,
		WriteTimeout:      75 * time.Second,
		IdleTimeout:       90 * time.Second,
		MaxHeaderBytes:    32 << 10,
	}
	go func() {
		logger.Info("service web démarré", "address", cfg.ListenAddress, "version", version, "commit", commit, "channel", channel)
		if err := server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			logger.Error("service web arrêté", "error", err)
			os.Exit(1)
		}
	}()
	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)
	<-stop
	shutdown, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	if err := server.Shutdown(shutdown); err != nil {
		logger.Error("arrêt incomplet", "error", err)
	}
}

func runMaintenance(ctx context.Context, repository *store.Postgres, logger *slog.Logger) {
	ticker := time.NewTicker(24 * time.Hour)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			maintenanceContext, cancel := context.WithTimeout(ctx, 5*time.Minute)
			result, err := repository.Maintain(maintenanceContext)
			cancel()
			if err != nil {
				logger.Warn("entretien PostgreSQL reporté", "error", err)
				continue
			}
			logger.Info("entretien PostgreSQL terminé", "result", string(result))
		}
	}
}
