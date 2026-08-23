package store

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io/fs"
	"path"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/MathieuLF/gaylemon/db/migrations"
	"github.com/MathieuLF/gaylemon/internal/model"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

var (
	ErrReplay       = errors.New("nonce déjà utilisé")
	ErrStaleBatch   = errors.New("lot plus ancien que la séquence active")
	ErrInvalidBatch = errors.New("lot invalide")
	ErrOAuthState   = errors.New("état OAuth invalide ou expiré")
)

const publicEventStaleAfter = 25 * time.Minute

func escapeLikePattern(value string) string {
	value = strings.ReplaceAll(value, `\`, `\\`)
	value = strings.ReplaceAll(value, `%`, `\%`)
	return strings.ReplaceAll(value, `_`, `\_`)
}

func publicEventFreshness(updatedAt, now time.Time) (string, string, int64) {
	if updatedAt.IsZero() {
		return "stale", "unknown", 0
	}
	lag := max(now.Sub(updatedAt), 0)
	freshness := "current"
	if lag > publicEventStaleAfter {
		freshness = "stale"
	}
	return freshness, "available", int64(lag / time.Second)
}

type Postgres struct {
	pool *pgxpool.Pool
}

func OpenPostgres(ctx context.Context, databaseURL string) (*Postgres, error) {
	config, err := pgxpool.ParseConfig(databaseURL)
	if err != nil {
		return nil, fmt.Errorf("configuration PostgreSQL: %w", err)
	}
	config.MaxConns = 8
	config.MinConns = 1
	config.MaxConnLifetime = time.Hour
	pool, err := pgxpool.NewWithConfig(ctx, config)
	if err != nil {
		return nil, fmt.Errorf("ouverture PostgreSQL: %w", err)
	}
	return &Postgres{pool: pool}, nil
}

func (p *Postgres) Close() { p.pool.Close() }

func (p *Postgres) Ping(ctx context.Context) error { return p.pool.Ping(ctx) }

// Pool exposes the shared PostgreSQL pool to database-backed infrastructure
// owned by the web process, such as the background job queue.
func (p *Postgres) Pool() *pgxpool.Pool { return p.pool }

func (p *Postgres) Migrate(ctx context.Context) error {
	entries, err := fs.ReadDir(migrations.Files, ".")
	if err != nil {
		return fmt.Errorf("lecture des migrations: %w", err)
	}
	names := make([]string, 0, len(entries))
	for _, entry := range entries {
		if !entry.IsDir() && strings.HasSuffix(entry.Name(), ".sql") {
			names = append(names, entry.Name())
		}
	}
	sort.Strings(names)
	for _, name := range names {
		var exists bool
		err := p.pool.QueryRow(ctx, `SELECT EXISTS (
			SELECT 1 FROM information_schema.tables
			WHERE table_schema='gaylemon_ops' AND table_name='schema_migrations'
		)`).Scan(&exists)
		if err != nil {
			return fmt.Errorf("inspection des migrations: %w", err)
		}
		if exists {
			var applied bool
			if err := p.pool.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM gaylemon_ops.schema_migrations WHERE version=$1)`, name).Scan(&applied); err != nil {
				return err
			}
			if applied {
				continue
			}
		}
		content, err := migrations.Files.ReadFile(name)
		if err != nil {
			return fmt.Errorf("lecture de %s: %w", name, err)
		}
		tx, err := p.pool.Begin(ctx)
		if err != nil {
			return err
		}
		if _, err := tx.Exec(ctx, string(content)); err != nil {
			_ = tx.Rollback(ctx)
			return fmt.Errorf("application de %s: %w", name, err)
		}
		if _, err := tx.Exec(ctx, `INSERT INTO gaylemon_ops.schema_migrations(version) VALUES($1) ON CONFLICT DO NOTHING`, name); err != nil {
			_ = tx.Rollback(ctx)
			return err
		}
		if err := tx.Commit(ctx); err != nil {
			return err
		}
	}
	return nil
}

