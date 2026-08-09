package agent

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
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
	timeout := e.Timeout
	if timeout <= 0 {
		timeout = 2 * time.Minute
	}
	commandContext, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()
	executable := e.Helper
	processArguments := arguments
	if e.UseSudo {
		executable = "/usr/bin/sudo"
		processArguments = append([]string{"-n", e.Helper}, arguments...)
	}
	process := exec.CommandContext(commandContext, executable, processArguments...)
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
	return model.CommandAck{Status: "completed", Message: message}
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
		return []string{"release", "update"}, nil
	case "service.restart":
		unit, _ := values["unit"].(string)
		allowPalworld, _ := values["allowPalworldRestart"].(bool)
		if !allowedUnit(unit) {
			return nil, errors.New("unité refusée")
		}
		if unit == "palworld.service" && !allowPalworld {
			return nil, errors.New("redémarrage Palworld non confirmé")
		}
		return []string{"restart", unit, fmt.Sprintf("%t", allowPalworld)}, nil
	default:
		return nil, errors.New("commande inconnue")
	}
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
	case "gaylemon-agent.service", "gaylemon-collect-metrics.service", "gaylemon-collect-stats.service", "gaylemon-publish-events.service", "gaylemon-publish-snapshot.service", "palworld-stats.service", "palworld-events.service", "palworld-save-snapshot.service", "palworld.service":
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
