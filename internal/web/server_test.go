package web

import (
	"bytes"
	"compress/gzip"
	"context"
	"crypto/ed25519"
	"crypto/rand"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/MathieuLF/gaylemon/internal/auth"
	"github.com/MathieuLF/gaylemon/internal/config"
	"github.com/MathieuLF/gaylemon/internal/model"
	"github.com/MathieuLF/gaylemon/internal/store"
)

type fakeRepository struct {
	document  model.PublicDocument
	eventPage model.PublicEventPage
	batch     model.Batch
	nonces    map[string]bool
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

func (f *fakeRepository) QueryPublicEvents(_ context.Context, query model.PublicEventQuery) (model.PublicEventPage, bool, error) {
	if !f.eventPage.OK {
		return model.PublicEventPage{}, false, nil
	}
	page := f.eventPage
	page.Offset = query.Offset
	page.Limit = query.Limit
	return page, true, nil
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
		LegacyHosts:         []string{"gaylemon.mathieu.pro", "www.gaylemon.nethercore.dev"},
		AgentPublicKeys:     map[string]ed25519.PublicKey{"test-agent": publicKey},
		SignatureMaxSkew:    5 * time.Minute,
		GitHubAllowedUserID: 753560,
	}
	return NewServer(cfg, repository, slog.New(slog.NewTextHandler(testWriter{t}, nil))).Handler(), privateKey
}

func TestLegacyHostsRedirectPreservesPathAndQuery(t *testing.T) {
	for _, host := range []string{"gaylemon.mathieu.pro", "www.gaylemon.nethercore.dev"} {
		t.Run(host, func(t *testing.T) {
			handler, _ := testServer(t, &fakeRepository{})
			request := httptest.NewRequest(http.MethodGet, "https://"+host+"/resume?jour=2026-08-08", nil)
			recorder := httptest.NewRecorder()
			handler.ServeHTTP(recorder, request)
			if recorder.Code != http.StatusMovedPermanently || recorder.Header().Get("Location") != "https://gaylemon.nethercore.dev/resume?jour=2026-08-08" {
				t.Fatalf("redirection inattendue: status=%d location=%s", recorder.Code, recorder.Header().Get("Location"))
			}
		})
	}
}

func TestOpsCookiesSupportOAuthRedirect(t *testing.T) {
	server := &Server{config: config.Web{CookieSecure: true}}
	expires := time.Now().UTC().Add(12 * time.Hour)

	session := server.opsCookie("gaylemon_ops", "session", expires, 43200, true)
	csrf := server.opsCookie("gaylemon_csrf", "csrf", expires, 43200, false)

	for _, cookie := range []*http.Cookie{session, csrf} {
		if cookie.Path != "/ops" || !cookie.Secure || cookie.SameSite != http.SameSiteLaxMode {
			t.Fatalf("attributs de cookie OAuth inattendus: %+v", cookie)
		}
	}
	if !session.HttpOnly {
		t.Fatal("le cookie de session doit rester HttpOnly")
	}
	if csrf.HttpOnly {
		t.Fatal("le jeton CSRF doit rester lisible par l'interface ops")
	}
}