func (p *Postgres) ClaimNonce(ctx context.Context, agentID, nonce string, expiresAt time.Time) error {
	tx, err := p.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)
	if _, err := tx.Exec(ctx, `DELETE FROM gaylemon_ops.ingest_nonces WHERE expires_at < now()`); err != nil {
		return err
	}
	commandTag, err := tx.Exec(ctx, `INSERT INTO gaylemon_ops.ingest_nonces(agent_id, nonce, expires_at) VALUES($1,$2,$3) ON CONFLICT DO NOTHING`, agentID, nonce, expiresAt)
	if err != nil {
		return err
	}
	if commandTag.RowsAffected() != 1 {
		return ErrReplay
	}
	return tx.Commit(ctx)
}

func (p *Postgres) IngestBatch(ctx context.Context, batch model.Batch, bodyHash string, activate bool) (model.IngestResult, error) {
	if err := validateBatch(batch); err != nil {
		return model.IngestResult{}, err
	}
	var payload model.BatchPayload
	if err := json.Unmarshal(batch.Payload, &payload); err != nil {
		return model.IngestResult{}, fmt.Errorf("%w: payload: %v", ErrInvalidBatch, err)
	}
	for _, document := range payload.Documents {
		if err := validateDocument(document); err != nil {
			return model.IngestResult{}, err
		}
	}
	tx, err := p.pool.BeginTx(ctx, pgx.TxOptions{IsoLevel: pgx.Serializable})
	if err != nil {
		return model.IngestResult{}, err
	}
	defer tx.Rollback(ctx)

	if _, err := tx.Exec(ctx, `INSERT INTO gaylemon_ops.agents(agent_id,last_seen_at,last_success_at) VALUES($1,now(),now())
		ON CONFLICT(agent_id) DO UPDATE SET last_seen_at=now()`, batch.AgentID); err != nil {
		return model.IngestResult{}, err
	}
	var duplicateStatus string
	var duplicateCount int
	err = tx.QueryRow(ctx, `SELECT status, document_count FROM gaylemon_ops.ingest_batches WHERE batch_id=$1`, batch.ID).Scan(&duplicateStatus, &duplicateCount)
	if err == nil {
		var sequence int64
		_ = tx.QueryRow(ctx, `SELECT active_sequence FROM gaylemon_ops.agent_stream_state WHERE agent_id=$1 AND stream=$2`, batch.AgentID, batch.Stream).Scan(&sequence)
		return model.IngestResult{BatchID: batch.ID, Status: "duplicate", Documents: duplicateCount, ActiveSequence: sequence}, nil
	}
	if !errors.Is(err, pgx.ErrNoRows) {
		return model.IngestResult{}, err
	}
	var activeSequence int64
	err = tx.QueryRow(ctx, `SELECT active_sequence FROM gaylemon_ops.agent_stream_state WHERE agent_id=$1 AND stream=$2 FOR UPDATE`, batch.AgentID, batch.Stream).Scan(&activeSequence)
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		return model.IngestResult{}, err
	}
	if batch.Sequence <= activeSequence {
		return model.IngestResult{}, ErrStaleBatch
	}
	status := "shadow"
	if activate {
		status = "active"
	}
	if _, err := tx.Exec(ctx, `INSERT INTO gaylemon_ops.ingest_batches
		(batch_id,agent_id,stream,schema_version,sequence,source_revision,captured_at,body_sha256,status,document_count)
		VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)`, batch.ID, batch.AgentID, batch.Stream, batch.SchemaVersion, batch.Sequence, batch.SourceRevision, batch.CapturedAt, bodyHash, status, len(payload.Documents)); err != nil {
		return model.IngestResult{}, err
	}
	if activate {
		var promotedSaveGeneration string
		if batch.Stream == "snapshot" {
			for _, document := range payload.Documents {
				if document.Path == "data/public-save-index.json" {
					promotedSaveGeneration = document.GenerationID
					break
				}
			}
		}
		if promotedSaveGeneration != "" {
			if _, err := tx.Exec(ctx, `DELETE FROM gaylemon_public.documents
				WHERE generation_id<>$1 AND (
					path LIKE 'data/players/%' OR
					path IN ('data/public-save-index.json','data/public-save-snapshot.json','data/public-save-bases.json','data/public-save-diagnostics.json')
				)`, promotedSaveGeneration); err != nil {
				return model.IngestResult{}, err
			}
		}
		for _, document := range payload.Documents {
			if batch.Stream == "events" && document.Path == "data/public-events.json" {
				var projected int64
				if err := tx.QueryRow(ctx, `SELECT gaylemon_public.replace_events_from_document($1::jsonb,$2)`, string(document.Content), batch.ID).Scan(&projected); err != nil {
					return model.IngestResult{}, err
				}
				continue
			}
			contentHash := sha256.Sum256(document.Content)
			sha := hex.EncodeToString(contentHash[:])
			if _, err := tx.Exec(ctx, `INSERT INTO gaylemon_public.document_contents(sha256,content,content_bytes) VALUES($1,$2::jsonb,$3) ON CONFLICT DO NOTHING`, sha, string(document.Content), []byte(document.Content)); err != nil {
				return model.IngestResult{}, err
			}
			if _, err := tx.Exec(ctx, `INSERT INTO gaylemon_public.documents(path,sha256,cache_policy,generation_id,batch_id,updated_at)
				VALUES($1,$2,$3,$4,$5,now()) ON CONFLICT(path) DO UPDATE SET sha256=excluded.sha256,cache_policy=excluded.cache_policy,generation_id=excluded.generation_id,batch_id=excluded.batch_id,updated_at=now()`, document.Path, sha, document.CachePolicy, document.GenerationID, batch.ID); err != nil {
				return model.IngestResult{}, err
			}
			recordVersion := batch.Stream != "events"
			if recordVersion {
				if _, err := tx.Exec(ctx, `INSERT INTO gaylemon_public.document_versions
					(path,sha256,cache_policy,generation_id,batch_id,agent_id,stream,captured_at,daily_checkpoint)
					VALUES($1,$2,$3,$4,$5,$6,$7,$8::timestamptz,
						$7::text='snapshot' AND NOT EXISTS (
							SELECT 1 FROM gaylemon_public.document_versions
							WHERE path=$1 AND daily_checkpoint=true AND captured_at::date=($8::timestamptz)::date
						)
					) ON CONFLICT DO NOTHING`, document.Path, sha, document.CachePolicy, document.GenerationID, batch.ID, batch.AgentID, batch.Stream, batch.CapturedAt); err != nil {
					return model.IngestResult{}, err
				}
			}
		}
		if batch.Stream == "events" {
			if _, err := tx.Exec(ctx, `DELETE FROM gaylemon_public.document_versions
				WHERE stream='events'`); err != nil {
				return model.IngestResult{}, err
			}
			if _, err := tx.Exec(ctx, `DELETE FROM gaylemon_public.documents
				WHERE path IN ('data/public-events.json','data/public-events-manifest-v6.json','data/public-events-head-v6.json','public-events-channel.json')
				   OR path LIKE 'data/public-events-v6/%'
				   OR path LIKE 'data/public-daily/%'`); err != nil {
				return model.IngestResult{}, err
			}
			if _, err := tx.Exec(ctx, `DELETE FROM gaylemon_public.document_contents contents
				WHERE NOT EXISTS (SELECT 1 FROM gaylemon_public.documents documents WHERE documents.sha256=contents.sha256)
				  AND NOT EXISTS (SELECT 1 FROM gaylemon_public.document_versions versions WHERE versions.sha256=contents.sha256)`); err != nil {
				return model.IngestResult{}, err
			}
		}
	}
	if _, err := tx.Exec(ctx, `INSERT INTO gaylemon_ops.agent_stream_state(agent_id,stream,active_sequence,source_revision,updated_at)
		VALUES($1,$2,$3,$4,now()) ON CONFLICT(agent_id,stream) DO UPDATE SET active_sequence=excluded.active_sequence,source_revision=excluded.source_revision,updated_at=now()`, batch.AgentID, batch.Stream, batch.Sequence, batch.SourceRevision); err != nil {
		return model.IngestResult{}, err
	}
	u := payload.Usage
	if batch.TransportBytes > 0 {
		u.BytesSent = batch.TransportBytes
		if batch.Compressed {
			u.BytesCompressed = batch.TransportBytes
		}
	}
	if _, err := tx.Exec(ctx, `INSERT INTO gaylemon_ops.sync_runs(batch_id,agent_id,stream,captured_at,duration_ms,cpu_user_ms,cpu_system_ms,max_rss_bytes,io_read_bytes,io_write_bytes,bytes_read,bytes_compressed,bytes_sent,status)
		VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14)`, batch.ID, batch.AgentID, batch.Stream, batch.CapturedAt, u.DurationMS, u.CPUUserMS, u.CPUSystemMS, u.MaxRSSBytes, u.IOReadBytes, u.IOWriteBytes, u.BytesRead, u.BytesCompressed, u.BytesSent, status); err != nil {
		return model.IngestResult{}, err
	}
	if _, err := tx.Exec(ctx, `UPDATE gaylemon_ops.agents SET last_seen_at=now(),last_success_at=now(),last_error='' WHERE agent_id=$1`, batch.AgentID); err != nil {
		return model.IngestResult{}, err
	}
	if err := tx.Commit(ctx); err != nil {
		return model.IngestResult{}, err
	}
	return model.IngestResult{BatchID: batch.ID, Status: status, Documents: len(payload.Documents), ActiveSequence: batch.Sequence}, nil
}

