package web

import (
	"bytes"
	"compress/gzip"
	"context"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"mime"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/MathieuLF/gaylemon/internal/auth"
	"github.com/MathieuLF/gaylemon/internal/config"
	"github.com/MathieuLF/gaylemon/internal/model"
	"github.com/MathieuLF/gaylemon/internal/store"
	"golang.org/x/oauth2"
	"golang.org/x/oauth2/github"
)

const maxIngestBody = 64 << 20

type Server struct {
	config       config.Web
	repo         store.Repository
	logger       *slog.Logger
	release      ReleaseInfo
	oauth        *oauth2.Config
	mux          *http.ServeMux
	eventQueries chan struct{}
}

type ReleaseInfo struct {
	Product string `json:"product"`
	Version string `json:"version"`
	Commit  string `json:"commit"`
	Channel string `json:"channel"`
}

type sessionContextKey struct{}

type verifiedPayload struct {
	Body       []byte
	Request    auth.VerifiedRequest
	WireSHA256 string
	WireBytes  int64
	Compressed bool
}

type oauthStateCookie struct {
	StateHash  string `json:"stateHash"`
	Verifier   string `json:"verifier"`
	ReturnPath string `json:"returnPath"`
	ExpiresAt  int64  `json:"expiresAt"`
}

func NewServer(cfg config.Web, repo store.Repository, logger *slog.Logger) *Server {
	return NewServerWithRelease(cfg, repo, logger, ReleaseInfo{})
}

func NewServerWithRelease(cfg config.Web, repo store.Repository, logger *slog.Logger, release ReleaseInfo) *Server {
	if logger == nil {
		logger = slog.Default()
	}
	release = release.normalized()
	s := &Server{
		config:       cfg,
		repo:         repo,
		logger:       logger,
		release:      release,
		mux:          http.NewServeMux(),
		eventQueries: make(chan struct{}, 2),
	}
	if cfg.GitHubClientID != "" && cfg.GitHubClientSecret != "" {
		s.oauth = &oauth2.Config{
			ClientID:     cfg.GitHubClientID,
			ClientSecret: cfg.GitHubClientSecret,
			Endpoint:     github.Endpoint,
			RedirectURL:  cfg.PublicBaseURL + "/ops/auth/github/callback",
			Scopes:       []string{"read:user"},
		}
	}
	s.routes()
	return s
}

func (release ReleaseInfo) normalized() ReleaseInfo {
	release.Product = strings.TrimSpace(release.Product)
	release.Version = strings.TrimSpace(release.Version)
	release.Commit = strings.TrimSpace(release.Commit)
	release.Channel = strings.TrimSpace(release.Channel)
	if release.Product == "" {
		release.Product = "gaylemon-microsite"
	}
	if release.Version == "" {
		release.Version = "dev"
	}
	if release.Commit == "" {
		release.Commit = "unknown"
	}
	if release.Channel == "" {
		release.Channel = "development"
	}
	return release
}

func (s *Server) Handler() http.Handler {
	return s.redirectLegacyHost(s.securityHeaders(s.requestLog(s.mux)))
}

