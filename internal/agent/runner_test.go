package agent

import (
	"context"
	"crypto/ed25519"
	"crypto/rand"
	"encoding/json"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"testing"
	"time"

	"github.com/MathieuLF/gaylemon/internal/model"
)

func TestSeasonArchiveDrainsSpoolWhileCommandRuns(t *testing.T) {
	_, privateKey, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/api/ingest/v1/batches" {
			http.NotFound(w, r)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"batchId":"batch-1","status":"active","documents":1,"activeSequence":1}`))
	}))
	defer server.Close()
	spool, err := OpenSpool(filepath.Join(t.TempDir(), "spool.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer spool.Close()
	payload, _ := json.Marshal(model.BatchPayload{Documents: []model.Document{{Path: "data/public-stats.json", Content: json.RawMessage(`{"ok":true}`), CachePolicy: model.CacheNoStore}}})
	if err := spool.Enqueue(context.Background(), &model.Batch{ID: "batch-1", AgentID: "agent", Stream: "stats", SchemaVersion: 1, CapturedAt: time.Now(), Payload: payload}); err != nil {
		t.Fatal(err)
	}
	client := NewClient(Config{APIBaseURL: server.URL, PrivateKey: privateKey, HTTPTimeout: time.Second})
	runner := &Runner{Spool: spool, Client: client, Logger: slog.Default(), CommandDrainInterval: 10 * time.Millisecond}
	execute := func(ctx context.Context, _ model.Command) model.CommandAck {
		deadline := time.NewTimer(time.Second)
		defer deadline.Stop()
		for {
			depth, err := spool.Depth(ctx)
			if err != nil {
				return model.CommandAck{Status: "failed", Message: err.Error()}
			}
			if depth == 0 {
				return model.CommandAck{Status: "completed"}
			}
			select {
			case <-ctx.Done():
				return model.CommandAck{Status: "failed", Message: ctx.Err().Error()}
			case <-deadline.C:
				return model.CommandAck{Status: "failed", Message: "file non vidée"}
			case <-time.After(5 * time.Millisecond):
			}
		}
	}
	ack := runner.executeCommand(context.Background(), model.Command{ID: "archive", Kind: "season.archive"}, execute)
	if ack.Status != "completed" {
		t.Fatalf("clôture bloquée: %#v", ack)
	}
	if depth, err := spool.Depth(context.Background()); err != nil || depth != 0 {
		t.Fatalf("file finale: depth=%d err=%v", depth, err)
	}
}
