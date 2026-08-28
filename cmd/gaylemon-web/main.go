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

	"github.com/MathieuLF/gaylemon/internal/background"
	"github.com/MathieuLF/gaylemon/internal/config"
	"github.com/MathieuLF/gaylemon/internal/store"
	webapp "github.com/MathieuLF/gaylemon/internal/web"
)

var (
	version = "0.0.0-dev"
	commit  = "0000000000000000000000000000000000000000"
	builtAt = "1970-01-01T00:00:00Z"
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
	ctx, cancel = context.WithTimeout(context.Background(), 30*time.Second)
	err = background.Migrate(ctx, repo.Pool(), logger)
	cancel()
	if err != nil {
		logger.Error("migration des travaux d'arrière-plan impossible", "error", err)
		os.Exit(1)
	}
	jobClient, err := background.NewClient(repo.Pool(), repo, logger)
	if err != nil {
		logger.Error("initialisation des travaux d'arrière-plan impossible", "error", err)
		os.Exit(1)
	}
	if err := jobClient.Start(context.Background()); err != nil {
		logger.Error("démarrage des travaux d'arrière-plan impossible", "error", err)
		os.Exit(1)
	}

	server := &http.Server{
		Addr: cfg.ListenAddress,
		Handler: webapp.NewServerWithRelease(cfg, repo, logger, webapp.ReleaseInfo{
			Version: version,
			Commit:  commit,
			BuiltAt: builtAt,
		}).Handler(),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       75 * time.Second,
		WriteTimeout:      75 * time.Second,
		IdleTimeout:       90 * time.Second,
		MaxHeaderBytes:    32 << 10,
	}
	go func() {
		logger.Info("service web démarré", "address", cfg.ListenAddress, "version", version, "commit", commit, "builtAt", builtAt)
		if err := server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			logger.Error("service web arrêté", "error", err)
			os.Exit(1)
		}
	}()
	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)
	<-stop
	shutdown, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	if err := server.Shutdown(shutdown); err != nil {
		logger.Error("arrêt incomplet", "error", err)
	}
	cancel()
	jobsShutdown, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	if err := jobClient.Stop(jobsShutdown); err != nil {
		logger.Error("arrêt incomplet des travaux d'arrière-plan", "error", err)
	}
	cancel()
}