func (s *Server) redirectLegacyHost(next http.Handler) http.Handler {
	legacyHosts := make(map[string]bool, len(s.config.LegacyHosts))
	for _, host := range s.config.LegacyHosts {
		legacyHosts[strings.ToLower(host)] = true
	}
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		host := strings.ToLower(r.Host)
		if colon := strings.LastIndex(host, ":"); colon > -1 {
			host = host[:colon]
		}
		if legacyHosts[host] {
			http.Redirect(w, r, s.config.PublicBaseURL+r.URL.RequestURI(), http.StatusMovedPermanently)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func (s *Server) routes() {
	s.mux.HandleFunc("GET /health/live", s.handleLive)
	s.mux.HandleFunc("GET /health/ready", s.handleReady)
	s.mux.HandleFunc("GET /version", s.handleVersion)
	s.mux.HandleFunc("POST /api/ingest/v1/batches", s.handleIngest)
	s.mux.HandleFunc("POST /api/agent/v1/heartbeat", s.handleHeartbeat)
	s.mux.HandleFunc("GET /api/agent/v1/commands", s.handlePendingCommands)
	s.mux.HandleFunc("POST /api/agent/v1/commands/{id}/ack", s.handleCommandAck)
	s.mux.HandleFunc("GET /api/public/events/v1", s.handlePublicEvents)
	s.mux.HandleFunc("GET /data/{path...}", s.handlePublicData)
	s.mux.HandleFunc("GET /public-events-channel.json", s.handlePublicChannel)
	s.mux.HandleFunc("GET /ops/auth/login", s.handleOAuthLogin)
	s.mux.HandleFunc("GET /ops/auth/github/callback", s.handleOAuthCallback)
	s.mux.HandleFunc("POST /ops/auth/logout", s.requireSession(s.handleLogout))
	s.mux.HandleFunc("GET /ops/api/snapshot", s.requireSession(s.handleOpsSnapshot))
	s.mux.HandleFunc("POST /ops/api/commands", s.requireSession(s.handleOpsCommand))
	s.mux.HandleFunc("GET /ops", s.requireSession(s.handleOpsPage))
	s.mux.HandleFunc("GET /assets/game/{path...}", s.handleGameAsset)
	s.mux.HandleFunc("GET /", s.handlePortal)
}

func (s *Server) handleLive(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{"ok": true})
}

func (s *Server) handleReady(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
	defer cancel()
	if err := s.repo.Ping(ctx); err != nil {
		writeError(w, http.StatusServiceUnavailable, "database-unavailable")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"ok": true})
}

func (s *Server) handleVersion(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Cache-Control", "no-store")
	writeJSON(w, http.StatusOK, s.release)
}

func (s *Server) verifiedBody(w http.ResponseWriter, r *http.Request, limit int64) (verifiedPayload, bool) {
	wireBody, err := io.ReadAll(http.MaxBytesReader(w, r.Body, limit))
	if err != nil {
		writeError(w, http.StatusRequestEntityTooLarge, "request-too-large")
		return verifiedPayload{}, false
	}
	verified, err := auth.VerifyRequest(r, wireBody, s.config.AgentPublicKeys, time.Now().UTC(), s.config.SignatureMaxSkew)
	if err != nil {
		s.logger.Warn("requête agent refusée", "remote", r.RemoteAddr, "reason", err)
		writeError(w, http.StatusUnauthorized, "signature-refused")
		return verifiedPayload{}, false
	}
	body := wireBody
	compressed := false
	switch strings.ToLower(strings.TrimSpace(r.Header.Get("Content-Encoding"))) {
	case "":
	case "gzip":
		reader, err := gzip.NewReader(bytes.NewReader(wireBody))
		if err != nil {
			writeError(w, http.StatusBadRequest, "invalid-compression")
			return verifiedPayload{}, false
		}
		body, err = io.ReadAll(io.LimitReader(reader, limit+1))
		closeErr := reader.Close()
		if err != nil || closeErr != nil {
			writeError(w, http.StatusBadRequest, "invalid-compression")
			return verifiedPayload{}, false
		}
		if int64(len(body)) > limit {
			writeError(w, http.StatusRequestEntityTooLarge, "request-too-large")
			return verifiedPayload{}, false
		}
		compressed = true
	default:
		writeError(w, http.StatusUnsupportedMediaType, "unsupported-compression")
		return verifiedPayload{}, false
	}
	if err := s.repo.ClaimNonce(r.Context(), verified.AgentID, verified.Nonce, verified.ExpiresAt); err != nil {
		writeError(w, http.StatusConflict, "request-replayed")
		return verifiedPayload{}, false
	}
	return verifiedPayload{Body: body, Request: verified, WireSHA256: auth.BodySHA256(wireBody), WireBytes: int64(len(wireBody)), Compressed: compressed}, true
}

