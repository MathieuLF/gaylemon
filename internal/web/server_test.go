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
	"slices"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/MathieuLF/gaylemon/internal/auth"
	"github.com/MathieuLF/gaylemon/internal/config"
	"github.com/MathieuLF/gaylemon/internal/model"
	"github.com/MathieuLF/gaylemon/internal/store"
)

type fakeRepository struct {
	mu                sync.Mutex
	document          model.PublicDocument
	eventPage         model.PublicEventPage
	eventQuery        model.PublicEventQuery
	eventBlock        <-chan struct{}
	eventStarted      chan<- struct{}
	batch             model.Batch
	ingestError       error
	nonces            map[string]bool
	oauthStateCreates int
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
	if f.ingestError != nil {
		return model.IngestResult{}, f.ingestError
	}
	if !activate {
		return model.IngestResult{}, errors.New("activation attendue")
	}
	f.batch = batch
	return model.IngestResult{BatchID: batch.ID, Status: "active", ActiveSequence: batch.Sequence}, nil
}

func TestArchivedSeasonReturnsLockedAfterSignedIngest(t *testing.T) {
	publicKey, privateKey, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	repository := &fakeRepository{ingestError: store.ErrSeasonArchived}
	_, responsePrivateKey, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	server := NewServer(config.Web{PublicBaseURL: "https://example.test", AgentPublicKeys: map[string]ed25519.PublicKey{"agent-1": publicKey}, ResponsePrivateKey: responsePrivateKey, SignatureMaxSkew: time.Minute}, repository, slog.Default())
	body := []byte(`{"batchId":"batch-1","agentId":"agent-1","stream":"stats","schemaVersion":1,"sequence":1,"capturedAt":"2026-08-26T12:00:00Z","payload":{"documents":[]}}`)
	request := httptest.NewRequest(http.MethodPost, "/api/ingest/v1/batches", bytes.NewReader(body))
	if err := auth.SignRequest(request, body, "agent-1", privateKey, time.Now().UTC()); err != nil {
		t.Fatal(err)
	}
	response := httptest.NewRecorder()
	server.Handler().ServeHTTP(response, request)
	if response.Code != http.StatusLocked || response.Header().Get("X-Gaylemon-Season-State") != "archived" || response.Header().Get("X-Gaylemon-Response-Signature") == "" || !strings.Contains(response.Body.String(), "season-archived") {
		t.Fatalf("réponse d'archive inattendue: status=%d headers=%v body=%s", response.Code, response.Header(), response.Body.String())
	}
}

