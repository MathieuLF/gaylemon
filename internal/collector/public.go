package collector

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"sort"
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
	EventsRecovery   string
	RecentEventsPath string
	SnapshotPath     string
	BasesPath        string
	DiagnosticsPath  string
	CatalogManifest  string
	CatalogsRoot     string
}

func PublicConfigFromEnv() PublicConfig {
	return PublicConfig{
		StatsPath:        env("GAYLEMON_STATS_PATH", "runtime/input/stats.json"),
		APIHelper:        env("GAYLEMON_PALWORLD_API_HELPER", ""),
		UseSudo:          boolEnv("GAYLEMON_PALWORLD_API_SUDO", false),
		StatsSudo:        boolEnv("GAYLEMON_STATS_SUDO", false),
		EventsPath:       env("GAYLEMON_EVENTS_PATH", "runtime/input/public-events.json"),
		EventsRecovery:   env("GAYLEMON_EVENTS_RECOVERY_PATH", "runtime/input/events-recovery.json"),
		RecentEventsPath: env("GAYLEMON_RECENT_EVENTS_PATH", "runtime/input/public-events-recent.json"),
		SnapshotPath:     env("GAYLEMON_SNAPSHOT_PATH", "runtime/input/public-save-snapshot.json"),
		BasesPath:        env("GAYLEMON_BASES_PATH", "runtime/input/public-save-bases.json"),
		DiagnosticsPath:  env("GAYLEMON_DIAGNOSTICS_PATH", "runtime/input/public-save-diagnostics.json"),
		CatalogManifest:  env("GAYLEMON_CATALOG_MANIFEST_PATH", "runtime/input/public-catalogs-manifest.json"),
		CatalogsRoot:     env("GAYLEMON_CATALOGS_ROOT", "runtime/input/public-catalogs"),
	}
}

func PublicEventsRevision(path string) (string, error) {
	file, err := os.Open(path)
	if err != nil {
		return "", fmt.Errorf("lecture des échos publics: %w", err)
	}
	defer file.Close()

	decoder := json.NewDecoder(io.LimitReader(file, 64<<10))
	token, err := decoder.Token()
	if err != nil || token != json.Delim('{') {
		return "", errors.New("enveloppe des échos publics invalide")
	}
	for decoder.More() {
		key, err := decoder.Token()
		if err != nil {
			return "", errors.New("révision des échos publics illisible")
		}
		if key == "revision" {
			var revision string
			if err := decoder.Decode(&revision); err != nil || strings.TrimSpace(revision) == "" {
				return "", errors.New("révision des échos publics invalide")
			}
			return revision, nil
		}
		var ignored json.RawMessage
		if err := decoder.Decode(&ignored); err != nil {
			return "", errors.New("révision des échos publics introuvable")
		}
	}
	return "", errors.New("révision des échos publics introuvable")
}

func PublicEventsObservedAt(path string) (time.Time, error) {
	file, err := os.Open(path)
	if err != nil {
		return time.Time{}, fmt.Errorf("lecture du rapport des échos: %w", err)
	}
	defer file.Close()
	var report struct {
		OK        bool   `json:"ok"`
		Status    string `json:"status"`
		CheckedAt string `json:"checkedAt"`
	}
	if err := json.NewDecoder(io.LimitReader(file, 1<<20)).Decode(&report); err != nil {
		return time.Time{}, fmt.Errorf("rapport des échos invalide: %w", err)
	}
	if !report.OK || report.Status != "complete" {
		return time.Time{}, errors.New("dernière collecte des échos incomplète")
	}
	observedAt, err := time.Parse(time.RFC3339Nano, report.CheckedAt)
	if err != nil {
		return time.Time{}, fmt.Errorf("horodatage de collecte invalide: %w", err)
	}
	return observedAt, nil
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
	if kind == "snapshot" {
		return collectPublicSnapshot(ctx, config, started)
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
		publicMetrics := projection.PublicMetrics(metrics, stats)
		content, err := json.Marshal(publicMetrics)
		if err != nil {
			return PublicResult{}, err
		}
		documents = append(documents, model.Document{Path: "data/public-metrics.json", Content: content, CachePolicy: model.CacheNoStore})
		uptime, err := json.Marshal(projection.PublicUptime(publicMetrics))
		if err != nil {
			return PublicResult{}, err
		}
		documents = append(documents, model.Document{Path: "data/public-uptime.json", Content: uptime, CachePolicy: model.CacheNoStore})
	default:
		return PublicResult{}, fmt.Errorf("collecteur inconnu: %s", kind)
	}
	var memory runtime.MemStats
	runtime.ReadMemStats(&memory)
	return PublicResult{Documents: documents, Usage: model.ResourceUsage{DurationMS: time.Since(started).Milliseconds(), MaxRSSBytes: int64(memory.Sys), BytesRead: bytesRead}, Summary: summary}, nil
}