func (s *Server) handleIngest(w http.ResponseWriter, r *http.Request) {
	payload, ok := s.verifiedBody(w, r, maxIngestBody)
	if !ok {
		return
	}
	var batch model.Batch
	if err := json.Unmarshal(payload.Body, &batch); err != nil {
		writeError(w, http.StatusBadRequest, "invalid-json")
		return
	}
	if batch.AgentID != payload.Request.AgentID {
		writeError(w, http.StatusForbidden, "agent-mismatch")
		return
	}
	batch.TransportBytes = payload.WireBytes
	batch.Compressed = payload.Compressed
	activate := r.URL.Query().Get("shadow") != "1"
	result, err := s.repo.IngestBatch(r.Context(), batch, payload.WireSHA256, activate)
	if err != nil {
		status := http.StatusUnprocessableEntity
		if errors.Is(err, store.ErrStaleBatch) {
			status = http.StatusConflict
		}
		s.logger.Warn("lot refusé", "agent", payload.Request.AgentID, "stream", batch.Stream, "batch", batch.ID, "error", err)
		writeError(w, status, "batch-refused")
		return
	}
	writeJSON(w, http.StatusAccepted, result)
}

func (s *Server) handleHeartbeat(w http.ResponseWriter, r *http.Request) {
	payload, ok := s.verifiedBody(w, r, 1<<20)
	if !ok {
		return
	}
	var status model.AgentStatus
	if err := json.Unmarshal(payload.Body, &status); err != nil || status.AgentID != payload.Request.AgentID {
		writeError(w, http.StatusBadRequest, "invalid-heartbeat")
		return
	}
	if status.Profile == "" {
		status.Profile = "jeu-prioritaire"
	}
	if err := s.repo.UpsertHeartbeat(r.Context(), status); err != nil {
		writeError(w, http.StatusInternalServerError, "heartbeat-failed")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"ok": true, "serverTime": time.Now().UTC()})
}

func (s *Server) handlePendingCommands(w http.ResponseWriter, r *http.Request) {
	payload, ok := s.verifiedBody(w, r, 1)
	if !ok {
		return
	}
	after, _ := strconv.ParseInt(r.URL.Query().Get("after"), 10, 64)
	commands, err := s.repo.PendingCommands(r.Context(), payload.Request.AgentID, after)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "commands-unavailable")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"commands": commands, "serverTime": time.Now().UTC()})
}

func (s *Server) handleCommandAck(w http.ResponseWriter, r *http.Request) {
	payload, ok := s.verifiedBody(w, r, 1<<20)
	if !ok {
		return
	}
	var ack model.CommandAck
	if err := json.Unmarshal(payload.Body, &ack); err != nil {
		writeError(w, http.StatusBadRequest, "invalid-ack")
		return
	}
	if err := s.repo.AckCommand(r.Context(), payload.Request.AgentID, r.PathValue("id"), ack); err != nil {
		writeError(w, http.StatusConflict, "ack-refused")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"ok": true})
}

func (s *Server) handlePublicData(w http.ResponseWriter, r *http.Request) {
	s.servePublicDocument(w, r, "data/"+r.PathValue("path"))
}

func (s *Server) handlePublicChannel(w http.ResponseWriter, r *http.Request) {
	s.servePublicDocument(w, r, "public-events-channel.json")
}

