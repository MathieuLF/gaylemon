package collector

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"runtime"
	"strings"
	"time"

	"github.com/MathieuLF/gaylemon/internal/model"
	"github.com/MathieuLF/gaylemon/internal/projection"
)

type PublicConfig struct {
	StatsPath        string
	APIHelper        string
	UseSudo          bool
	StatsSudo        bool
	EventsPath       string
	RecentEventsPath string
}

func PublicConfigFromEnv() PublicConfig {
	return PublicConfig{
		StatsPath:        env("GAYLEMON_STATS_PATH", "/srv/storage/steam/servers/palworld/stats/stats.json"),
		APIHelper:        env("GAYLEMON_PALWORLD_API_HELPER", "/srv/storage/steam/bin/palworld-api.sh"),
		UseSudo:          boolEnv("GAYLEMON_PALWORLD_API_SUDO", true),
		StatsSudo:        boolEnv("GAYLEMON_STATS_SUDO", true),
		EventsPath:       env("GAYLEMON_EVENTS_PATH", "/home/gaylemon/Gaylemon/runtime/public-events.json"),
		RecentEventsPath: env("GAYLEMON_RECENT_EVENTS_PATH", "/home/gaylemon/Gaylemon/runtime/public-events-recent.json"),
	}
}

type PublicResult struct {
	Documents []model.Document
	Usage     model.ResourceUsage
	Summary   map[string]any
}

func CollectPublic(ctx context.Context, config PublicConfig, kind string) (PublicResult, error) {
	started := time.Now()
	if kind == "events" {
		return collectPublicEvents(ctx, config, started)
	}
	statsBytes, err := readStats(ctx, config)
	if err != nil {
		return PublicResult{}, fmt.Errorf("lecture des statistiques: %w", err)
	}
	stats, err := projection.DecodeObject(statsBytes)
	if err != nil {
		return PublicResult{}, fmt.Errorf("statistiques invalides: %w", err)
	}
	var documents []model.Document
	bytesRead := int64(len(statsBytes))
	summary := map[string]any{"collector": "public-projection", "kind": kind}
	switch kind {
	case "stats":
		content, err := json.Marshal(projection.PublicStats(stats))
		if err != nil {
			return PublicResult{}, err
		}
		documents = append(documents, model.Document{Path: "data/public-stats.json", Content: content, CachePolicy: model.CacheRevalidate})
	case "metrics":
		metrics, apiBytes, apiErr := collectMetricsAPI(ctx, config)
		bytesRead += apiBytes
		if apiErr != nil {
			now := time.Now()
			metrics = map[string]any{"ok": false, "updatedAt": now.Format(time.RFC3339), "updatedAtLocal": now.Format("2006-01-02 15:04:05")}
			summary["sourceError"] = apiErr.Error()
		}
		content, err := json.Marshal(projection.PublicMetrics(metrics, stats))
		if err != nil {
			return PublicResult{}, err
		}
		documents = append(documents, model.Document{Path: "data/public-metrics.json", Content: content, CachePolicy: model.CacheNoStore})
	default:
		return PublicResult{}, fmt.Errorf("collecteur inconnu: %s", kind)
	}
	var memory runtime.MemStats
	runtime.ReadMemStats(&memory)
	return PublicResult{Documents: documents, Usage: model.ResourceUsage{DurationMS: time.Since(started).Milliseconds(), MaxRSSBytes: int64(memory.Sys), BytesRead: bytesRead}, Summary: summary}, nil
}

func collectPublicEvents(_ context.Context, config PublicConfig, started time.Time) (PublicResult, error) {
	fullBytes, err := os.ReadFile(config.EventsPath)
	if err != nil {
		return PublicResult{}, fmt.Errorf("lecture des échos publics: %w", err)
	}
	recentBytes, err := os.ReadFile(config.RecentEventsPath)
	if err != nil {
		return PublicResult{}, fmt.Errorf("lecture des échos récents: %w", err)
	}
	full, err := projection.DecodeObject(fullBytes)
	if err != nil {
		return PublicResult{}, fmt.Errorf("échos publics invalides: %w", err)
	}
	documents, err := projection.EventsV6(full)
	if err != nil {
		return PublicResult{}, err
	}
	documents = append(documents,
		model.Document{Path: "data/public-events.json", Content: fullBytes, CachePolicy: model.CacheNoStore},
		model.Document{Path: "data/public-events-recent.json", Content: recentBytes, CachePolicy: model.CacheNoStore},
	)
	var memory runtime.MemStats
	runtime.ReadMemStats(&memory)
	return PublicResult{
		Documents: documents,
		Usage:     model.ResourceUsage{DurationMS: time.Since(started).Milliseconds(), MaxRSSBytes: int64(memory.Sys), BytesRead: int64(len(fullBytes) + len(recentBytes))},
		Summary:   map[string]any{"collector": "events-v6", "kind": "events", "documents": len(documents), "revision": full["revision"]},
	}, nil
}

