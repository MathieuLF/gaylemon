package main

import (
	"context"
	"crypto/ed25519"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"log/slog"
	"os"
	"os/signal"
	"path/filepath"
	"runtime/debug"
	"syscall"
	"time"

	"github.com/MathieuLF/gaylemon/internal/agent"
	"github.com/MathieuLF/gaylemon/internal/collector"
)

var version = "dev"

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelInfo}))
	if err := run(os.Args[1:], logger); err != nil {
		logger.Error("commande échouée", "error", err)
		os.Exit(1)
	}
}

func run(arguments []string, logger *slog.Logger) error {
	if len(arguments) == 0 {
		return errors.New("commande requise: keygen, config-check, collect, enqueue, publish, run ou queue-status")
	}
	switch arguments[0] {
	case "version":
		fmt.Println(buildVersion())
		return nil
	case "keygen":
		return keygen(arguments[1:])
	case "config-check":
		config, err := agent.ConfigFromEnv()
		if err != nil {
			return err
		}
		if err := config.Validate(); err != nil {
			return err
		}
		fmt.Printf("configuration valide pour %s vers %s\n", config.AgentID, config.APIBaseURL)
		return nil
	case "enqueue", "publish":
		return publish(arguments[0], arguments[1:], logger)
	case "collect":
		return collect(arguments[1:], logger)
	case "run":
		return runAgent(logger)
	case "queue-status":
		return queueStatus()
	default:
		return fmt.Errorf("commande inconnue: %s", arguments[0])
	}
}

func collect(arguments []string, logger *slog.Logger) error {
	flags := flag.NewFlagSet("collect", flag.ContinueOnError)
	kind := flags.String("kind", "metrics", "projection à produire: metrics, stats ou events")
	if err := flags.Parse(arguments); err != nil {
		return err
	}
	config, err := agent.ConfigFromEnv()
	if err != nil {
		return err
	}
	if err := config.Validate(); err != nil {
		return err
	}
	spool, err := agent.OpenSpool(config.SpoolPath)
	if err != nil {
		return err
	}
	defer spool.Close()
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()
	result, err := collector.CollectPublic(ctx, collector.PublicConfigFromEnv(), *kind)
	if err != nil {
		return err
	}
	batches, err := agent.EnqueueDocuments(ctx, spool, config.AgentID, *kind, "", result.Documents, result.Usage, result.Summary)
	if err != nil {
		return err
	}
	logger.Info("projection ajoutée à la file", "kind", *kind, "batches", len(batches))
	return nil
}

func keygen(arguments []string) error {
	flags := flag.NewFlagSet("keygen", flag.ContinueOnError)
	privatePath := flags.String("private", "gaylemon-agent.key", "fichier privé à créer")
	if err := flags.Parse(arguments); err != nil {
		return err
	}
	publicKey, privateKey, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		return err
	}
	absolute, err := filepath.Abs(*privatePath)
	if err != nil {
		return err
	}
	file, err := os.OpenFile(absolute, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o600)
	if err != nil {
		return fmt.Errorf("création de la clé privée: %w", err)
	}
	if _, err := file.WriteString(base64.StdEncoding.EncodeToString(privateKey) + "\n"); err != nil {
		file.Close()
		return err
	}
	if err := file.Close(); err != nil {
		return err
	}
	fmt.Printf("clé privée créée: %s\nclé publique: %s\n", absolute, base64.StdEncoding.EncodeToString(publicKey))
	return nil
}

func publish(command string, arguments []string, logger *slog.Logger) error {
	flags := flag.NewFlagSet(command, flag.ContinueOnError)
	source := flags.String("source", "portal/data", "répertoire JSON filtré")
	prefix := flags.String("prefix", "data", "préfixe public")
	stream := flags.String("stream", "public", "nom du flux")
	revision := flags.String("revision", "", "révision de la source")
	shadow := flags.Bool("shadow", false, "enregistrer sans activer les documents")
	if err := flags.Parse(arguments); err != nil {
		return err
	}
	config, err := agent.ConfigFromEnv()
	if err != nil {
		return err
	}
	if err := config.Validate(); err != nil {
		return err
	}
	spool, err := agent.OpenSpool(config.SpoolPath)
	if err != nil {
		return err
	}
	defer spool.Close()
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Minute)
	defer cancel()
	batches, err := agent.EnqueueDirectory(ctx, spool, config.AgentID, *stream, *source, *prefix, *revision)
	if err != nil {
		return err
	}
	logger.Info("publication ajoutée à la file", "batches", len(batches), "stream", *stream)
	if command == "enqueue" {
		return nil
	}
	client := agent.NewClient(config)
	client.Shadow = *shadow
	runner := agent.Runner{Config: config, Spool: spool, Client: client, Logger: logger, Version: buildVersion()}
	completed, err := runner.Flush(ctx)
	if err != nil {
		return fmt.Errorf("lot conservé dans la file après %d publication(s): %w", completed, err)
	}
	logger.Info("file publiée", "batches", completed)
	return nil
}

func runAgent(logger *slog.Logger) error {
	config, err := agent.ConfigFromEnv()
	if err != nil {
		return err
	}
	if err := config.Validate(); err != nil {
		return err
	}
	spool, err := agent.OpenSpool(config.SpoolPath)
	if err != nil {
		return err
	}
	defer spool.Close()
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	runner := agent.Runner{Config: config, Spool: spool, Client: agent.NewClient(config), Logger: logger, Version: buildVersion()}
	err = runner.Run(ctx)
	if errors.Is(err, context.Canceled) {
		return nil
	}
	return err
}

func queueStatus() error {
	path := os.Getenv("GAYLEMON_AGENT_SPOOL")
	if path == "" {
		path = "/var/lib/gaylemon-agent/spool.db"
	}
	spool, err := agent.OpenSpool(path)
	if err != nil {
		return err
	}
	defer spool.Close()
	depth, err := spool.Depth(context.Background())
	if err != nil {
		return err
	}
	return json.NewEncoder(os.Stdout).Encode(map[string]any{"queueDepth": depth, "spool": path})
}

func buildVersion() string {
	if version != "dev" {
		return version
	}
	if info, ok := debug.ReadBuildInfo(); ok && info.Main.Version != "" && info.Main.Version != "(devel)" {
		return info.Main.Version
	}
	return version
}