func validateBatch(batch model.Batch) error {
	if batch.ID == "" || len(batch.ID) > 128 || batch.AgentID == "" || batch.Stream == "" || batch.SchemaVersion < 1 || batch.Sequence < 1 || batch.CapturedAt.IsZero() || len(batch.Payload) == 0 {
		return ErrInvalidBatch
	}
	if len(batch.Stream) > 64 || strings.ContainsAny(batch.Stream, "\r\n\x00") {
		return ErrInvalidBatch
	}
	return nil
}

func validateDocument(document model.Document) error {
	clean := path.Clean("/" + strings.TrimSpace(document.Path))
	clean = strings.TrimPrefix(clean, "/")
	if clean != document.Path || strings.Contains(clean, "..") || len(clean) > 512 || len(document.Content) == 0 || !json.Valid(document.Content) {
		return fmt.Errorf("%w: document %q", ErrInvalidBatch, document.Path)
	}
	allowed := clean == "public-events-channel.json" || strings.HasPrefix(clean, "data/public-") || strings.HasPrefix(clean, "data/players/")
	if !allowed {
		return fmt.Errorf("%w: chemin public refusé %q", ErrInvalidBatch, clean)
	}
	switch document.CachePolicy {
	case model.CacheNoStore, model.CacheRevalidate, model.CacheImmutable:
	default:
		return fmt.Errorf("%w: cache invalide", ErrInvalidBatch)
	}
	return nil
}