func (s *Server) handlePublicEvents(w http.ResponseWriter, r *http.Request) {
	dateKey := strings.TrimSpace(r.URL.Query().Get("date"))
	var dayStart, dayEnd time.Time
	if dateKey != "" {
		location, err := time.LoadLocation("America/Toronto")
		if err != nil {
			s.logger.Error("fuseau public indisponible", "error", err)
			writeError(w, http.StatusInternalServerError, "events-time-zone-unavailable")
			return
		}
		dayStart, err = time.ParseInLocation(time.DateOnly, dateKey, location)
		if err != nil || dayStart.Format(time.DateOnly) != dateKey {
			writeError(w, http.StatusBadRequest, "events-date-invalid")
			return
		}
		dayEnd = dayStart.AddDate(0, 0, 1)
	}
	limit, err := strconv.Atoi(r.URL.Query().Get("limit"))
	if err != nil || limit < 1 {
		limit = 6
	}
	maxLimit := 100
	if dateKey != "" {
		maxLimit = 500
	}
	if limit > maxLimit {
		limit = maxLimit
	}
	offset, err := strconv.Atoi(r.URL.Query().Get("offset"))
	if err != nil || offset < 0 {
		offset = 0
	}
	if offset > 10_000 {
		writeError(w, http.StatusBadRequest, "events-offset-invalid")
		return
	}
	query := model.PublicEventQuery{
		Offset: offset,
		Limit:  limit,
		Type:   strings.TrimSpace(r.URL.Query().Get("type")),
		Player: strings.TrimSpace(r.URL.Query().Get("player")),
		Search: strings.TrimSpace(r.URL.Query().Get("q")),
		Day:    dateKey,
		From:   dayStart,
		Before: dayEnd,
	}
	if len(query.Type) > 80 || len(query.Player) > 120 || len(query.Search) > 200 {
		writeError(w, http.StatusBadRequest, "events-filter-invalid")
		return
	}
	select {
	case s.eventQueries <- struct{}{}:
		defer func() { <-s.eventQueries }()
	default:
		w.Header().Set("Retry-After", "1")
		writeError(w, http.StatusTooManyRequests, "events-busy")
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 3*time.Second)
	defer cancel()
	page, found, err := s.repo.QueryPublicEvents(ctx, query)
	if err != nil {
		s.logger.Warn("lecture des échos PostgreSQL impossible", "error", err)
		if errors.Is(err, context.DeadlineExceeded) || errors.Is(err, context.Canceled) {
			writeError(w, http.StatusServiceUnavailable, "events-timeout")
			return
		}
		writeError(w, http.StatusInternalServerError, "events-unavailable")
		return
	}
	if !found {
		writeError(w, http.StatusServiceUnavailable, "events-not-ready")
		return
	}
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("X-Robots-Tag", "noindex, nofollow")
	writeJSON(w, http.StatusOK, page)
}

func (s *Server) servePublicDocument(w http.ResponseWriter, r *http.Request, documentPath string) {
	document, found, err := s.repo.GetPublicDocument(r.Context(), documentPath)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "document-unavailable")
		return
	}
	if !found {
		http.NotFound(w, r)
		return
	}
	etag := `"sha256-` + document.ETag + `"`
	if r.Header.Get("If-None-Match") == etag {
		w.WriteHeader(http.StatusNotModified)
		return
	}
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Header().Set("ETag", etag)
	w.Header().Set("Last-Modified", document.UpdatedAt.UTC().Format(http.TimeFormat))
	w.Header().Set("X-Robots-Tag", "noindex, nofollow")
	switch document.CachePolicy {
	case model.CacheImmutable:
		w.Header().Set("Cache-Control", "public, max-age=31536000, immutable")
	case model.CacheRevalidate:
		w.Header().Set("Cache-Control", "no-cache, must-revalidate")
	default:
		w.Header().Set("Cache-Control", "no-store")
	}
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write(document.Content)
}

func (s *Server) handleGameAsset(w http.ResponseWriter, r *http.Request) {
	relative := filepath.Clean(filepath.FromSlash(r.PathValue("path")))
	if relative == "." || relative == ".source-commit" || strings.HasPrefix(relative, "..") || filepath.IsAbs(relative) {
		http.NotFound(w, r)
		return
	}
	target := filepath.Join(s.config.AssetRoot, relative)
	rootPrefix := s.config.AssetRoot + string(os.PathSeparator)
	if !strings.HasPrefix(target, rootPrefix) {
		http.NotFound(w, r)
		return
	}
	w.Header().Set("Cache-Control", "public, max-age=31536000, immutable")
	http.ServeFile(w, r, target)
}