func collectPublicSnapshot(_ context.Context, config PublicConfig, started time.Time) (PublicResult, error) {
	read := func(label, path string) ([]byte, error) {
		content, err := os.ReadFile(path)
		if err != nil {
			return nil, fmt.Errorf("lecture de %s: %w", label, err)
		}
		return content, nil
	}
	snapshotBytes, err := read("la sauvegarde publique intermédiaire", config.SnapshotPath)
	if err != nil {
		return PublicResult{}, err
	}
	basesBytes, err := read("la projection des bases", config.BasesPath)
	if err != nil {
		return PublicResult{}, err
	}
	diagnosticsBytes, err := read("le diagnostic de sauvegarde", config.DiagnosticsPath)
	if err != nil {
		return PublicResult{}, err
	}
	documents, err := projection.SaveDocuments(snapshotBytes, basesBytes, diagnosticsBytes)
	if err != nil {
		return PublicResult{}, err
	}
	if len(documents) == 0 {
		return PublicResult{}, fmt.Errorf("la projection de sauvegarde est vide")
	}
	index := documents[len(documents)-1]
	documents = documents[:len(documents)-1]
	bytesRead := int64(len(snapshotBytes) + len(basesBytes) + len(diagnosticsBytes))

	manifestBytes, err := read("le manifeste des catalogues", config.CatalogManifest)
	if err != nil {
		return PublicResult{}, err
	}
	if !json.Valid(manifestBytes) {
		return PublicResult{}, fmt.Errorf("manifeste des catalogues invalide")
	}
	manifest, err := projection.DecodeObject(manifestBytes)
	if err != nil || !booleanValue(manifest["ok"]) {
		return PublicResult{}, fmt.Errorf("manifeste des catalogues incomplet")
	}
	catalogGeneration := strings.TrimSpace(fmt.Sprint(manifest["generationId"]))
	if catalogGeneration == "" || strings.ContainsAny(catalogGeneration, "/\\") {
		return PublicResult{}, fmt.Errorf("génération des catalogues invalide")
	}
	documents = append(documents, model.Document{Path: "data/public-catalogs-manifest.json", Content: manifestBytes, CachePolicy: model.CacheRevalidate, GenerationID: catalogGeneration})
	bytesRead += int64(len(manifestBytes))

	var catalogDocuments []model.Document
	err = filepath.WalkDir(config.CatalogsRoot, func(path string, entry fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		if entry.IsDir() || !strings.EqualFold(filepath.Ext(entry.Name()), ".json") || strings.HasSuffix(strings.ToLower(entry.Name()), ".example.json") {
			return nil
		}
		relative, err := filepath.Rel(config.CatalogsRoot, path)
		if err != nil {
			return err
		}
		content, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		if !json.Valid(content) {
			return fmt.Errorf("catalogue JSON invalide: %s", path)
		}
		bytesRead += int64(len(content))
		catalogDocuments = append(catalogDocuments, model.Document{Path: "data/public-catalogs/" + filepath.ToSlash(relative), Content: content, CachePolicy: model.CacheRevalidate, GenerationID: catalogGeneration})
		return nil
	})
	if err != nil {
		return PublicResult{}, fmt.Errorf("lecture des catalogues: %w", err)
	}
	sort.Slice(catalogDocuments, func(i, j int) bool { return catalogDocuments[i].Path < catalogDocuments[j].Path })
	documents = append(documents, catalogDocuments...)
	// L'index reste le dernier pointeur publié, après les données lourdes.
	documents = append(documents, index)

	var memory runtime.MemStats
	runtime.ReadMemStats(&memory)
	return PublicResult{
		Documents: documents,
		Usage:     model.ResourceUsage{DurationMS: time.Since(started).Milliseconds(), MaxRSSBytes: int64(memory.Sys), BytesRead: bytesRead},
		Summary:   map[string]any{"collector": "save-public-projection", "kind": "snapshot", "documents": len(documents)},
	}, nil
}

func booleanValue(value any) bool {
	if typed, ok := value.(bool); ok {
		return typed
	}
	return strings.EqualFold(strings.TrimSpace(fmt.Sprint(value)), "true")
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
	sourceRevision, eventCount, err := projection.ValidatePublicEvents(fullBytes)
	if err != nil {
		return PublicResult{}, fmt.Errorf("échos publics invalides: %w", err)
	}
	if !json.Valid(recentBytes) {
		return PublicResult{}, errors.New("échos publics récents invalides")
	}
	documents := []model.Document{
		model.Document{Path: "data/public-events.json", Content: fullBytes, CachePolicy: model.CacheNoStore},
		model.Document{Path: "data/public-events-recent.json", Content: recentBytes, CachePolicy: model.CacheNoStore},
	}
	var memory runtime.MemStats
	runtime.ReadMemStats(&memory)
	return PublicResult{
		Documents: documents,
		Usage:     model.ResourceUsage{DurationMS: time.Since(started).Milliseconds(), MaxRSSBytes: int64(memory.Sys), BytesRead: int64(len(fullBytes) + len(recentBytes))},
		Summary:   map[string]any{"collector": "events-postgresql", "kind": "events", "documents": len(documents), "revision": sourceRevision, "sourceRevision": sourceRevision, "events": eventCount},
	}, nil
}

func readStats(ctx context.Context, config PublicConfig) ([]byte, error) {
	if config.StatsSudo {
		output, err := exec.CommandContext(ctx, "sudo", "-n", "cat", config.StatsPath).Output()
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
			executable = "sudo"
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