func (p *Postgres) GetPublicDocument(ctx context.Context, documentPath string) (model.PublicDocument, bool, error) {
	var document model.PublicDocument
	var cache string
	err := p.pool.QueryRow(ctx, `SELECT d.path,c.content_bytes,d.cache_policy,d.sha256,d.updated_at
		FROM gaylemon_public.documents d JOIN gaylemon_public.document_contents c ON c.sha256=d.sha256 WHERE d.path=$1`, documentPath).
		Scan(&document.Path, &document.Content, &cache, &document.ETag, &document.UpdatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return model.PublicDocument{}, false, nil
	}
	if err != nil {
		return model.PublicDocument{}, false, err
	}
	document.CachePolicy = model.CachePolicy(cache)
	return document, true, nil
}

func (p *Postgres) QueryPublicEvents(ctx context.Context, query model.PublicEventQuery) (model.PublicEventPage, bool, error) {
	if query.Limit < 1 {
		query.Limit = 6
	}
	maxLimit := 100
	if query.Day != "" {
		maxLimit = 500
	}
	if query.Limit > maxLimit {
		query.Limit = maxLimit
	}
	if query.Offset < 0 {
		query.Offset = 0
	}

	page := model.PublicEventPage{
		OK:            true,
		SchemaVersion: 1,
		Source:        "postgresql",
		Offset:        query.Offset,
		Limit:         query.Limit,
		Date:          query.Day,
		Facets:        map[string][]model.PublicEventFacet{},
	}
	var stateTotal int64
	var facetsJSON []byte
	var summaryJSON []byte
	err := p.pool.QueryRow(ctx, `SELECT revision,source_updated_at,total_echoes,facets::text,summary::text,
		GREATEST(source_updated_at,COALESCE((
			SELECT max(captured_at) FROM gaylemon_ops.sync_runs
			WHERE stream='events-observation' AND status='active'
		),source_updated_at))
		FROM gaylemon_public.event_state WHERE singleton=true`).
		Scan(&page.Revision, &page.UpdatedAt, &stateTotal, &facetsJSON, &summaryJSON, &page.ObservedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return model.PublicEventPage{}, false, nil
	}
	if err != nil {
		return model.PublicEventPage{}, false, err
	}
	page.Freshness, page.SourceStatus, page.LagSeconds = publicEventFreshness(page.ObservedAt, time.Now())
	if err := json.Unmarshal(facetsJSON, &page.Facets); err != nil {
		return model.PublicEventPage{}, false, err
	}
	page.Summary = append(json.RawMessage(nil), summaryJSON...)

	conditions := []string{"true"}
	arguments := []any{}
	if value := strings.TrimSpace(query.Type); value != "" && value != "all" {
		arguments = append(arguments, value)
		conditions = append(conditions, fmt.Sprintf("$%d=ANY(facet_types)", len(arguments)))
	}
	if value := strings.TrimSpace(query.Player); value != "" && value != "all" {
		arguments = append(arguments, value)
		conditions = append(conditions, fmt.Sprintf("player=$%d", len(arguments)))
	}
	if value := strings.ToLower(strings.TrimSpace(query.Search)); value != "" {
		arguments = append(arguments, escapeLikePattern(value))
		conditions = append(conditions, fmt.Sprintf("search_text LIKE '%%'||$%d||'%%' ESCAPE '\\'", len(arguments)))
	}
	if !query.From.IsZero() {
		arguments = append(arguments, query.From)
		conditions = append(conditions, fmt.Sprintf("occurred_at >= $%d", len(arguments)))
	}
	if !query.Before.IsZero() {
		arguments = append(arguments, query.Before)
		conditions = append(conditions, fmt.Sprintf("occurred_at < $%d", len(arguments)))
	}
	where := strings.Join(conditions, " AND ")

	if len(arguments) == 0 {
		page.Total = stateTotal
	} else if err := p.pool.QueryRow(ctx, `SELECT count(*) FROM gaylemon_public.events WHERE `+where, arguments...).Scan(&page.Total); err != nil {
		return model.PublicEventPage{}, false, err
	}

	pageArguments := append(append([]any{}, arguments...), query.Limit, query.Offset)
	rows, err := p.pool.Query(ctx, `WITH page AS MATERIALIZED (
			SELECT event_key,occurred_at,event_id
			FROM gaylemon_public.events
			WHERE `+where+`
			ORDER BY occurred_at DESC,event_id DESC,event_key DESC
			LIMIT $`+strconv.Itoa(len(arguments)+1)+` OFFSET $`+strconv.Itoa(len(arguments)+2)+`
		)
		SELECT stored.payload::text
		FROM page
		JOIN gaylemon_public.events stored USING(event_key)
		ORDER BY page.occurred_at DESC,page.event_id DESC,page.event_key DESC`, pageArguments...)
	if err != nil {
		return model.PublicEventPage{}, false, err
	}
	defer rows.Close()
	for rows.Next() {
		var payload []byte
		if err := rows.Scan(&payload); err != nil {
			return model.PublicEventPage{}, false, err
		}
		page.Events = append(page.Events, append(json.RawMessage(nil), payload...))
	}
	if err := rows.Err(); err != nil {
		return model.PublicEventPage{}, false, err
	}
	if page.Events == nil {
		page.Events = []json.RawMessage{}
	}
	return page, true, nil
}