var portalRoutes = map[string]string{
	"/":             "index.html",
	"/terminal":     "terminal.html",
	"/terminal/":    "terminal.html",
	"/resume":       "resume.html",
	"/resume/":      "resume.html",
	"/classements":  "classements.html",
	"/classements/": "classements.html",
	"/carte":        "carte.html",
	"/carte/":       "carte.html",
	"/github":       "github.html",
	"/github/":      "github.html",
}

func (s *Server) handlePortal(w http.ResponseWriter, r *http.Request) {
	canonical := map[string]string{"/Terminal": "/terminal", "/Resume": "/resume", "/Classements": "/classements", "/Carte": "/carte", "/Github": "/github"}
	if target, ok := canonical[strings.TrimSuffix(r.URL.Path, "/")]; ok {
		if strings.HasSuffix(r.URL.Path, "/") {
			target += "/"
		}
		http.Redirect(w, r, target, http.StatusMovedPermanently)
		return
	}
	if fileName, ok := portalRoutes[r.URL.Path]; ok {
		w.Header().Set("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0")
		http.ServeFile(w, r, filepath.Join(s.config.PortalRoot, fileName))
		return
	}
	relative := filepath.Clean(filepath.FromSlash(strings.TrimPrefix(r.URL.Path, "/")))
	if relative == "." || strings.HasPrefix(relative, "..") || filepath.IsAbs(relative) {
		http.NotFound(w, r)
		return
	}
	target := filepath.Join(s.config.PortalRoot, relative)
	if !strings.HasPrefix(target, s.config.PortalRoot+string(os.PathSeparator)) {
		http.NotFound(w, r)
		return
	}
	if strings.HasPrefix(r.URL.Path, "/assets/") || r.URL.Path == "/site.webmanifest" {
		w.Header().Set("Cache-Control", "public, max-age=31536000, immutable")
	} else {
		w.Header().Set("Cache-Control", "public, max-age=3600, must-revalidate")
	}
	if extension := filepath.Ext(target); extension != "" {
		if mediaType := mime.TypeByExtension(extension); mediaType != "" {
			w.Header().Set("Content-Type", mediaType)
		}
	}
	http.ServeFile(w, r, target)
}

func (s *Server) requestLog(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		started := time.Now()
		next.ServeHTTP(w, r)
		if strings.HasPrefix(r.URL.Path, "/api/") || strings.HasPrefix(r.URL.Path, "/ops/") {
			s.logger.Info("http", "method", r.Method, "path", r.URL.Path, "durationMs", time.Since(started).Milliseconds())
		}
	})
}

func (s *Server) securityHeaders(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("X-Frame-Options", "DENY")
		w.Header().Set("Referrer-Policy", "strict-origin-when-cross-origin")
		w.Header().Set("Permissions-Policy", "camera=(), microphone=(), geolocation=(), payment=(), usb=()")
		w.Header().Set("Content-Security-Policy", "base-uri 'self'; object-src 'none'; form-action 'self'; frame-ancestors 'none'")
		next.ServeHTTP(w, r)
	})
}

func writeJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(value)
}

func writeError(w http.ResponseWriter, status int, code string) {
	writeJSON(w, status, map[string]any{"ok": false, "error": code})
}

func randomToken(size int) (string, error) {
	value := make([]byte, size)
	if _, err := rand.Read(value); err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(value), nil
}

func tokenHash(value string) string {
	sum := sha256.Sum256([]byte(value))
	return hex.EncodeToString(sum[:])
}

func (s *Server) opsCookie(name, value string, expires time.Time, maxAge int, httpOnly bool) *http.Cookie {
	return &http.Cookie{
		Name:     name,
		Value:    value,
		Path:     "/ops",
		Expires:  expires,
		MaxAge:   maxAge,
		HttpOnly: httpOnly,
		Secure:   s.config.CookieSecure,
		SameSite: http.SameSiteLaxMode,
	}
}

