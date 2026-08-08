package web

import (
	"context"
	"crypto/ed25519"
	"crypto/rand"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/MathieuLF/gaylemon/internal/auth"
	"github.com/MathieuLF/gaylemon/internal/config"
	"github.com/MathieuLF/gaylemon/internal/model"
	"github.com/MathieuLF/gaylemon/internal/store"
)

type fakeRepository struct {
	document model.PublicDocument
	batch    model.Batch
	nonces   map[string]bool
}

func (f *fakeRepository) Close()                        {}
func (f *fakeRepository) Ping(context.Context) error    { return nil }
func (f *fakeRepository) Migrate(context.Context) error { return nil }
func (f *fakeRepository) Maintain(context.Context) (json.RawMessage, error) {
	return json.RawMessage(`{}`), nil
}
func (f *fakeRepository) UpsertHeartbeat(context.Context, model.AgentStatus) error { return nil }
func (f *fakeRepository) AckCommand(context.Context, string, string, model.CommandAck) error {
	return nil
}

func (f *fakeRepository) ClaimNonce(_ context.Context, agentID, nonce string, _ time.Time) error {
	if f.nonces == nil {
		f.nonces = map[string]bool{}
	}
	key := agentID + ":" + nonce
	if f.nonces[key] {
		return store.ErrReplay
	}
	f.nonces[key] = true
	return nil
}

func (f *fakeRepository) IngestBatch(_ context.Context, batch model.Batch, _ string, activate bool) (model.IngestResult, error) {
	if !activate {
		return model.IngestResult{}, errors.New("activation attendue")
	}
	f.batch = batch
	return model.IngestResult{BatchID: batch.ID, Status: "active", ActiveSequence: batch.Sequence}, nil
}

func (f *fakeRepository) GetPublicDocument(_ context.Context, path string) (model.PublicDocument, bool, error) {
	if f.document.Path != path {
		return model.PublicDocument{}, false, nil
	}
	return f.document, true, nil
}

func (f *fakeRepository) PendingCommands(context.Context, string, int64) ([]model.Command, error) {
	return nil, nil
}

func (f *fakeRepository) EnqueueCommand(_ context.Context, id, agentID, kind string, arguments json.RawMessage, _ string, expires time.Time) (model.Command, error) {
	return model.Command{ID: id, AgentID: agentID, Kind: kind, Arguments: arguments, ExpiresAt: expires}, nil
}

func (f *fakeRepository) CreateOAuthState(context.Context, string, string, string, time.Time) error {
	return nil
}

func (f *fakeRepository) ConsumeOAuthState(context.Context, string, time.Time) (store.OAuthState, error) {
	return store.OAuthState{}, store.ErrOAuthState
}

func (f *fakeRepository) CreateSession(context.Context, string, int64, string, time.Time) error {
	return nil
}

func (f *fakeRepository) GetSession(context.Context, string, time.Time) (store.Session, bool, error) {
	return store.Session{}, false, nil
}

func (f *fakeRepository) DeleteSession(context.Context, string) error { return nil }
func (f *fakeRepository) Dashboard(context.Context) (model.DashboardSnapshot, error) {
	return model.DashboardSnapshot{}, nil
}

func testServer(t *testing.T, repository *fakeRepository) (http.Handler, ed25519.PrivateKey) {
	t.Helper()
	publicKey, privateKey, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	cfg := config.Web{
		PublicBaseURL:       "https://gaylemon.nethercore.dev",
		LegacyHosts:         []string{"gaylemon.mathieu.pro"},
		AgentPublicKeys:     map[string]ed25519.PublicKey{"test-agent": publicKey},
		SignatureMaxSkew:    5 * time.Minute,
		GitHubAllowedUserID: 753560,
	}
	return NewServer(cfg, repository, slog.New(slog.NewTextHandler(testWriter{t}, nil))).Handler(), privateKey
}

func TestLegacyHostRedirectPreservesPathAndQuery(t *testing.T) {
	handler, _ := testServer(t, &fakeRepository{})
	request := httptest.NewRequest(http.MethodGet, "https://gaylemon.mathieu.pro/resume?jour=2026-08-08", nil)
	recorder := httptest.NewRecorder()
	handler.ServeHTTP(recorder, request)
	if recorder.Code != http.StatusMovedPermanently || recorder.Header().Get("Location") != "https://gaylemon.nethercore.dev/resume?jour=2026-08-08" {
		t.Fatalf("redirection inattendue: status=%d location=%s", recorder.Code, recorder.Header().Get("Location"))
	}
}

func TestSignedIngestAndReplayProtection(t *testing.T) {
	repository := &fakeRepository{}
	handler, privateKey := testServer(t, repository)
	payload, _ := json.Marshal(model.BatchPayload{Documents: []model.Document{{Path: "data/public-stats.json", Content: json.RawMessage(`{"ok":true}`), CachePolicy: model.CacheRevalidate}}})
	batch := model.Batch{ID: "batch-1", AgentID: "test-agent", Stream: "stats", SchemaVersion: 1, Sequence: 1, CapturedAt: time.Now().UTC(), Payload: payload}
	body, _ := json.Marshal(batch)
	request := httptest.NewRequest(http.MethodPost, "https://gaylemon.nethercore.dev/api/ingest/v1/batches", strings.NewReader(string(body)))
	if err := auth.SignRequest(request, body, "test-agent", privateKey, time.Now().UTC()); err != nil {
		t.Fatal(err)
	}
	recorder := httptest.NewRecorder()
	handler.ServeHTTP(recorder, request)
	if recorder.Code != http.StatusAccepted || repository.batch.ID != batch.ID {
		t.Fatalf("publication refusée: status=%d body=%s", recorder.Code, recorder.Body.String())
	}
	replay := httptest.NewRequest(http.MethodPost, "https://gaylemon.nethercore.dev/api/ingest/v1/batches", strings.NewReader(string(body)))
	replay.Header = request.Header.Clone()
	replayRecorder := httptest.NewRecorder()
	handler.ServeHTTP(replayRecorder, replay)
	if replayRecorder.Code != http.StatusConflict {
		t.Fatalf("rejeu accepté: status=%d", replayRecorder.Code)
	}
}

func TestPublicDocumentUsesETag(t *testing.T) {
	repository := &fakeRepository{document: model.PublicDocument{Path: "data/public-stats.json", Content: []byte(`{"ok":true}`), ETag: "abc123", CachePolicy: model.CacheRevalidate, UpdatedAt: time.Now()}}
	handler, _ := testServer(t, repository)
	request := httptest.NewRequest(http.MethodGet, "/data/public-stats.json", nil)
	recorder := httptest.NewRecorder()
	handler.ServeHTTP(recorder, request)
	if recorder.Code != http.StatusOK || recorder.Header().Get("ETag") != `"sha256-abc123"` {
		t.Fatalf("document inattendu: status=%d etag=%s", recorder.Code, recorder.Header().Get("ETag"))
	}
	request = httptest.NewRequest(http.MethodGet, "/data/public-stats.json", nil)
	request.Header.Set("If-None-Match", `"sha256-abc123"`)
	recorder = httptest.NewRecorder()
	handler.ServeHTTP(recorder, request)
	if recorder.Code != http.StatusNotModified {
		t.Fatalf("revalidation inattendue: status=%d", recorder.Code)
	}
}

type testWriter struct{ t *testing.T }

func (w testWriter) Write(value []byte) (int, error) {
	w.t.Log(strings.TrimSpace(string(value)))
	return len(value), nil
}