func readStats(ctx context.Context, config PublicConfig) ([]byte, error) {
	if config.StatsSudo {
		output, err := exec.CommandContext(ctx, "/usr/bin/sudo", "-n", "/usr/bin/cat", config.StatsPath).Output()
		return output, commandError(err)
	}
	return os.ReadFile(config.StatsPath)
}

func collectMetricsAPI(ctx context.Context, config PublicConfig) (map[string]any, int64, error) {
	responses := map[string]map[string]any{}
	var bytesRead int64
	for _, endpoint := range []string{"metrics", "players", "info"} {
		arguments := []string{"GET", "/" + endpoint}
		executable := config.APIHelper
		if config.UseSudo {
			arguments = append([]string{"-n", config.APIHelper}, arguments...)
			executable = "/usr/bin/sudo"
		}
		output, err := exec.CommandContext(ctx, executable, arguments...).Output()
		if err != nil {
			return nil, bytesRead, fmt.Errorf("API Palworld %s: %w", endpoint, commandError(err))
		}
		bytesRead += int64(len(output))
		decoded, err := projection.DecodeObject(output)
		if err != nil {
			return nil, bytesRead, fmt.Errorf("API Palworld %s invalide: %w", endpoint, err)
		}
		responses[endpoint] = decoded
	}
	now := time.Now()
	metrics := responses["metrics"]
	players := responses["players"]
	info := responses["info"]
	return map[string]any{
		"ok": true, "updatedAt": now.Format(time.RFC3339), "updatedAtLocal": now.Format("2006-01-02 15:04:05"),
		"info": map[string]any{"version": info["version"], "serverName": info["servername"], "description": info["description"]},
		"metrics": map[string]any{
			"players": integer(metrics["currentplayernum"]), "maxPlayers": integer(metrics["maxplayernum"]), "fps": integer(metrics["serverfps"]),
			"fpsAverage": round(number(metrics["serverfpsaverage"]), 1), "frameMs": round(number(metrics["serverframetime"]), 1),
			"days": integer(metrics["days"]), "baseCamps": integer(metrics["basecampnum"]), "uptimeSeconds": integer(metrics["uptime"]),
			"uptime": uptime(integer(metrics["uptime"])),
		},
		"players": players["players"],
	}, bytesRead, nil
}

func commandError(err error) error {
	if err == nil {
		return nil
	}
	if exitError, ok := err.(*exec.ExitError); ok {
		if details := strings.TrimSpace(string(exitError.Stderr)); details != "" {
			return fmt.Errorf("%w: %s", err, details)
		}
	}
	return err
}

func env(name, fallback string) string {
	if value := strings.TrimSpace(os.Getenv(name)); value != "" {
		return value
	}
	return fallback
}

func boolEnv(name string, fallback bool) bool {
	switch strings.ToLower(strings.TrimSpace(os.Getenv(name))) {
	case "1", "true", "yes":
		return true
	case "0", "false", "no":
		return false
	default:
		return fallback
	}
}

func number(value any) float64 {
	switch typed := value.(type) {
	case float64:
		return typed
	case json.Number:
		result, _ := typed.Float64()
		return result
	default:
		return 0
	}
}

func integer(value any) int64 { return int64(number(value)) }

func round(value float64, decimals int) float64 {
	factor := 1.0
	for range decimals {
		factor *= 10
	}
	return float64(int64(value*factor+0.5)) / factor
}

func uptime(seconds int64) string {
	if seconds < 0 {
		seconds = 0
	}
	days := seconds / 86400
	hours := (seconds % 86400) / 3600
	minutes := (seconds % 3600) / 60
	if days > 0 {
		return fmt.Sprintf("%dj %dh", days, hours)
	}
	if hours > 0 {
		return fmt.Sprintf("%dh %dm", hours, minutes)
	}
	return fmt.Sprintf("%dm", minutes)
}
