//go:build integration

package store

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/MathieuLF/gaylemon/internal/background"
	"github.com/MathieuLF/gaylemon/internal/model"
	"github.com/riverqueue/river"
)

func TestPostgresIngestionLifecycle(t *testing.T) {
	databaseURL := os.Getenv("GAYLEMON_TEST_DATABASE_URL")
	if databaseURL == "" {
		t.Skip("GAYLEMON_TEST_DATABASE_URL absent")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()
	repository, err := OpenPostgres(ctx, databaseURL)
	if err != nil {
		t.Fatal(err)
	}
	defer repository.Close()
	if err := repository.Migrate(ctx); err != nil {
		t.Fatal(err)
	}
	if err := repository.ClaimNonce(ctx, "integration", "nonce-1234567890123456", time.Now().Add(time.Minute)); err != nil {
		t.Fatal(err)
	}
	if err := repository.ClaimNonce(ctx, "integration", "nonce-1234567890123456", time.Now().Add(time.Minute)); err != ErrReplay {
		t.Fatalf("rejeu inattendu: %v", err)
	}
	payload, err := json.Marshal(model.BatchPayload{
		Documents: []model.Document{{Path: "data/public-stats.json", Content: json.RawMessage(`{"ok":true,"players":[]}`), CachePolicy: model.CacheRevalidate}},
		Usage:     model.ResourceUsage{DurationMS: 42, MaxRSSBytes: 1024, BytesRead: 24, BytesSent: 512},
	})
	if err != nil {
		t.Fatal(err)
	}
	batch := model.Batch{ID: "integration-batch", AgentID: "integration", Stream: "stats", SchemaVersion: 1, Sequence: 1, CapturedAt: time.Now().UTC(), Payload: payload}
	result, err := repository.IngestBatch(ctx, batch, "integration-hash", true)
	if err != nil {
		t.Fatal(err)
	}
	if result.Status != "active" || result.Documents != 1 {
		t.Fatalf("résultat inattendu: %#v", result)
	}
	document, found, err := repository.GetPublicDocument(ctx, "data/public-stats.json")
	if err != nil || !found || !json.Valid(document.Content) {
		t.Fatalf("document absent: found=%v err=%v", found, err)
	}
	if string(document.Content) != `{"ok":true,"players":[]}` {
		t.Fatalf("octets JSON modifiés: %q", document.Content)
	}
	eventsDocument := json.RawMessage(`{"ok":true,"revision":"events-integration-1","updatedAt":"2026-08-08T21:49:00-04:00","summary":{"totalEchoes":2},"events":[{"key":"evt-2","id":2,"occurredAt":"2026-08-08T21:49:00-04:00","type":"craft","player":"MathieuLF","title":"Fabrications terminées","message":"Deux fabrications.","details":{"types":["craft"]}},{"key":"evt-1","id":1,"occurredAt":"2026-08-08T21:48:00-04:00","type":"capture","player":"Sprince","title":"Première capture","message":"Une capture.","details":{}}]}`)
	eventsPayload, err := json.Marshal(model.BatchPayload{Documents: []model.Document{
		{Path: "data/public-events.json", Content: eventsDocument, CachePolicy: model.CacheNoStore},
		{Path: "data/public-events-head-v6.json", Content: json.RawMessage(`{"ok":true,"manifest":{"path":"data/public-events-v6/g-old/manifest.json"}}`), CachePolicy: model.CacheRevalidate, GenerationID: "g-old"},
		{Path: "data/public-events-v6/g-old/manifest.json", Content: json.RawMessage(`{"ok":true,"generationId":"g-old"}`), CachePolicy: model.CacheImmutable, GenerationID: "g-old"},
		{Path: "data/public-events-v6/d-old/2026-08-08.json", Content: json.RawMessage(`{"ok":true,"events":[]}`), CachePolicy: model.CacheImmutable, GenerationID: "d-old"},
		{Path: "data/public-daily/d-old/2026-08-08.json", Content: json.RawMessage(`{"ok":true,"events":[]}`), CachePolicy: model.CacheImmutable, GenerationID: "d-old"},
	}})
	if err != nil {
		t.Fatal(err)
	}
	eventsBatch := model.Batch{ID: "integration-events-batch", AgentID: "integration", Stream: "events", SchemaVersion: 1, Sequence: 1, CapturedAt: time.Now().UTC(), Payload: eventsPayload}
	if _, err := repository.IngestBatch(ctx, eventsBatch, "integration-events-hash", true); err != nil {
		t.Fatal(err)
	}
	nextEventsPayload, err := json.Marshal(model.BatchPayload{Documents: []model.Document{
		{Path: "data/public-events.json", Content: eventsDocument, CachePolicy: model.CacheNoStore},
		{Path: "data/public-events-recent.json", Content: json.RawMessage(`{"ok":true,"revision":"recent-current","events":[]}`), CachePolicy: model.CacheNoStore},
	}})
	if err != nil {
		t.Fatal(err)
	}
	nextEventsBatch := model.Batch{ID: "integration-events-batch-current", AgentID: "integration", Stream: "events", SchemaVersion: 1, Sequence: 2, CapturedAt: time.Now().UTC(), Payload: nextEventsPayload}
	if _, err := repository.IngestBatch(ctx, nextEventsBatch, "integration-events-hash-current", true); err != nil {
		t.Fatal(err)
	}
	eventsPage, found, err := repository.QueryPublicEvents(ctx, model.PublicEventQuery{Limit: 10, Type: "craft"})
	if err != nil || !found || eventsPage.Source != "postgresql" || eventsPage.Total != 1 || len(eventsPage.Events) != 1 {
		t.Fatalf("projection relationnelle absente: found=%v page=%#v err=%v", found, eventsPage, err)
	}
	dayLocation := time.FixedZone("America/Toronto", -4*60*60)
	dayStart := time.Date(2026, time.August, 8, 0, 0, 0, 0, dayLocation)
	dayPage, found, err := repository.QueryPublicEvents(ctx, model.PublicEventQuery{
		Limit: 1000, Day: "2026-08-08", From: dayStart, Before: dayStart.AddDate(0, 0, 1),
	})
	if err != nil || !found || dayPage.Date != "2026-08-08" || dayPage.Limit != 500 || dayPage.Total != 2 || len(dayPage.Events) != 2 {
		t.Fatalf("projection journalière absente: found=%v page=%#v err=%v", found, dayPage, err)
	}
	var eventVersions int
	if err := repository.pool.QueryRow(ctx, `SELECT count(*) FROM gaylemon_public.document_versions WHERE stream='events'`).Scan(&eventVersions); err != nil {
		t.Fatal(err)
	}
	if eventVersions != 0 {
		t.Fatalf("versions JSON d'événements conservées: %d", eventVersions)
	}
	var activeFallbackDocuments int
	if err := repository.pool.QueryRow(ctx, `SELECT count(*) FROM gaylemon_public.documents
		WHERE path LIKE 'data/public-events-v6/%' OR path LIKE 'data/public-daily/%'`).Scan(&activeFallbackDocuments); err != nil {
		t.Fatal(err)
	}
	if activeFallbackDocuments != 0 {
		t.Fatalf("génération JSON active incohérente: %d documents", activeFallbackDocuments)
	}
	if _, found, err := repository.GetPublicDocument(ctx, "data/public-events-v6/d-old/2026-08-08.json"); err != nil || found {
		t.Fatalf("ancienne génération JSON encore active: found=%v err=%v", found, err)
	}
	if _, found, err := repository.GetPublicDocument(ctx, "data/public-events.json"); err != nil || found {
		t.Fatalf("export complet encore conservé: found=%v err=%v", found, err)
	}
	if _, found, err := repository.GetPublicDocument(ctx, "data/public-events-recent.json"); err != nil || !found {
		t.Fatalf("repli récent absent: found=%v err=%v", found, err)
	}
	snapshot, err := repository.Dashboard(ctx)
	if err != nil || len(snapshot.RecentRuns) == 0 || snapshot.DatabaseBytes <= 0 {
		t.Fatalf("tableau incomplet: %#v err=%v", snapshot, err)
	}
	maintenance, err := repository.Maintain(ctx)
	if err != nil || !json.Valid(maintenance) {
		t.Fatalf("entretien invalide: %s err=%v", maintenance, err)
	}

	logger := slog.New(slog.NewTextHandler(io.Discard, nil))
	if err := background.Migrate(ctx, repository.Pool(), logger); err != nil {
		t.Fatal(err)
	}
	var jobTables int
	if err := repository.pool.QueryRow(ctx, `SELECT count(*) FROM information_schema.tables
		WHERE table_schema='gaylemon_ops' AND table_name IN ('river_job', 'river_queue', 'river_migration')`).Scan(&jobTables); err != nil {
		t.Fatal(err)
	}
	if jobTables != 3 {
		t.Fatalf("tables de travaux absentes: %d/3", jobTables)
	}

	jobClient, err := background.NewClient(repository.Pool(), repository, logger)
	if err != nil {
		t.Fatal(err)
	}
	completed, unsubscribe := jobClient.Subscribe(river.EventKindJobCompleted)
	defer unsubscribe()
	if err := jobClient.Start(ctx); err != nil {
		t.Fatal(err)
	}
	defer func() {
		stopContext, stop := context.WithTimeout(context.Background(), 20*time.Second)
		defer stop()
		if err := jobClient.Stop(stopContext); err != nil {
			t.Errorf("arrêt des travaux: %v", err)
		}
	}()
	select {
	case event := <-completed:
		if event.Job == nil || event.Job.Kind != "database_maintenance" || event.Job.Queue != "maintenance" {
			t.Fatalf("travail terminé inattendu: %#v", event.Job)
		}
	case <-time.After(15 * time.Second):
		t.Fatal("le travail d'entretien initial n'a pas terminé")
	}
	var completedMaintenanceJobs int
	if err := repository.pool.QueryRow(ctx, `SELECT count(*) FROM gaylemon_ops.river_job
		WHERE kind='database_maintenance' AND queue='maintenance' AND state='completed'`).Scan(&completedMaintenanceJobs); err != nil {
		t.Fatal(err)
	}
	if completedMaintenanceJobs != 1 {
		t.Fatalf("travaux d'entretien terminés: %d, attendu 1", completedMaintenanceJobs)
	}
}

func TestSeasonArchivePreservesProjectionsAndIsolatesNextSequences(t *testing.T) {
	databaseURL := os.Getenv("GAYLEMON_TEST_DATABASE_URL")
	if databaseURL == "" {
		t.Skip("GAYLEMON_TEST_DATABASE_URL absent")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()
	repository, err := OpenPostgres(ctx, databaseURL)
	if err != nil {
		t.Fatal(err)
	}
	defer repository.Close()
	if err := repository.Migrate(ctx); err != nil {
		t.Fatal(err)
	}
	active, found, err := repository.ResolveSeason(ctx, "")
	if err != nil || !found || active.State != model.SeasonActive {
		t.Fatalf("saison active absente: %#v found=%v err=%v", active, found, err)
	}
	if err := repository.UpsertHeartbeat(ctx, model.AgentStatus{AgentID: "season-agent", Version: "test"}); err != nil {
		t.Fatal(err)
	}
	expiredCommand, err := repository.BeginSeasonArchive(ctx, active.ID, "season-agent", "archive-expired-"+active.ID, "integration", time.Now().Add(-time.Minute))
	if err != nil {
		t.Fatal(err)
	}
	recoveryCommands, err := repository.PendingCommands(ctx, "season-agent", expiredCommand.Sequence-1)
	if err != nil {
		t.Fatal(err)
	}
	if len(recoveryCommands) != 1 || recoveryCommands[0].Kind != "season.activate" || !strings.Contains(string(recoveryCommands[0].Arguments), `"transition": "recover"`) {
		t.Fatalf("commande compensatoire absente: %#v", recoveryCommands)
	}
	active, found, err = repository.ResolveSeason(ctx, active.Slug)
	if err != nil || !found || active.State != model.SeasonFinalizing {
		t.Fatalf("archive expirée non maintenue en récupération: %#v found=%v err=%v", active, found, err)
	}
	if err := repository.AckCommand(ctx, "season-agent", recoveryCommands[0].ID, model.CommandAck{Status: "completed", Details: json.RawMessage(`{"seasonId":"season-2026","slug":"saison-2026","activated":true,"palworldPid":"4242","palworldRestarts":"0"}`)}); err != nil {
		t.Fatal(err)
	}
	active, found, err = repository.ResolveSeason(ctx, active.Slug)
	if err != nil || !found || active.State != model.SeasonActive {
		t.Fatalf("récupération compensatoire non confirmée: %#v found=%v err=%v", active, found, err)
	}
	expiredCommand, err = repository.BeginSeasonArchive(ctx, active.ID, "season-agent", "archive-expired-bounded-"+active.ID, "integration", time.Now().Add(-time.Minute))
	if err != nil {
		t.Fatal(err)
	}
	recoveryCommands, err = repository.PendingCommands(ctx, "season-agent", expiredCommand.Sequence-1)
	if err != nil || len(recoveryCommands) != 1 {
		t.Fatalf("seconde compensation absente: %#v err=%v", recoveryCommands, err)
	}
	if _, err := repository.pool.Exec(ctx, `UPDATE gaylemon_ops.control_commands SET expires_at=now()-interval '1 minute' WHERE command_id=$1`, recoveryCommands[0].ID); err != nil {
		t.Fatal(err)
	}
	if _, err := repository.Maintain(ctx); err != nil {
		t.Fatal(err)
	}
	var recoveryState model.SeasonState
	if err := repository.pool.QueryRow(ctx, `SELECT state FROM gaylemon_ops.seasons WHERE season_id=$1`, active.ID).Scan(&recoveryState); err != nil || recoveryState != model.SeasonFailed {
		t.Fatalf("expiration compensatoire non bornée: state=%s err=%v", recoveryState, err)
	}
	recoveredSeason, recoveryCommand, err := repository.ReopenSeason(ctx, active.ID, "season-agent", "recover-manual-"+active.ID, "integration", time.Now().Add(time.Minute))
	if err != nil || recoveredSeason.State != model.SeasonFailed {
		t.Fatalf("reprise opérateur impossible: %#v err=%v", recoveredSeason, err)
	}
	if err := repository.AckCommand(ctx, "season-agent", recoveryCommand.ID, model.CommandAck{Status: "completed", Details: json.RawMessage(`{"seasonId":"season-2026","slug":"saison-2026","activated":true,"palworldPid":"4242","palworldRestarts":"0"}`)}); err != nil {
		t.Fatal(err)
	}
	active, found, err = repository.ResolveSeason(ctx, active.Slug)
	if err != nil || !found || active.State != model.SeasonActive {
		t.Fatalf("reprise opérateur non confirmée: %#v found=%v err=%v", active, found, err)
	}
	failedCommand, err := repository.BeginSeasonArchive(ctx, active.ID, "season-agent", "archive-failed-"+active.ID, "integration", time.Now().Add(time.Minute))
	if err != nil {
		t.Fatal(err)
	}
	if err := repository.AckCommand(ctx, "season-agent", failedCommand.ID, model.CommandAck{Status: "failed", Message: "sauvegarde finale impossible"}); err != nil {
		t.Fatal(err)
	}
	active, found, err = repository.ResolveSeason(ctx, active.Slug)
	if err != nil || !found || active.State != model.SeasonActive {
		t.Fatalf("échec d'archive non restauré: %#v found=%v err=%v", active, found, err)
	}
	command, err := repository.BeginSeasonArchive(ctx, active.ID, "season-agent", "archive-"+active.ID, "integration", time.Now().Add(time.Hour))
	if err != nil {
		t.Fatal(err)
	}
	if err := repository.AckCommand(ctx, "season-agent", command.ID, model.CommandAck{Status: "completed", Details: json.RawMessage(`{"seasonId":"season-2026","slug":"saison-2026","immutableBackup":"urn:gaylemon:season-archive:saison-2026:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","backupSha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","receipt":"urn:gaylemon:season-receipt:saison-2026:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","receiptSha256":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","queueDepth":0,"palworldPid":"4242","palworldRestarts":"0"}`)}); err != nil {
		t.Fatal(err)
	}
	archived, found, err := repository.ResolveSeason(ctx, active.Slug)
	if err != nil || !found || archived.State != model.SeasonArchived || len(archived.FinalSHA256) != 64 || !json.Valid(archived.Manifest) {
		t.Fatalf("archive non scellée: %#v found=%v err=%v", archived, found, err)
	}
	emptyPayload, _ := json.Marshal(model.BatchPayload{Documents: []model.Document{{Path: "data/public-stats.json", Content: json.RawMessage(`{"ok":true}`), CachePolicy: model.CacheNoStore}}})
	if _, err := repository.IngestBatch(ctx, model.Batch{ID: "blocked-" + active.ID, AgentID: "season-agent", Stream: "stats", SchemaVersion: 1, Sequence: 999, CapturedAt: time.Now(), Payload: emptyPayload}, "blocked", true); !errors.Is(err, ErrSeasonArchived) {
		t.Fatalf("ingestion après archive: %v", err)
	}
	reopened, activateCommand, err := repository.ReopenSeason(ctx, active.ID, "season-agent", "reopen-activate-"+active.ID, "integration", time.Now().Add(time.Minute))
	if err != nil || reopened.State != model.SeasonArchived || activateCommand.Kind != "season.activate" {
		t.Fatalf("réouverture sans réactivation agent: %#v command=%#v err=%v", reopened, activateCommand, err)
	}
	if err := repository.AckCommand(ctx, "season-agent", activateCommand.ID, model.CommandAck{Status: "completed", Details: json.RawMessage(`{"seasonId":"season-2026","slug":"saison-2026","activated":true,"palworldPid":"4242","palworldRestarts":"0"}`)}); err != nil {
		t.Fatal(err)
	}
	reopened, found, err = repository.ResolveSeason(ctx, active.Slug)
	if err != nil || !found || reopened.State != model.SeasonActive {
		t.Fatalf("réouverture non confirmée après acquittement: %#v err=%v", reopened, err)
	}
	command, err = repository.BeginSeasonArchive(ctx, active.ID, "season-agent", "archive-again-"+active.ID, "integration", time.Now().Add(time.Hour))
	if err != nil {
		t.Fatal(err)
	}
	if err := repository.AckCommand(ctx, "season-agent", command.ID, model.CommandAck{Status: "completed", Details: json.RawMessage(`{"seasonId":"season-2026","slug":"saison-2026","immutableBackup":"urn:gaylemon:season-archive:saison-2026:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","backupSha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","receipt":"urn:gaylemon:season-receipt:saison-2026:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","receiptSha256":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","queueDepth":0,"palworldPid":"4242","palworldRestarts":"0"}`)}); err != nil {
		t.Fatal(err)
	}
	suffix := time.Now().UTC().Format("20060102-150405000000000")
	next, err := repository.CreateSeason(ctx, model.SeasonCreate{Slug: "saison-" + suffix, Title: "Saison suivante", StartsOn: time.Now().UTC().Format(time.DateOnly)}, "integration")
	if err != nil {
		t.Fatal(err)
	}
	next, failedActivation, err := repository.ActivateSeasonWithCommand(ctx, next.ID, "season-agent", "activate-failed-"+next.ID, "integration", time.Now().Add(time.Minute))
	if err != nil || next.State != model.SeasonDraft {
		t.Fatalf("préparation de l'échec d'activation: %#v err=%v", next, err)
	}
	if _, _, err := repository.ActivateSeasonWithCommand(ctx, next.ID, "season-agent", "activate-duplicate-"+next.ID, "integration", time.Now().Add(time.Minute)); !errors.Is(err, ErrSeasonConflict) {
		t.Fatalf("activation concurrente acceptée: %v", err)
	}
	if err := repository.AckCommand(ctx, "season-agent", failedActivation.ID, model.CommandAck{Status: "failed", Message: "timers indisponibles"}); err != nil {
		t.Fatal(err)
	}
	var nextState model.SeasonState
	if err := repository.pool.QueryRow(ctx, `SELECT state FROM gaylemon_ops.seasons WHERE season_id=$1`, next.ID).Scan(&nextState); err != nil || nextState != model.SeasonFailed {
		t.Fatalf("échec d'activation non reflété: state=%s err=%v", nextState, err)
	}
	next, nextCommand, err := repository.ActivateSeasonWithCommand(ctx, next.ID, "season-agent", "activate-"+next.ID, "integration", time.Now().Add(time.Minute))
	if err != nil || next.State != model.SeasonFailed || nextCommand.Kind != "season.activate" {
		t.Fatalf("préparation de l'activation suivante: %#v command=%#v err=%v", next, nextCommand, err)
	}
	nextProof, _ := json.Marshal(map[string]any{"seasonId": next.ID, "slug": next.Slug, "activated": true, "palworldPid": "4242", "palworldRestarts": "0"})
	if err := repository.AckCommand(ctx, "season-agent", nextCommand.ID, model.CommandAck{Status: "completed", Details: nextProof}); err != nil {
		t.Fatal(err)
	}
	next, found, err = repository.ResolveSeason(ctx, next.Slug)
	if err != nil || !found || next.State != model.SeasonActive {
		t.Fatalf("activation suivante: %#v found=%v err=%v", next, found, err)
	}
	newPayload, _ := json.Marshal(model.BatchPayload{Documents: []model.Document{{Path: "data/public-stats.json", Content: json.RawMessage(`{"ok":true,"season":"next"}`), CachePolicy: model.CacheNoStore}}})
	newBatch := model.Batch{ID: "next-" + next.ID, AgentID: "season-agent", Stream: "stats", SchemaVersion: 1, Sequence: 1, CapturedAt: time.Now(), Payload: newPayload}
	if _, err := repository.IngestBatch(ctx, newBatch, "next-hash", true); err != nil {
		t.Fatal(err)
	}
	document, found, err := repository.GetPublicDocument(ctx, "data/public-stats.json")
	if err != nil || !found || !strings.Contains(string(document.Content), `"next"`) {
		t.Fatalf("projection suivante absente: %s found=%v err=%v", document.Content, found, err)
	}
	if _, found, err := repository.GetPublicDocumentForSeason(ctx, active.Slug, "data/public-stats.json"); err != nil || !found {
		t.Fatalf("projection archivée perdue: found=%v err=%v", found, err)
	}
	if _, _, err := repository.ReopenSeason(ctx, active.ID, "season-agent", "reopen-command", "integration", time.Now().Add(time.Minute)); !errors.Is(err, ErrSeasonConflict) {
		t.Fatalf("ancienne saison rouverte malgré la suivante: %v", err)
	}
	if _, err := repository.pool.Exec(ctx, `UPDATE gaylemon_ops.season_lifecycle_events SET actor='tampered' WHERE season_id=$1`, active.ID); err == nil {
		t.Fatal("le journal de cycle de vie aurait dû être append-only")
	}
}