func (s *Server) handleOAuthLogin(w http.ResponseWriter, r *http.Request) {
	if s.oauth == nil {
		writeError(w, http.StatusServiceUnavailable, "oauth-not-configured")
		return
	}
	state, err := randomToken(32)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "oauth-state-failed")
		return
	}
	verifier, err := randomToken(48)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "oauth-verifier-failed")
		return
	}
	challengeBytes := sha256.Sum256([]byte(verifier))
	challenge := base64.RawURLEncoding.EncodeToString(challengeBytes[:])
	returnPath := r.URL.Query().Get("return")
	if len(returnPath) > 512 || (returnPath != "/ops" && !strings.HasPrefix(returnPath, "/ops/")) {
		returnPath = "/ops"
	}
	expires := time.Now().UTC().Add(10 * time.Minute)
	stateCookie, err := s.encodeOAuthStateCookie(oauthStateCookie{
		StateHash:  tokenHash(state),
		Verifier:   verifier,
		ReturnPath: returnPath,
		ExpiresAt:  expires.Unix(),
	})
	if err != nil {
		writeError(w, http.StatusInternalServerError, "oauth-state-failed")
		return
	}
	http.SetCookie(w, s.opsCookie("gaylemon_oauth_state", stateCookie, expires, 600, true))
	location := s.oauth.AuthCodeURL(state, oauth2.AccessTypeOnline, oauth2.SetAuthURLParam("code_challenge", challenge), oauth2.SetAuthURLParam("code_challenge_method", "S256"))
	http.Redirect(w, r, location, http.StatusFound)
}

func (s *Server) handleOAuthCallback(w http.ResponseWriter, r *http.Request) {
	if s.oauth == nil || r.URL.Query().Get("code") == "" || r.URL.Query().Get("state") == "" {
		writeError(w, http.StatusBadRequest, "oauth-callback-invalid")
		return
	}
	cookie, cookieErr := r.Cookie("gaylemon_oauth_state")
	http.SetCookie(w, s.opsCookie("gaylemon_oauth_state", "", time.Time{}, -1, true))
	state, err := s.decodeOAuthStateCookie(cookie, time.Now().UTC())
	if cookieErr != nil || err != nil || !hmac.Equal([]byte(state.StateHash), []byte(tokenHash(r.URL.Query().Get("state")))) {
		writeError(w, http.StatusBadRequest, "oauth-state-invalid")
		return
	}
	token, err := s.oauth.Exchange(r.Context(), r.URL.Query().Get("code"), oauth2.VerifierOption(state.Verifier))
	if err != nil {
		s.logger.Warn("échange OAuth refusé", "error", err)
		writeError(w, http.StatusUnauthorized, "oauth-exchange-refused")
		return
	}
	request, _ := http.NewRequestWithContext(r.Context(), http.MethodGet, "https://api.github.com/user", nil)
	request.Header.Set("Accept", "application/vnd.github+json")
	request.Header.Set("Authorization", "Bearer "+token.AccessToken)
	request.Header.Set("User-Agent", "Gaylemon")
	response, err := http.DefaultClient.Do(request)
	if err != nil {
		writeError(w, http.StatusBadGateway, "github-unavailable")
		return
	}
	defer response.Body.Close()
	var user struct {
		ID    int64  `json:"id"`
		Login string `json:"login"`
	}
	if response.StatusCode != http.StatusOK || json.NewDecoder(io.LimitReader(response.Body, 1<<20)).Decode(&user) != nil || user.ID != s.config.GitHubAllowedUserID {
		writeError(w, http.StatusForbidden, "github-user-refused")
		return
	}
	sessionToken, err := randomToken(48)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "session-failed")
		return
	}
	expires := time.Now().UTC().Add(12 * time.Hour)
	if err := s.repo.CreateSession(r.Context(), tokenHash(sessionToken), user.ID, user.Login, expires); err != nil {
		writeError(w, http.StatusInternalServerError, "session-failed")
		return
	}
	csrf, _ := randomToken(24)
	http.SetCookie(w, s.opsCookie("gaylemon_ops", sessionToken, expires, 43200, true))
	http.SetCookie(w, s.opsCookie("gaylemon_csrf", csrf, expires, 43200, false))
	http.Redirect(w, r, state.ReturnPath, http.StatusFound)
}

