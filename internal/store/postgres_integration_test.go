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
	snapshot, err := repository.Dashboard(ctx)
	if err != nil || len(snapshot.RecentRuns) == 0 || snapshot.DatabaseBytes <= 0 {
		t.Fatalf("tableau incomplet: %#v err=%v", snapshot, err)
	}
	maintenance, err := repository.Maintain(ctx)
	if err != nil || !json.Valid(maintenance) {
		t.Fatalf("entretien invalide: %s err=%v", maintenance, err)
	}
}
