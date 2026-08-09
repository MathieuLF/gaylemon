package agent

import (
	"context"
	"encoding/json"
	"path/filepath"
	"testing"
	"time"

	"github.com/MathieuLF/gaylemon/internal/model"
)

func TestSpoolKeepsOrderAndFailures(t *testing.T) {
	spool, err := OpenSpool(filepath.Join(t.TempDir(), "spool.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer spool.Close()
	ctx := context.Background()
	for _, id := range []string{"first", "second"} {
		batch := model.Batch{ID: id, AgentID: "test", Stream: "stats", CapturedAt: time.Now(), Payload: json.RawMessage(`{}`)}
		if err := spool.Enqueue(ctx, &batch); err != nil {
			t.Fatal(err)
		}
	}
	pending, found, err := spool.Peek(ctx)
	if err != nil || !found {
		t.Fatalf("lot attendu: found=%v err=%v", found, err)
	}
	if pending.ID != "first" || pending.Sequence != 1 || !json.Valid(pending.Body) {
		t.Fatalf("premier lot inattendu: %#v", pending)
	}
	if err := spool.Fail(ctx, pending.ID, context.DeadlineExceeded); err != nil {
		t.Fatal(err)
	}
	pending, _, _ = spool.Peek(ctx)
	if pending.Attempts != 1 {
		t.Fatalf("tentatives=%d", pending.Attempts)
	}
	if err := spool.Complete(ctx, pending.ID); err != nil {
		t.Fatal(err)
	}
	pending, found, err = spool.Peek(ctx)
	if err != nil || !found || pending.ID != "second" || pending.Sequence != 2 {
		t.Fatalf("second lot inattendu: %#v found=%v err=%v", pending, found, err)
	}
}

func TestEnqueueDirectoryRejectsPrivateJSON(t *testing.T) {
	root := t.TempDir()
	if err := osWriteFile(filepath.Join(root, "secret.json"), []byte(`{"secret":true}`)); err != nil {
		t.Fatal(err)
	}
	spool, err := OpenSpool(filepath.Join(t.TempDir(), "spool.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer spool.Close()
	if _, err := EnqueueDirectory(context.Background(), spool, "test", "stats", root, "private", ""); err == nil {
		t.Fatal("un chemin privé aurait dû être refusé")
	}
}

func TestCommandResultSurvivesAcknowledgementRetry(t *testing.T) {
	spool, err := OpenSpool(filepath.Join(t.TempDir(), "spool.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer spool.Close()
	ctx := context.Background()
	command := model.Command{ID: "command-1", Sequence: 12}
	want := model.CommandAck{Status: "completed", Message: "ok"}
	if err := spool.SaveCommandResult(ctx, command, want); err != nil {
		t.Fatal(err)
	}
	got, found, err := spool.CommandResult(ctx, command.ID)
	if err != nil || !found || got != want {
		t.Fatalf("résultat perdu: got=%#v found=%v err=%v", got, found, err)
	}
}

func TestSpoolDeduplicatesCompletedSourceRevision(t *testing.T) {
	spool, err := OpenSpool(filepath.Join(t.TempDir(), "spool.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer spool.Close()
	ctx := context.Background()
	document := model.Document{Path: "data/public-events.json", Content: json.RawMessage(`{"ok":true}`), CachePolicy: model.CacheNoStore}
	batches, err := EnqueueDocuments(ctx, spool, "test", "events", "revision-42", []model.Document{document}, model.ResourceUsage{}, nil)
	if err != nil || len(batches) != 1 {
		t.Fatalf("première révision non ajoutée: batches=%d err=%v", len(batches), err)
	}
	repeated, err := EnqueueDocuments(ctx, spool, "test", "events", "revision-42", []model.Document{document}, model.ResourceUsage{}, nil)
	if err != nil || len(repeated) != 0 {
		t.Fatalf("révision en attente dupliquée: batches=%d err=%v", len(repeated), err)
	}
	pending, found, err := spool.Peek(ctx)
	if err != nil || !found {
		t.Fatalf("lot absent: found=%v err=%v", found, err)
	}
	if err := spool.Complete(ctx, pending.ID); err != nil {
		t.Fatal(err)
	}
	repeated, err = EnqueueDocuments(ctx, spool, "test", "events", "revision-42", []model.Document{document}, model.ResourceUsage{}, nil)
	if err != nil || len(repeated) != 0 {
		t.Fatalf("révision terminée dupliquée: batches=%d err=%v", len(repeated), err)
	}
}

func TestSpoolRecognizesLegacyHashedSourceRevision(t *testing.T) {
	spool, err := OpenSpool(filepath.Join(t.TempDir(), "spool.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer spool.Close()
	ctx := context.Background()
	document := model.Document{Path: "data/public-events.json", Content: json.RawMessage(`{"ok":true}`), CachePolicy: model.CacheNoStore}
	batches, err := EnqueueDocuments(ctx, spool, "test", "events", "revision-43:sha256:abcdef", []model.Document{document}, model.ResourceUsage{}, nil)
	if err != nil || len(batches) != 1 {
		t.Fatalf("ancienne révision non ajoutée: batches=%d err=%v", len(batches), err)
	}
	present, err := spool.HasRevision(ctx, "events", "revision-43")
	if err != nil || !present {
		t.Fatalf("ancienne empreinte non reconnue: present=%v err=%v", present, err)
	}
}