func TestOpsPageWaitsForTheAgentResult(t *testing.T) {
	required := []string{
		"waitForCommand(d.id)",
		"current.status!=='pending'",
		"Commande transmise, en attente du serveur",
		"shortResult(x.message)",
		"Reconnectez-vous à l’exploitation",
		"Message dans le chat du jeu",
	}
	for _, fragment := range required {
		if !strings.Contains(opsHTML, fragment) {
			t.Fatalf("retour de commande Ops incomplet: %s", fragment)
		}
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

func TestSignedGzipIngestTracksWireBytes(t *testing.T) {
	repository := &fakeRepository{}
	handler, privateKey := testServer(t, repository)
	payload, _ := json.Marshal(model.BatchPayload{Documents: []model.Document{{Path: "data/public-stats.json", Content: json.RawMessage(`{"ok":true}`), CachePolicy: model.CacheRevalidate}}})
	batch := model.Batch{ID: "batch-gzip", AgentID: "test-agent", Stream: "stats", SchemaVersion: 1, Sequence: 1, CapturedAt: time.Now().UTC(), Payload: payload}
	body, _ := json.Marshal(batch)
	var compressed bytes.Buffer
	writer := gzip.NewWriter(&compressed)
	if _, err := writer.Write(body); err != nil {
		t.Fatal(err)
	}
	if err := writer.Close(); err != nil {
		t.Fatal(err)
	}
	wireBody := compressed.Bytes()
	request := httptest.NewRequest(http.MethodPost, "https://gaylemon.nethercore.dev/api/ingest/v1/batches", bytes.NewReader(wireBody))
	request.Header.Set("Content-Encoding", "gzip")
	if err := auth.SignRequest(request, wireBody, "test-agent", privateKey, time.Now().UTC()); err != nil {
		t.Fatal(err)
	}
	recorder := httptest.NewRecorder()
	handler.ServeHTTP(recorder, request)
	if recorder.Code != http.StatusAccepted || !repository.batch.Compressed || repository.batch.TransportBytes != int64(len(wireBody)) {
		t.Fatalf("ingestion gzip inattendue: status=%d batch=%#v body=%s", recorder.Code, repository.batch, recorder.Body.String())
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

func TestPublicEventsAreServedFromPostgresProjection(t *testing.T) {
	repository := &fakeRepository{eventPage: model.PublicEventPage{
		OK: true, SchemaVersion: 1, Source: "postgresql", Revision: "events-42", Total: 1,
		Freshness: "stale", SourceStatus: "available", LagSeconds: 1560,
		Events: []json.RawMessage{json.RawMessage(`{"key":"evt-42","type":"craft","player":"MathieuLF"}`)},
		Facets: map[string][]model.PublicEventFacet{
			"types": []model.PublicEventFacet{{Value: "craft", Count: 1}},
		},
	}}
	handler, _ := testServer(t, repository)
	request := httptest.NewRequest(http.MethodGet, "/api/public/events/v1?limit=12&offset=24&type=craft", nil)
	recorder := httptest.NewRecorder()
	handler.ServeHTTP(recorder, request)

	if recorder.Code != http.StatusOK || recorder.Header().Get("Cache-Control") != "no-store" {
		t.Fatalf("API publique inattendue: status=%d cache=%s body=%s", recorder.Code, recorder.Header().Get("Cache-Control"), recorder.Body.String())
	}
	var payload model.PublicEventPage
	if err := json.Unmarshal(recorder.Body.Bytes(), &payload); err != nil {
		t.Fatal(err)
	}
	if payload.Source != "postgresql" || payload.Offset != 24 || payload.Limit != 12 || len(payload.Events) != 1 {
		t.Fatalf("page PostgreSQL inattendue: %#v", payload)
	}
	if payload.Freshness != "stale" || payload.SourceStatus != "available" || payload.LagSeconds != 1560 {
		t.Fatalf("fraîcheur PostgreSQL inattendue: %#v", payload)
	}
}

func TestGameAssetsHideTheSourceMarker(t *testing.T) {
	root := t.TempDir()
	if err := os.WriteFile(filepath.Join(root, ".source-commit"), []byte("private-build-marker\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	server := &Server{config: config.Web{AssetRoot: root}}
	request := httptest.NewRequest(http.MethodGet, "/assets/game/.source-commit", nil)
	request.SetPathValue("path", ".source-commit")
	recorder := httptest.NewRecorder()
	server.handleGameAsset(recorder, request)
	if recorder.Code != http.StatusNotFound {
		t.Fatalf("marqueur de source exposé: status=%d body=%s", recorder.Code, recorder.Body.String())
	}
}

type testWriter struct{ t *testing.T }

func (w testWriter) Write(value []byte) (int, error) {
	w.t.Log(strings.TrimSpace(string(value)))
	return len(value), nil
}
