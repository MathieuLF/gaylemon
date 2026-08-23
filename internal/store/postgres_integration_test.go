//go:build integration

package store

import (
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"os"
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
		Limit: 10, Day: "2026-08-08", From: dayStart, Before: dayStart.AddDate(0, 0, 1),
	})
	if err != nil || !found || dayPage.Date != "2026-08-08" || dayPage.Total != 2 || len(dayPage.Events) != 2 {
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