func TestPortalAssetsAreContentAddressedAndRollbackSafe(t *testing.T) {
	portalRoot := t.TempDir()
	if err := os.MkdirAll(filepath.Join(portalRoot, "assets"), 0o755); err != nil {
		t.Fatal(err)
	}
	for name, content := range map[string]string{
		"assets/app.js":     "console.log('gaylemon');\n",
		"assets/styles.css": "body{color:#123}\n",
		"index.html":        `<!doctype html><html><head><link rel="stylesheet" href="/assets/styles.css"><script src="/assets/app.js"></script></head><body></body></html>`,
		"robots.txt":        "Sitemap: __GAYLEMON_PUBLIC_BASE_URL__/sitemap.xml\n",
		"sitemap.xml":       "<loc>__GAYLEMON_PUBLIC_BASE_URL__/</loc>\n",
		"sw.js":             `const release="__GAYLEMON_ASSET_RELEASE__";const shell=["__GAYLEMON_STYLES__","__GAYLEMON_APP__"];`,
	} {
		target := filepath.Join(portalRoot, filepath.FromSlash(name))
		if err := os.WriteFile(target, []byte(content), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	server := NewServer(config.Web{PublicBaseURL: "https://example.test", AnalyticsBaseURL: "https://analytics.example", PortalRoot: portalRoot}, &fakeRepository{}, slog.Default())

	manifestResponse := httptest.NewRecorder()
	server.Handler().ServeHTTP(manifestResponse, httptest.NewRequest(http.MethodGet, "/asset-manifest.json", nil))
	if manifestResponse.Code != http.StatusOK || !strings.Contains(manifestResponse.Header().Get("Cache-Control"), "no-store") {
		t.Fatalf("manifeste inattendu: status=%d cache=%q body=%s", manifestResponse.Code, manifestResponse.Header().Get("Cache-Control"), manifestResponse.Body.String())
	}
	var manifest struct {
		Schema      string `json:"schema"`
		Application string `json:"application"`
		Release     string `json:"release"`
		Assets      []struct {
			Source string `json:"source"`
			Path   string `json:"path"`
			SHA256 string `json:"sha256"`
		} `json:"assets"`
	}
	if err := json.Unmarshal(manifestResponse.Body.Bytes(), &manifest); err != nil {
		t.Fatal(err)
	}
	if manifest.Schema != "suite.asset-manifest.v1" || manifest.Application != "gaylemon" || len(manifest.Release) != 16 || len(manifest.Assets) != 2 {
		t.Fatalf("manifeste incomplet: %+v", manifest)
	}

	indexResponse := httptest.NewRecorder()
	server.Handler().ServeHTTP(indexResponse, httptest.NewRequest(http.MethodGet, "/", nil))
	if !strings.Contains(indexResponse.Body.String(), `name="gaylemon-analytics-base-url" content="https://analytics.example"`) {
		t.Fatalf("configuration analytics absente du HTML: %s", indexResponse.Body.String())
	}
	if !strings.Contains(indexResponse.Header().Get("Content-Security-Policy"), "https://analytics.example") {
		t.Fatalf("origine analytics absente de la CSP: %q", indexResponse.Header().Get("Content-Security-Policy"))
	}
	for _, asset := range manifest.Assets {
		if len(asset.SHA256) != 64 || asset.Path == "/"+asset.Source || !strings.Contains(indexResponse.Body.String(), asset.Path) {
			t.Fatalf("actif non lié au contenu: %+v body=%s", asset, indexResponse.Body.String())
		}
		hashedResponse := httptest.NewRecorder()
		server.Handler().ServeHTTP(hashedResponse, httptest.NewRequest(http.MethodGet, asset.Path, nil))
		if hashedResponse.Code != http.StatusOK || !strings.Contains(hashedResponse.Header().Get("Cache-Control"), "immutable") {
			t.Fatalf("cache haché invalide pour %s: %d %q", asset.Path, hashedResponse.Code, hashedResponse.Header().Get("Cache-Control"))
		}
	}
	unversionedResponse := httptest.NewRecorder()
	server.Handler().ServeHTTP(unversionedResponse, httptest.NewRequest(http.MethodGet, "/assets/app.js", nil))
	if strings.Contains(unversionedResponse.Header().Get("Cache-Control"), "immutable") {
		t.Fatalf("actif non haché immuable: %q", unversionedResponse.Header().Get("Cache-Control"))
	}
	workerResponse := httptest.NewRecorder()
	server.Handler().ServeHTTP(workerResponse, httptest.NewRequest(http.MethodGet, "/sw.js", nil))
	if strings.Contains(workerResponse.Body.String(), "__GAYLEMON_") || strings.Contains(workerResponse.Body.String(), "ignoreSearch") {
		t.Fatalf("service worker non résolu ou identité relâchée: %s", workerResponse.Body.String())
	}
	if !strings.Contains(workerResponse.Header().Get("Cache-Control"), "no-store") {
		t.Fatalf("service worker mis en cache: %q", workerResponse.Header().Get("Cache-Control"))
	}
	for _, path := range []string{"/robots.txt", "/sitemap.xml"} {
		response := httptest.NewRecorder()
		server.Handler().ServeHTTP(response, httptest.NewRequest(http.MethodGet, path, nil))
		if response.Code != http.StatusOK || !strings.Contains(response.Body.String(), "https://example.test/") || strings.Contains(response.Body.String(), "__GAYLEMON_") {
			t.Fatalf("ressource publique non résolue %s: status=%d body=%s", path, response.Code, response.Body.String())
		}
		if !strings.Contains(response.Header().Get("Cache-Control"), "no-store") {
			t.Fatalf("ressource publique mise en cache %s: %q", path, response.Header().Get("Cache-Control"))
		}
	}
}

func TestPublicSeasonStateIsExposed(t *testing.T) {
	server := NewServer(config.Web{PublicBaseURL: "https://example.test"}, &fakeRepository{}, slog.Default())
	for _, route := range []string{"/api/public/seasons/v1", "/api/public/site-state/v1"} {
		request := httptest.NewRequest(http.MethodGet, route, nil)
		response := httptest.NewRecorder()
		server.Handler().ServeHTTP(response, request)
		if response.Code != http.StatusOK || !strings.Contains(response.Body.String(), "saison-2026") {
			t.Fatalf("route %s: status=%d body=%s", route, response.Code, response.Body.String())
		}
		if strings.Contains(response.Body.String(), "manifest") || strings.Contains(response.Body.String(), "immutableBackup") || strings.Contains(response.Body.String(), "season-2026") {
			t.Fatalf("route %s expose des détails opérationnels: %s", route, response.Body.String())
		}
	}
}

func (f *fakeRepository) GetPublicDocument(_ context.Context, path string) (model.PublicDocument, bool, error) {
	if f.document.Path != path {
		return model.PublicDocument{}, false, nil
	}
	return f.document, true, nil
}
func (f *fakeRepository) GetPublicDocumentForSeason(ctx context.Context, _ string, path string) (model.PublicDocument, bool, error) {
	return f.GetPublicDocument(ctx, path)
}

func (f *fakeRepository) QueryPublicEvents(ctx context.Context, query model.PublicEventQuery) (model.PublicEventPage, bool, error) {
	f.mu.Lock()
	f.eventQuery = query
	f.mu.Unlock()
	if f.eventStarted != nil {
		f.eventStarted <- struct{}{}
	}
	if f.eventBlock != nil {
		select {
		case <-f.eventBlock:
		case <-ctx.Done():
			return model.PublicEventPage{}, false, ctx.Err()
		}
	}
	if !f.eventPage.OK {
		return model.PublicEventPage{}, false, nil
	}
	page := f.eventPage
	page.Offset = query.Offset
	page.Limit = query.Limit
	page.Date = query.Day
	return page, true, nil
}

func (f *fakeRepository) lastEventQuery() model.PublicEventQuery {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.eventQuery
}
func (f *fakeRepository) QueryPublicEventsForSeason(ctx context.Context, _ string, query model.PublicEventQuery) (model.PublicEventPage, bool, error) {
	return f.QueryPublicEvents(ctx, query)
}

func (f *fakeRepository) PendingCommands(context.Context, string, int64) ([]model.Command, error) {
	return nil, nil
}

func (f *fakeRepository) EnqueueCommand(_ context.Context, id, agentID, kind string, arguments json.RawMessage, _ string, expires time.Time) (model.Command, error) {
	return model.Command{ID: id, AgentID: agentID, Kind: kind, Arguments: arguments, ExpiresAt: expires}, nil
}

func (f *fakeRepository) CreateOAuthState(context.Context, string, string, string, time.Time) error {
	f.oauthStateCreates++
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
func (f *fakeRepository) ResolveSeason(context.Context, string) (model.Season, bool, error) {
	return model.Season{ID: "season-2026", Slug: "saison-2026", Title: "Saison 2026", State: model.SeasonActive, Manifest: json.RawMessage(`{"immutableBackup":"urn:private:test"}`)}, true, nil
}
func (f *fakeRepository) ListSeasons(context.Context) ([]model.Season, error) {
	season, _, _ := f.ResolveSeason(context.Background(), "")
	return []model.Season{season}, nil
}
func (f *fakeRepository) CreateSeason(context.Context, model.SeasonCreate, string) (model.Season, error) {
	return model.Season{ID: "season-new", State: model.SeasonDraft}, nil
}
func (f *fakeRepository) ActivateSeasonWithCommand(context.Context, string, string, string, string, time.Time) (model.Season, model.Command, error) {
	return model.Season{ID: "season-new", State: model.SeasonActive}, model.Command{ID: "activate-command", Kind: "season.activate", Status: "pending"}, nil
}
func (f *fakeRepository) BeginSeasonArchive(context.Context, string, string, string, string, time.Time) (model.Command, error) {
	return model.Command{ID: "archive-command", Kind: "season.archive", Status: "pending"}, nil
}
func (f *fakeRepository) ReopenSeason(context.Context, string, string, string, string, time.Time) (model.Season, model.Command, error) {
	return model.Season{ID: "season-2026", State: model.SeasonActive}, model.Command{ID: "activate-command", Kind: "season.activate"}, nil
}

func testServer(t *testing.T, repository *fakeRepository) (http.Handler, ed25519.PrivateKey) {
	t.Helper()
	publicKey, privateKey, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	cfg := config.Web{
		PublicBaseURL:       "https://gaylemon.example",
		LegacyHosts:         []string{"legacy.gaylemon.example", "www.gaylemon.example"},
		AgentPublicKeys:     map[string]ed25519.PublicKey{"test-agent": publicKey},
		SignatureMaxSkew:    5 * time.Minute,
		GitHubAllowedUserID: 753560,
	}
	return NewServer(cfg, repository, slog.New(slog.NewTextHandler(testWriter{t}, nil))).Handler(), privateKey
}

func TestLegacyHostsRedirectPreservesPathAndQuery(t *testing.T) {
	for _, host := range []string{"legacy.gaylemon.example", "www.gaylemon.example"} {
		t.Run(host, func(t *testing.T) {
			handler, _ := testServer(t, &fakeRepository{})
			request := httptest.NewRequest(http.MethodGet, "https://"+host+"/resume?jour=2026-08-08", nil)
			recorder := httptest.NewRecorder()
			handler.ServeHTTP(recorder, request)
			if recorder.Code != http.StatusMovedPermanently || recorder.Header().Get("Location") != "https://gaylemon.example/resume?jour=2026-08-08" {
				t.Fatalf("redirection inattendue: status=%d location=%s", recorder.Code, recorder.Header().Get("Location"))
			}
		})
	}
}

func TestVersionRoutePublishesOnlyReleaseMetadataWithoutCaching(t *testing.T) {
	repository := &fakeRepository{}
	server := NewServerWithRelease(config.Web{}, repository, slog.New(slog.NewTextHandler(testWriter{t}, nil)), ReleaseInfo{
		Version: "1.0.0",
		Commit:  "a815220a66fa16ffc9f55f71b6782993988c2fd9",
		BuiltAt: "2026-08-10T12:30:00Z",
	})
	request := httptest.NewRequest(http.MethodGet, "https://gaylemon.example/api/version", nil)
	recorder := httptest.NewRecorder()
	server.Handler().ServeHTTP(recorder, request)

	if recorder.Code != http.StatusOK {
		t.Fatalf("route de version indisponible: status=%d body=%s", recorder.Code, recorder.Body.String())
	}
	if recorder.Header().Get("Cache-Control") != "no-store" {
		t.Fatalf("métadonnées de version mises en cache: %q", recorder.Header().Get("Cache-Control"))
	}
	if got := recorder.Header().Get("Content-Type"); got != "application/json; charset=utf-8" {
		t.Fatalf("MIME du contrat de version inattendu: %q", got)
	}
	var raw map[string]json.RawMessage
	if err := json.Unmarshal(recorder.Body.Bytes(), &raw); err != nil {
		t.Fatal(err)
	}
	expectedKeys := []string{"application", "builtAt", "commit", "schema", "version"}
	actualKeys := make([]string, 0, len(raw))
	for key := range raw {
		actualKeys = append(actualKeys, key)
	}
	slices.Sort(actualKeys)
	if !slices.Equal(actualKeys, expectedKeys) {
		t.Fatalf("clés du contrat de version inattendues: %v", actualKeys)
	}
	var release ReleaseInfo
	if err := json.Unmarshal(recorder.Body.Bytes(), &release); err != nil {
		t.Fatal(err)
	}
	if release.Schema != "suite.version.v1" || release.Application != "gaylemon" || release.Version != "1.0.0" || release.Commit != "a815220a66fa16ffc9f55f71b6782993988c2fd9" || release.BuiltAt != "2026-08-10T12:30:00Z" {
		t.Fatalf("métadonnées de version inattendues: %+v", release)
	}
}

func TestDefaultReleaseMetadataRemainsExplicit(t *testing.T) {
	server := NewServer(config.Web{}, &fakeRepository{}, nil)
	if server.release.Schema != "suite.version.v1" || server.release.Application != "gaylemon" || server.release.Version != "0.0.0-dev" || server.release.Commit != "0000000000000000000000000000000000000000" || server.release.BuiltAt != "1970-01-01T00:00:00Z" {
		t.Fatalf("valeurs de développement ambiguës: %+v", server.release)
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

func TestOAuthLoginUsesAClientCookieWithoutDatabaseWrite(t *testing.T) {
	repository := &fakeRepository{}
	cfg := config.Web{
		PublicBaseURL:      "https://gaylemon.example",
		CookieSecure:       true,
		GitHubClientID:     "client-id",
		GitHubClientSecret: "client-secret-with-enough-entropy",
	}
	handler := NewServer(cfg, repository, slog.New(slog.NewTextHandler(testWriter{t}, nil))).Handler()
	request := httptest.NewRequest(http.MethodGet, "https://gaylemon.example/ops/auth/login?return=/ops", nil)
	recorder := httptest.NewRecorder()
	handler.ServeHTTP(recorder, request)

	if recorder.Code != http.StatusFound {
		t.Fatalf("initiation OAuth inattendue: status=%d body=%s", recorder.Code, recorder.Body.String())
	}
	if repository.oauthStateCreates != 0 {
		t.Fatalf("l'initiation OAuth a persisté %d état(s)", repository.oauthStateCreates)
	}
	found := false
	for _, cookie := range recorder.Result().Cookies() {
		if cookie.Name == "gaylemon_oauth_state" {
			found = cookie.HttpOnly && cookie.Secure && cookie.MaxAge == 600
		}
	}
	if !found {
		t.Fatal("le cookie OAuth court et HttpOnly est absent")
	}
}

func TestOAuthStateCookieRejectsTamperingAndExpiry(t *testing.T) {
	server := &Server{config: config.Web{GitHubClientSecret: "client-secret-with-enough-entropy"}}
	now := time.Now().UTC()
	encoded, err := server.encodeOAuthStateCookie(oauthStateCookie{
		StateHash:  tokenHash("state"),
		Verifier:   "verifier",
		ReturnPath: "/ops",
		ExpiresAt:  now.Add(time.Minute).Unix(),
	})
	if err != nil {
		t.Fatal(err)
	}
	decoded, err := server.decodeOAuthStateCookie(&http.Cookie{Value: encoded}, now)
	if err != nil || decoded.Verifier != "verifier" {
		t.Fatalf("cookie OAuth valide refusé: state=%+v error=%v", decoded, err)
	}

	tamperedPrefix := "A"
	if encoded[0] == 'A' {
		tamperedPrefix = "B"
	}
	tampered := tamperedPrefix + encoded[1:]
	if _, err := server.decodeOAuthStateCookie(&http.Cookie{Value: tampered}, now); !errors.Is(err, store.ErrOAuthState) {
		t.Fatalf("cookie OAuth altéré accepté: %v", err)
	}
	if _, err := server.decodeOAuthStateCookie(&http.Cookie{Value: encoded}, now.Add(2*time.Minute)); !errors.Is(err, store.ErrOAuthState) {
		t.Fatalf("cookie OAuth expiré accepté: %v", err)
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
		"loadRelease()",
		"document.querySelector('#release').textContent",
	}
	for _, fragment := range required {
		if !strings.Contains(opsHTML, fragment) {
			t.Fatalf("retour de commande Ops incomplet: %s", fragment)
		}
	}
	for _, forbidden := range []string{"server.update", "palworld.service", "allowPalworldRestart"} {
		if strings.Contains(opsHTML, forbidden) {
			t.Fatalf("commande perturbatrice encore exposée dans Ops: %s", forbidden)
		}
	}
}

func TestPortalDisplaysReleaseMetadataAsText(t *testing.T) {
	for _, page := range []string{"index.html", "resume.html", "terminal.html", "classements.html", "carte.html", "github.html", "informations.html", "confidentialite.html"} {
		source, err := os.ReadFile(filepath.Join("..", "..", "portal", page))
		if err != nil {
			t.Fatal(err)
		}
		text := string(source)
		if !strings.Contains(text, "data-microsite-version") || !strings.Contains(text, "/assets/app.js") || !strings.Contains(text, "/assets/styles.css") || strings.Contains(text, "app.js?") || strings.Contains(text, "styles.css?") {
			t.Fatalf("version publique absente ou assets incohérents dans %s", page)
		}
	}

	appSource, err := os.ReadFile(filepath.Join("..", "..", "portal", "assets", "app.js"))
	if err != nil {
		t.Fatal(err)
	}
	app := string(appSource)
	for _, required := range []string{"fetch(\"/api/version\"", "micrositeVersion.textContent", "Version v", "cache: \"no-store\""} {
		if !strings.Contains(app, required) {
			t.Fatalf("chargement sûr de la version incomplet: %s", required)
		}
	}
	if strings.Contains(app, "micrositeVersion.innerHTML") {
		t.Fatal("les métadonnées de version ne doivent jamais être injectées en HTML")
	}
}

func TestSignedIngestAndReplayProtection(t *testing.T) {
	repository := &fakeRepository{}
	handler, privateKey := testServer(t, repository)
	payload, _ := json.Marshal(model.BatchPayload{Documents: []model.Document{{Path: "data/public-stats.json", Content: json.RawMessage(`{"ok":true}`), CachePolicy: model.CacheRevalidate}}})
	batch := model.Batch{ID: "batch-1", AgentID: "test-agent", Stream: "stats", SchemaVersion: 1, Sequence: 1, CapturedAt: time.Now().UTC(), Payload: payload}
	body, _ := json.Marshal(batch)
	request := httptest.NewRequest(http.MethodPost, "https://gaylemon.example/api/ingest/v1/batches", strings.NewReader(string(body)))
	if err := auth.SignRequest(request, body, "test-agent", privateKey, time.Now().UTC()); err != nil {
		t.Fatal(err)
	}
	recorder := httptest.NewRecorder()
	handler.ServeHTTP(recorder, request)
	if recorder.Code != http.StatusAccepted || repository.batch.ID != batch.ID {
		t.Fatalf("publication refusée: status=%d body=%s", recorder.Code, recorder.Body.String())
	}
	replay := httptest.NewRequest(http.MethodPost, "https://gaylemon.example/api/ingest/v1/batches", strings.NewReader(string(body)))
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
	request := httptest.NewRequest(http.MethodPost, "https://gaylemon.example/api/ingest/v1/batches", bytes.NewReader(wireBody))
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
		ObservedAt: time.Date(2026, time.August, 9, 20, 0, 0, 0, time.UTC),
		Events:     []json.RawMessage{json.RawMessage(`{"key":"evt-42","type":"craft","player":"MathieuLF"}`)},
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
	if payload.Freshness != "stale" || payload.SourceStatus != "available" || payload.LagSeconds != 1560 || payload.ObservedAt.IsZero() {
		t.Fatalf("fraîcheur PostgreSQL inattendue: %#v", payload)
	}
}

func TestPublicEventsRejectDeepOffsets(t *testing.T) {
	repository := &fakeRepository{eventPage: model.PublicEventPage{OK: true}}
	handler, _ := testServer(t, repository)
	request := httptest.NewRequest(http.MethodGet, "/api/public/events/v1?limit=100&offset=10001", nil)
	recorder := httptest.NewRecorder()
	handler.ServeHTTP(recorder, request)

	if recorder.Code != http.StatusBadRequest {
		t.Fatalf("offset profond accepté: status=%d body=%s", recorder.Code, recorder.Body.String())
	}
}

func TestPublicEventsFilterOneTorontoDay(t *testing.T) {
	repository := &fakeRepository{eventPage: model.PublicEventPage{OK: true}}
	handler, _ := testServer(t, repository)
	request := httptest.NewRequest(http.MethodGet, "/api/public/events/v1?limit=1000&date=2026-01-15", nil)
	recorder := httptest.NewRecorder()
	handler.ServeHTTP(recorder, request)

	if recorder.Code != http.StatusOK {
		t.Fatalf("filtre journalier refusé: status=%d body=%s", recorder.Code, recorder.Body.String())
	}
	query := repository.lastEventQuery()
	if query.Day != "2026-01-15" || query.Limit != 500 || query.From.IsZero() || query.Before.IsZero() {
		t.Fatalf("requête journalière inattendue: %#v", query)
	}
	if query.From.Format(time.RFC3339) != "2026-01-15T00:00:00-05:00" || query.Before.Format(time.RFC3339) != "2026-01-16T00:00:00-05:00" {
		t.Fatalf("bornes Toronto inattendues: %s -> %s", query.From.Format(time.RFC3339), query.Before.Format(time.RFC3339))
	}
	var payload model.PublicEventPage
	if err := json.Unmarshal(recorder.Body.Bytes(), &payload); err != nil || payload.Date != query.Day {
		t.Fatalf("date absente de la réponse: payload=%#v err=%v", payload, err)
	}
}

func TestPublicEventsRejectInvalidDay(t *testing.T) {
	repository := &fakeRepository{eventPage: model.PublicEventPage{OK: true}}
	handler, _ := testServer(t, repository)
	recorder := httptest.NewRecorder()
	handler.ServeHTTP(recorder, httptest.NewRequest(http.MethodGet, "/api/public/events/v1?date=2026-02-31", nil))

	query := repository.lastEventQuery()
	if recorder.Code != http.StatusBadRequest || query.Day != "" {
		t.Fatalf("date invalide acceptée: status=%d query=%#v body=%s", recorder.Code, query, recorder.Body.String())
	}
}

func TestPublicEventsLimitConcurrentDatabaseQueries(t *testing.T) {
	block := make(chan struct{})
	started := make(chan struct{}, 2)
	repository := &fakeRepository{
		eventPage:    model.PublicEventPage{OK: true},
		eventBlock:   block,
		eventStarted: started,
	}
	handler, _ := testServer(t, repository)
	responses := make(chan int, 2)
	for range 2 {
		go func() {
			recorder := httptest.NewRecorder()
			handler.ServeHTTP(recorder, httptest.NewRequest(http.MethodGet, "/api/public/events/v1", nil))
			responses <- recorder.Code
		}()
	}
	for range 2 {
		select {
		case <-started:
		case <-time.After(time.Second):
			t.Fatal("les deux requêtes PostgreSQL n'ont pas démarré")
		}
	}

	recorder := httptest.NewRecorder()
	handler.ServeHTTP(recorder, httptest.NewRequest(http.MethodGet, "/api/public/events/v1", nil))
	if recorder.Code != http.StatusTooManyRequests || recorder.Header().Get("Retry-After") != "1" {
		t.Fatalf("troisième requête non bornée: status=%d body=%s", recorder.Code, recorder.Body.String())
	}
	close(block)
	for range 2 {
		if status := <-responses; status != http.StatusOK {
			t.Fatalf("requête normale refusée: status=%d", status)
		}
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