func (s *Server) oauthStateSigningKey() []byte {
	digest := hmac.New(sha256.New, []byte(s.config.GitHubClientSecret))
	_, _ = digest.Write([]byte("gaylemon-oauth-state-cookie-v1"))
	return digest.Sum(nil)
}

func (s *Server) encodeOAuthStateCookie(state oauthStateCookie) (string, error) {
	payload, err := json.Marshal(state)
	if err != nil {
		return "", err
	}
	encoded := base64.RawURLEncoding.EncodeToString(payload)
	signature := hmac.New(sha256.New, s.oauthStateSigningKey())
	_, _ = signature.Write([]byte(encoded))
	return encoded + "." + base64.RawURLEncoding.EncodeToString(signature.Sum(nil)), nil
}

func (s *Server) decodeOAuthStateCookie(cookie *http.Cookie, now time.Time) (oauthStateCookie, error) {
	if cookie == nil || len(cookie.Value) > 4096 {
		return oauthStateCookie{}, store.ErrOAuthState
	}
	parts := strings.Split(cookie.Value, ".")
	if len(parts) != 2 {
		return oauthStateCookie{}, store.ErrOAuthState
	}
	providedSignature, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		return oauthStateCookie{}, store.ErrOAuthState
	}
	expectedSignature := hmac.New(sha256.New, s.oauthStateSigningKey())
	_, _ = expectedSignature.Write([]byte(parts[0]))
	if !hmac.Equal(providedSignature, expectedSignature.Sum(nil)) {
		return oauthStateCookie{}, store.ErrOAuthState
	}
	payload, err := base64.RawURLEncoding.DecodeString(parts[0])
	if err != nil {
		return oauthStateCookie{}, store.ErrOAuthState
	}
	var state oauthStateCookie
	if json.Unmarshal(payload, &state) != nil || state.StateHash == "" || state.Verifier == "" || len(state.ReturnPath) > 512 || (state.ReturnPath != "/ops" && !strings.HasPrefix(state.ReturnPath, "/ops/")) || now.Unix() >= state.ExpiresAt {
		return oauthStateCookie{}, store.ErrOAuthState
	}
	return state, nil
}

func (s *Server) requireSession(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		cookie, err := r.Cookie("gaylemon_ops")
		if err != nil || cookie.Value == "" {
			if r.Method == http.MethodGet && strings.HasPrefix(r.Header.Get("Accept"), "text/html") {
				http.Redirect(w, r, "/ops/auth/login", http.StatusFound)
				return
			}
			writeError(w, http.StatusUnauthorized, "authentication-required")
			return
		}
		session, found, err := s.repo.GetSession(r.Context(), tokenHash(cookie.Value), time.Now().UTC())
		if err != nil || !found || session.GitHubUserID != s.config.GitHubAllowedUserID {
			writeError(w, http.StatusUnauthorized, "session-invalid")
			return
		}
		if r.Method != http.MethodGet && r.Method != http.MethodHead {
			origin := r.Header.Get("Origin")
			csrfCookie, csrfErr := r.Cookie("gaylemon_csrf")
			if origin != s.config.PublicBaseURL || csrfErr != nil || csrfCookie.Value == "" || r.Header.Get("X-Gaylemon-CSRF") != csrfCookie.Value {
				writeError(w, http.StatusForbidden, "csrf-refused")
				return
			}
		}
		next(w, r.WithContext(context.WithValue(r.Context(), sessionContextKey{}, session)))
	}
}

