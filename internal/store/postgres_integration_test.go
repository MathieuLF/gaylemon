//go:build integration

package store

import (
	"context"
	"encoding/json"
	"os"
	"testing"
	"time"

	"github.com/MathieuLF/gaylemon/internal/model"
)

func TestPostgresIngestionLifecycle(t *testing.T) {
	databaseURL := os.Getenv("GAYLEMON_TEST_DATABASE_URL")
	if databaseURL == "" {
		t.Skip("GAYLEMON_TEST_DATABASE_URL absent")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
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
	eventsPayload, err := json.Marshal(model.BatchPayload{Documents: []model.Document{{
		Path: "data/public-events.json", Content: eventsDocument, CachePolicy: model.CacheNoStore,
	}}})
	if err != nil {
		t.Fatal(err)
	}
	eventsBatch := model.Batch{ID: "integration-events-batch", AgentID: "integration", Stream: "events", SchemaVersion: 1, Sequence: 1, CapturedAt: time.Now().UTC(), Payload: eventsPayload}
	if _, err := repository.IngestBatch(ctx, eventsBatch, "integration-events-hash", true); err != nil {
		t.Fatal(err)
	}
	eventsPage, found, err := repository.QueryPublicEvents(ctx, model.PublicEventQuery{Limit: 10, Type: "craft"})
	if err != nil || !found || eventsPage.Source != "postgresql" || eventsPage.Total != 1 || len(eventsPage.Events) != 1 {
		t.Fatalf("projection relationnelle absente: found=%v page=%#v err=%v", found, eventsPage, err)
	}
	var mutableEventVersions int
	if err := repository.pool.QueryRow(ctx, `SELECT count(*) FROM gaylemon_public.document_versions WHERE stream='events' AND cache_policy<>'immutable'`).Scan(&mutableEventVersions); err != nil {
		t.Fatal(err)
	}
	if mutableEventVersions != 0 {
		t.Fatalf("versions JSON mutables conservées: %d", mutableEventVersions)
	}
	snapshot, err := repository.Dashboard(ctx)
	if err != nil || len(snapshot.RecentRuns) == 0 || snapshot.DatabaseBytes <= 0 {
		t.Fatalf("tableau incomplet: %#v err=%v", snapshot, err)
	}
	maintenance, err := repository.Maintain(ctx)
	if err != nil || !json.Valid(maintenance) {
		t.Fatalf("entretien invalide: %s err=%v", maintenance, err)
	}
}