func (p *Postgres) Maintain(ctx context.Context) (json.RawMessage, error) {
	var result []byte
	err := p.pool.QueryRow(ctx, `SELECT gaylemon_ops.apply_retention()::text`).Scan(&result)
	return json.RawMessage(result), err
}

func (p *Postgres) UpsertHeartbeat(ctx context.Context, status model.AgentStatus) error {
	_, err := p.pool.Exec(ctx, `INSERT INTO gaylemon_ops.agents(agent_id,version,profile,last_seen_at,queue_depth,last_error)
		VALUES($1,$2,$3,now(),$4,$5) ON CONFLICT(agent_id) DO UPDATE SET version=excluded.version,profile=excluded.profile,last_seen_at=now(),queue_depth=excluded.queue_depth,last_error=excluded.last_error`, status.AgentID, status.Version, status.Profile, status.QueueDepth, status.LastError)
	return err
}

func (p *Postgres) PendingCommands(ctx context.Context, agentID string, after int64) ([]model.Command, error) {
	rows, err := p.pool.Query(ctx, `SELECT command_id,sequence,agent_id,kind,arguments::text,requested_at,expires_at,status
		FROM gaylemon_ops.control_commands WHERE agent_id=$1 AND sequence>$2 AND status='pending' AND expires_at>now() ORDER BY sequence LIMIT 50`, agentID, after)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var commands []model.Command
	for rows.Next() {
		var command model.Command
		var arguments []byte
		if err := rows.Scan(&command.ID, &command.Sequence, &command.AgentID, &command.Kind, &arguments, &command.RequestedAt, &command.ExpiresAt, &command.Status); err != nil {
			return nil, err
		}
		command.Arguments = arguments
		commands = append(commands, command)
	}
	return commands, rows.Err()
}