func (s *Server) handleLogout(w http.ResponseWriter, r *http.Request) {
	if cookie, err := r.Cookie("gaylemon_ops"); err == nil {
		_ = s.repo.DeleteSession(r.Context(), tokenHash(cookie.Value))
	}
	http.SetCookie(w, s.opsCookie("gaylemon_ops", "", time.Time{}, -1, true))
	http.SetCookie(w, s.opsCookie("gaylemon_csrf", "", time.Time{}, -1, false))
	writeJSON(w, http.StatusOK, map[string]any{"ok": true})
}

func (s *Server) handleOpsSnapshot(w http.ResponseWriter, r *http.Request) {
	snapshot, err := s.repo.Dashboard(r.Context())
	if err != nil {
		writeError(w, http.StatusInternalServerError, "dashboard-unavailable")
		return
	}
	writeJSON(w, http.StatusOK, snapshot)
}

var allowedCommands = map[string]struct {
	Dangerous bool
	TTL       time.Duration
}{
	"sync.pause": {}, "sync.resume": {}, "sync.run": {TTL: 15 * time.Minute}, "sync.set-schedule": {},
	"server.status": {TTL: 5 * time.Minute}, "server.logs": {TTL: 5 * time.Minute}, "server.announce": {TTL: 5 * time.Minute},
	"server.backup": {TTL: 30 * time.Minute}, "service.restart": {Dangerous: true, TTL: 15 * time.Minute},
}

func (s *Server) handleOpsCommand(w http.ResponseWriter, r *http.Request) {
	var request struct {
		AgentID   string          `json:"agentId"`
		Kind      string          `json:"kind"`
		Arguments json.RawMessage `json:"arguments"`
		Confirm   string          `json:"confirm"`
	}
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1<<20)).Decode(&request); err != nil {
		writeError(w, http.StatusBadRequest, "command-invalid")
		return
	}
	policy, ok := allowedCommands[request.Kind]
	if !ok || request.AgentID == "" {
		writeError(w, http.StatusBadRequest, "command-refused")
		return
	}
	session := r.Context().Value(sessionContextKey{}).(store.Session)
	if policy.Dangerous {
		if request.Confirm != "GAYLÉMON" || time.Since(session.CreatedAt) > 5*time.Minute {
			writeError(w, http.StatusPreconditionFailed, "recent-login-and-confirmation-required")
			return
		}
		if request.Kind == "service.restart" && !validRestartArguments(request.Arguments) {
			writeError(w, http.StatusBadRequest, "restart-arguments-refused")
			return
		}
	}
	commandID, err := randomToken(18)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "command-failed")
		return
	}
	ttl := policy.TTL
	if ttl == 0 {
		ttl = 10 * time.Minute
	}
	command, err := s.repo.EnqueueCommand(r.Context(), commandID, request.AgentID, request.Kind, request.Arguments, session.GitHubLogin, time.Now().UTC().Add(ttl))
	if err != nil {
		writeError(w, http.StatusInternalServerError, "command-failed")
		return
	}
	writeJSON(w, http.StatusAccepted, command)
}

func validRestartArguments(raw json.RawMessage) bool {
	var args struct {
		Unit string `json:"unit"`
	}
	if json.Unmarshal(raw, &args) != nil {
		return false
	}
	switch args.Unit {
	case "gaylemon-agent.service", "gaylemon-collect-metrics.service", "gaylemon-collect-stats.service", "gaylemon-publish-events.service", "gaylemon-publish-snapshot.service", "palworld-events.service", "palworld-save-snapshot.service", "palworld-stats.service":
		return true
	default:
		return false
	}
}

func (s *Server) handleOpsPage(w http.ResponseWriter, _ *http.Request) {
	nonce, err := randomToken(18)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "page-unavailable")
		return
	}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("Content-Security-Policy", "base-uri 'self'; default-src 'none'; style-src 'nonce-"+nonce+"'; script-src 'nonce-"+nonce+"'; connect-src 'self'; form-action 'self'; frame-ancestors 'none'")
	_, _ = io.WriteString(w, strings.ReplaceAll(opsHTML, "{{NONCE}}", nonce))
}
