package agent

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"os/exec"
	"strings"
	"time"

	"github.com/MathieuLF/gaylemon/internal/model"
)

type CommandExecutor struct {
	Helper  string
	Timeout time.Duration
	UseSudo bool
}

func (e CommandExecutor) Execute(ctx context.Context, command model.Command) model.CommandAck {
	arguments, err := commandArguments(command)
	if err != nil {
		return model.CommandAck{Status: "refused", Message: err.Error()}
	}
	if e.Helper == "" {
		return model.CommandAck{Status: "refused", Message: "outil d'exploitation non configuré"}
	}
	timeout := commandTimeout(command.Kind, e.Timeout)
	commandContext, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()
	executable := e.Helper
	processArguments := arguments
	if e.UseSudo {
		executable = "sudo"
		processArguments = append([]string{"-n", e.Helper}, arguments...)
	}
	process := exec.CommandContext(commandContext, executable, processArguments...)
	if command.Kind == "season.archive" {
		process.Cancel = func() error { return process.Process.Signal(os.Interrupt) }
		process.WaitDelay = 30 * time.Second
	}
	output, execErr := process.CombinedOutput()
	message := strings.TrimSpace(string(output))
	if len(message) > 4000 {
		message = message[len(message)-4000:]
	}
	if execErr != nil {
		if message == "" {
			message = execErr.Error()
		}
		return model.CommandAck{Status: "failed", Message: message}
	}
	ack := model.CommandAck{Status: "completed", Message: message}
	if json.Valid([]byte(message)) {
		ack.Details = json.RawMessage(message)
		ack.Message = "Cycle de saison exécuté et preuves structurées reçues."
	}
	return ack
}

func commandTimeout(kind string, configured time.Duration) time.Duration {
	if configured > 0 {
		return configured
	}
	if kind == "season.archive" {
		return 75 * time.Minute
	}
	return 2 * time.Minute
}

func commandArguments(command model.Command) ([]string, error) {
	var values map[string]any
	if len(command.Arguments) > 0 && json.Unmarshal(command.Arguments, &values) != nil {
		return nil, errors.New("arguments JSON invalides")
	}
	switch command.Kind {
	case "server.status":
		return []string{"status"}, nil
	case "server.logs":
		unit, _ := values["unit"].(string)
		if !allowedUnit(unit) {
			return nil, errors.New("unité de journal refusée")
		}
		return []string{"logs", unit}, nil
	case "sync.pause":
		stream, _ := values["stream"].(string)
		if !allowedStream(stream) {
			return nil, errors.New("flux de synchronisation refusé")
		}
		return []string{"sync", "pause", stream}, nil
	case "sync.resume":
		stream, _ := values["stream"].(string)
		if !allowedStream(stream) {
			return nil, errors.New("flux de synchronisation refusé")
		}
		return []string{"sync", "resume", stream}, nil
	case "sync.run":
		stream, _ := values["stream"].(string)
		if !allowedStream(stream) {
			return nil, errors.New("flux de synchronisation refusé")
		}
		return []string{"sync", "run", stream}, nil
	case "sync.set-schedule":
		stream, _ := values["stream"].(string)
		schedule, _ := values["schedule"].(string)
		if !allowedStream(stream) || stream == "all" || !allowedSchedule(schedule) {
			return nil, errors.New("horaire refusé")
		}
		return []string{"sync", "schedule", stream, schedule}, nil
	case "server.announce":
		message, _ := values["message"].(string)
		if strings.TrimSpace(message) == "" || len(message) > 240 || strings.ContainsAny(message, "\r\n") {
			return nil, errors.New("annonce refusée")
		}
		return []string{"announce", message}, nil
	case "server.backup":
		return []string{"backup"}, nil
	case "server.update":
		return nil, errors.New("mise à jour Palworld réservée à une session sudo interactive")
	case "season.activate", "season.archive":
		seasonID, _ := values["seasonId"].(string)
		slug, _ := values["slug"].(string)
		if !safeSeasonToken(seasonID) || !safeSeasonToken(slug) {
			return nil, errors.New("saison refusée")
		}
		action := strings.TrimPrefix(command.Kind, "season.")
		return []string{"season", action, seasonID, slug}, nil
	case "service.restart":
		unit, _ := values["unit"].(string)
		if !allowedUnit(unit) {
			return nil, errors.New("unité refusée")
		}
		if unit == "palworld.service" {
			return nil, errors.New("redémarrage Palworld réservé à une session sudo interactive")
		}
		return []string{"restart", unit}, nil
	default:
		return nil, errors.New("commande inconnue")
	}
}

func safeSeasonToken(value string) bool {
	if value == "" || len(value) > 128 {
		return false
	}
	for _, r := range value {
		if (r < 'a' || r > 'z') && (r < '0' || r > '9') && r != '-' {
			return false
		}
	}
	return true
}

func allowedSchedule(schedule string) bool {
	switch schedule {
	case "30s", "1m", "5m", "30m", "2h":
		return true
	default:
		return false
	}
}

func allowedUnit(unit string) bool {
	switch unit {
	case "gaylemon-agent.service", "gaylemon-collect-metrics.service", "gaylemon-collect-stats.service", "gaylemon-publish-events.service", "gaylemon-publish-snapshot.service", "palworld-stats.service", "palworld-events.service", "palworld-save-snapshot.service", "palworld-welcome.service":
		return true
	default:
		return false
	}
}

func allowedStream(stream string) bool {
	switch stream {
	case "metrics", "stats", "events", "snapshot", "all":
		return true
	default:
		return false
	}
}