func (p *Postgres) AckCommand(ctx context.Context, agentID, commandID string, ack model.CommandAck) error {
	status := ack.Status
	if status != "completed" && status != "failed" && status != "refused" {
		return errors.New("statut de commande invalide")
	}
	tag, err := p.pool.Exec(ctx, `UPDATE gaylemon_ops.control_commands SET status=$1,acknowledged_at=now(),result_message=$2 WHERE command_id=$3 AND agent_id=$4 AND status='pending'`, status, ack.Message, commandID, agentID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() != 1 {
		return errors.New("commande introuvable ou déjà acquittée")
	}
	return nil
}

func (p *Postgres) EnqueueCommand(ctx context.Context, commandID, agentID, kind string, arguments json.RawMessage, actor string, expiresAt time.Time) (model.Command, error) {
	if len(arguments) == 0 {
		arguments = json.RawMessage(`{}`)
	}
	var command model.Command
	err := p.pool.QueryRow(ctx, `INSERT INTO gaylemon_ops.control_commands(command_id,agent_id,kind,arguments,requested_by,expires_at)
		VALUES($1,$2,$3,$4::jsonb,$5,$6) RETURNING command_id,sequence,agent_id,kind,arguments::text,requested_at,expires_at,status`, commandID, agentID, kind, string(arguments), actor, expiresAt).
		Scan(&command.ID, &command.Sequence, &command.AgentID, &command.Kind, &command.Arguments, &command.RequestedAt, &command.ExpiresAt, &command.Status)
	if err != nil {
		return model.Command{}, err
	}
	_, _ = p.pool.Exec(ctx, `INSERT INTO gaylemon_ops.audit_log(actor,action,target,details) VALUES($1,'command.enqueue',$2,jsonb_build_object('kind',$3,'commandId',$4))`, actor, agentID, kind, commandID)
	return command, nil
}

func (p *Postgres) CreateOAuthState(ctx context.Context, stateHash, verifier, returnPath string, expiresAt time.Time) error {
	_, err := p.pool.Exec(ctx, `INSERT INTO gaylemon_ops.oauth_states(state_hash,verifier,return_path,expires_at) VALUES($1,$2,$3,$4)`, stateHash, verifier, returnPath, expiresAt)
	return err
}

func (p *Postgres) ConsumeOAuthState(ctx context.Context, stateHash string, now time.Time) (OAuthState, error) {
	var state OAuthState
	tag, err := p.pool.Exec(ctx, `DELETE FROM gaylemon_ops.oauth_states WHERE expires_at<$1`, now)
	_ = tag
	if err != nil {
		return state, err
	}
	err = p.pool.QueryRow(ctx, `DELETE FROM gaylemon_ops.oauth_states WHERE state_hash=$1 AND expires_at>$2 RETURNING verifier,return_path`, stateHash, now).Scan(&state.Verifier, &state.ReturnPath)
	if errors.Is(err, pgx.ErrNoRows) {
		return state, ErrOAuthState
	}
	return state, err
}

func (p *Postgres) CreateSession(ctx context.Context, tokenHash string, githubUserID int64, githubLogin string, expiresAt time.Time) error {
	_, err := p.pool.Exec(ctx, `INSERT INTO gaylemon_ops.sessions(token_hash,github_user_id,github_login,expires_at) VALUES($1,$2,$3,$4)`, tokenHash, githubUserID, githubLogin, expiresAt)
	return err
}

func (p *Postgres) GetSession(ctx context.Context, tokenHash string, now time.Time) (Session, bool, error) {
	var session Session
	err := p.pool.QueryRow(ctx, `UPDATE gaylemon_ops.sessions SET last_seen_at=$2 WHERE token_hash=$1 AND expires_at>$2 RETURNING github_user_id,github_login,created_at,expires_at`, tokenHash, now).
		Scan(&session.GitHubUserID, &session.GitHubLogin, &session.CreatedAt, &session.ExpiresAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return Session{}, false, nil
	}
	return session, err == nil, err
}

func (p *Postgres) DeleteSession(ctx context.Context, tokenHash string) error {
	_, err := p.pool.Exec(ctx, `DELETE FROM gaylemon_ops.sessions WHERE token_hash=$1`, tokenHash)
	return err
}

func (p *Postgres) Dashboard(ctx context.Context) (model.DashboardSnapshot, error) {
	snapshot := model.DashboardSnapshot{GeneratedAt: time.Now().UTC()}
	rows, err := p.pool.Query(ctx, `SELECT agent_id,last_seen_at,version,profile,queue_depth,COALESCE(last_success_at,'epoch'::timestamptz),last_error FROM gaylemon_ops.agents ORDER BY agent_id`)
	if err != nil {
		return snapshot, err
	}
	for rows.Next() {
		var agent model.AgentStatus
		if err := rows.Scan(&agent.AgentID, &agent.LastSeenAt, &agent.Version, &agent.Profile, &agent.QueueDepth, &agent.LastSuccessAt, &agent.LastError); err != nil {
			rows.Close()
			return snapshot, err
		}
		snapshot.Agents = append(snapshot.Agents, agent)
	}
	rows.Close()
	runRows, err := p.pool.Query(ctx, `SELECT stream,captured_at,duration_ms,cpu_user_ms+cpu_system_ms AS cpu_ms,max_rss_bytes,bytes_sent,status FROM gaylemon_ops.sync_runs ORDER BY captured_at DESC LIMIT 100`)
	if err != nil {
		return snapshot, err
	}
	for runRows.Next() {
		var stream, status string
		var captured time.Time
		var duration, cpu, rss, bytesSent int64
		if err := runRows.Scan(&stream, &captured, &duration, &cpu, &rss, &bytesSent, &status); err != nil {
			runRows.Close()
			return snapshot, err
		}
		snapshot.RecentRuns = append(snapshot.RecentRuns, map[string]any{"stream": stream, "capturedAt": captured, "durationMs": duration, "cpuMs": cpu, "maxRssBytes": rss, "bytesSent": bytesSent, "status": status})
	}
	runRows.Close()
	commandRows, err := p.pool.Query(ctx, `SELECT command_id,agent_id,kind,status,requested_by,requested_at,expires_at,result_message FROM gaylemon_ops.control_commands ORDER BY requested_at DESC LIMIT 50`)
	if err != nil {
		return snapshot, err
	}
	for commandRows.Next() {
		var id, agent, kind, status, actor, message string
		var requested, expires time.Time
		if err := commandRows.Scan(&id, &agent, &kind, &status, &actor, &requested, &expires, &message); err != nil {
			commandRows.Close()
			return snapshot, err
		}
		snapshot.RecentCommands = append(snapshot.RecentCommands, map[string]any{"id": id, "agentId": agent, "kind": kind, "status": status, "actor": actor, "requestedAt": requested, "expiresAt": expires, "message": message})
	}
	commandRows.Close()
	_ = p.pool.QueryRow(ctx, `SELECT pg_database_size(current_database())`).Scan(&snapshot.DatabaseBytes)
	return snapshot, nil
}
