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
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/MathieuLF/gaylemon/db/migrations"
	"github.com/MathieuLF/gaylemon/internal/model"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

var (
	ErrReplay         = errors.New("nonce déjà utilisé")
	ErrStaleBatch     = errors.New("lot plus ancien que la séquence active")
	ErrInvalidBatch   = errors.New("lot invalide")
	ErrOAuthState     = errors.New("état OAuth invalide ou expiré")
	ErrSeasonArchived = errors.New("la saison n'accepte plus de synchronisation")
	ErrSeasonConflict = errors.New("transition de saison refusée")
)

const publicEventStaleAfter = 25 * time.Minute

var (
	seasonSlugPattern = regexp.MustCompile(`^[a-z0-9]+(?:-[a-z0-9]+)*$`)
	hexDigestPattern  = regexp.MustCompile(`^[0-9a-f]{64}$`)
	processIDPattern  = regexp.MustCompile(`^[1-9][0-9]*$`)
	counterPattern    = regexp.MustCompile(`^[0-9]+$`)
)

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
	if _, err := tx.Exec(ctx, `SELECT pg_advisory_xact_lock(hashtextextended('gaylemon-season-lifecycle',0))`); err != nil {
		return model.IngestResult{}, err
	}
	var seasonID string
	if err := tx.QueryRow(ctx, `SELECT season_id FROM gaylemon_ops.seasons WHERE state IN ('active','finalizing') FOR SHARE`).Scan(&seasonID); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return model.IngestResult{}, ErrSeasonArchived
		}
		return model.IngestResult{}, err
	}

	if _, err := tx.Exec(ctx, `INSERT INTO gaylemon_ops.agents(agent_id,last_seen_at,last_success_at) VALUES($1,now(),now())
		ON CONFLICT(agent_id) DO UPDATE SET last_seen_at=now()`, batch.AgentID); err != nil {
		return model.IngestResult{}, err
	}
	var duplicateStatus string
	var duplicateCount int
	err = tx.QueryRow(ctx, `SELECT status, document_count FROM gaylemon_ops.ingest_batches WHERE batch_id=$1`, batch.ID).Scan(&duplicateStatus, &duplicateCount)
	if err == nil {
		var sequence int64
		_ = tx.QueryRow(ctx, `SELECT active_sequence FROM gaylemon_ops.agent_stream_state WHERE agent_id=$1 AND season_id=$2 AND stream=$3`, batch.AgentID, seasonID, batch.Stream).Scan(&sequence)
		return model.IngestResult{BatchID: batch.ID, Status: "duplicate", Documents: duplicateCount, ActiveSequence: sequence}, nil
	}
	if !errors.Is(err, pgx.ErrNoRows) {
		return model.IngestResult{}, err
	}
	var activeSequence int64
	err = tx.QueryRow(ctx, `SELECT active_sequence FROM gaylemon_ops.agent_stream_state WHERE agent_id=$1 AND season_id=$2 AND stream=$3 FOR UPDATE`, batch.AgentID, seasonID, batch.Stream).Scan(&activeSequence)
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
		(batch_id,agent_id,season_id,stream,schema_version,sequence,source_revision,captured_at,body_sha256,status,document_count)
		VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)`, batch.ID, batch.AgentID, seasonID, batch.Stream, batch.SchemaVersion, batch.Sequence, batch.SourceRevision, batch.CapturedAt, bodyHash, status, len(payload.Documents)); err != nil {
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
				WHERE season_id=$1 AND generation_id<>$2 AND (
					path LIKE 'data/players/%' OR
					path IN ('data/public-save-index.json','data/public-save-snapshot.json','data/public-save-bases.json','data/public-save-diagnostics.json')
				)`, seasonID, promotedSaveGeneration); err != nil {
				return model.IngestResult{}, err
			}
		}
		for _, document := range payload.Documents {
			if batch.Stream == "events" && document.Path == "data/public-events.json" {
				var projected int64
				if err := tx.QueryRow(ctx, `SELECT gaylemon_public.replace_events_from_document($1::jsonb,$2,$3)`, string(document.Content), batch.ID, seasonID).Scan(&projected); err != nil {
					return model.IngestResult{}, err
				}
				continue
			}
			contentHash := sha256.Sum256(document.Content)
			sha := hex.EncodeToString(contentHash[:])
			if _, err := tx.Exec(ctx, `INSERT INTO gaylemon_public.document_contents(sha256,content,content_bytes) VALUES($1,$2::jsonb,$3) ON CONFLICT DO NOTHING`, sha, string(document.Content), []byte(document.Content)); err != nil {
				return model.IngestResult{}, err
			}
			if _, err := tx.Exec(ctx, `INSERT INTO gaylemon_public.documents(season_id,path,sha256,cache_policy,generation_id,batch_id,updated_at)
				VALUES($1,$2,$3,$4,$5,$6,now()) ON CONFLICT(season_id,path) DO UPDATE SET sha256=excluded.sha256,cache_policy=excluded.cache_policy,generation_id=excluded.generation_id,batch_id=excluded.batch_id,updated_at=now()`, seasonID, document.Path, sha, document.CachePolicy, document.GenerationID, batch.ID); err != nil {
				return model.IngestResult{}, err
			}
			recordVersion := batch.Stream != "events"
			if recordVersion {
				if _, err := tx.Exec(ctx, `INSERT INTO gaylemon_public.document_versions
					(season_id,path,sha256,cache_policy,generation_id,batch_id,agent_id,stream,captured_at,daily_checkpoint)
					VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9::timestamptz,
						$8::text='snapshot' AND NOT EXISTS (
							SELECT 1 FROM gaylemon_public.document_versions
							WHERE season_id=$1 AND path=$2 AND daily_checkpoint=true AND captured_at::date=($9::timestamptz)::date
						)
					) ON CONFLICT DO NOTHING`, seasonID, document.Path, sha, document.CachePolicy, document.GenerationID, batch.ID, batch.AgentID, batch.Stream, batch.CapturedAt); err != nil {
					return model.IngestResult{}, err
				}
			}
		}
		if batch.Stream == "events" {
			if _, err := tx.Exec(ctx, `DELETE FROM gaylemon_public.document_versions
				WHERE season_id=$1 AND stream='events'`, seasonID); err != nil {
				return model.IngestResult{}, err
			}
			if _, err := tx.Exec(ctx, `DELETE FROM gaylemon_public.documents
				WHERE season_id=$1 AND (path IN ('data/public-events.json','data/public-events-manifest-v6.json','data/public-events-head-v6.json','public-events-channel.json')
				   OR path LIKE 'data/public-events-v6/%'
				   OR path LIKE 'data/public-daily/%')`, seasonID); err != nil {
				return model.IngestResult{}, err
			}
			if _, err := tx.Exec(ctx, `DELETE FROM gaylemon_public.document_contents contents
				WHERE NOT EXISTS (SELECT 1 FROM gaylemon_public.documents documents WHERE documents.sha256=contents.sha256)
				  AND NOT EXISTS (SELECT 1 FROM gaylemon_public.document_versions versions WHERE versions.sha256=contents.sha256)`); err != nil {
				return model.IngestResult{}, err
			}
		}
	}
	if _, err := tx.Exec(ctx, `INSERT INTO gaylemon_ops.agent_stream_state(agent_id,season_id,stream,active_sequence,source_revision,updated_at)
		VALUES($1,$2,$3,$4,$5,now()) ON CONFLICT(agent_id,season_id,stream) DO UPDATE SET active_sequence=excluded.active_sequence,source_revision=excluded.source_revision,updated_at=now()`, batch.AgentID, seasonID, batch.Stream, batch.Sequence, batch.SourceRevision); err != nil {
		return model.IngestResult{}, err
	}
	u := payload.Usage
	if batch.TransportBytes > 0 {
		u.BytesSent = batch.TransportBytes
		if batch.Compressed {
			u.BytesCompressed = batch.TransportBytes
		}
	}
	if _, err := tx.Exec(ctx, `INSERT INTO gaylemon_ops.sync_runs(batch_id,agent_id,season_id,stream,captured_at,duration_ms,cpu_user_ms,cpu_system_ms,max_rss_bytes,io_read_bytes,io_write_bytes,bytes_read,bytes_compressed,bytes_sent,status)
		VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15)`, batch.ID, batch.AgentID, seasonID, batch.Stream, batch.CapturedAt, u.DurationMS, u.CPUUserMS, u.CPUSystemMS, u.MaxRSSBytes, u.IOReadBytes, u.IOWriteBytes, u.BytesRead, u.BytesCompressed, u.BytesSent, status); err != nil {
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
	return p.GetPublicDocumentForSeason(ctx, "", documentPath)
}

func (p *Postgres) GetPublicDocumentForSeason(ctx context.Context, slug, documentPath string) (model.PublicDocument, bool, error) {
	var document model.PublicDocument
	var cache string
	season, found, err := p.ResolveSeason(ctx, slug)
	if err != nil || !found {
		return model.PublicDocument{}, false, err
	}
	err = p.pool.QueryRow(ctx, `SELECT d.path,c.content_bytes,d.cache_policy,d.sha256,d.updated_at
		FROM gaylemon_public.documents d JOIN gaylemon_public.document_contents c ON c.sha256=d.sha256 WHERE d.season_id=$1 AND d.path=$2`, season.ID, documentPath).
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
	return p.QueryPublicEventsForSeason(ctx, "", query)
}

func (p *Postgres) QueryPublicEventsForSeason(ctx context.Context, slug string, query model.PublicEventQuery) (model.PublicEventPage, bool, error) {
	season, found, err := p.ResolveSeason(ctx, slug)
	if err != nil || !found {
		return model.PublicEventPage{}, false, err
	}
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
	err = p.pool.QueryRow(ctx, `SELECT revision,source_updated_at,total_echoes,facets::text,summary::text,
		GREATEST(source_updated_at,COALESCE((
			SELECT max(captured_at) FROM gaylemon_ops.sync_runs
			WHERE season_id=$1 AND stream='events-observation' AND status='active'
		),source_updated_at))
		FROM gaylemon_public.event_state WHERE season_id=$1`, season.ID).
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

	conditions := []string{"season_id=$1"}
	arguments := []any{season.ID}
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

	if len(arguments) == 1 {
		page.Total = stateTotal
	} else if err := p.pool.QueryRow(ctx, `SELECT count(*) FROM gaylemon_public.events WHERE `+where, arguments...).Scan(&page.Total); err != nil {
		return model.PublicEventPage{}, false, err
	}

	pageArguments := append(append([]any{}, arguments...), query.Limit, query.Offset)
	rows, err := p.pool.Query(ctx, `WITH page AS MATERIALIZED (
			SELECT event_key,occurred_at,event_id,payload
			FROM gaylemon_public.events
			WHERE `+where+`
			ORDER BY occurred_at DESC,event_id DESC,event_key DESC
			LIMIT $`+strconv.Itoa(len(arguments)+1)+` OFFSET $`+strconv.Itoa(len(arguments)+2)+`
		)
		SELECT page.payload::text FROM page
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
	if err := p.expireSeasonTransitions(ctx); err != nil {
		return nil, err
	}
	var result []byte
	err := p.pool.QueryRow(ctx, `SELECT gaylemon_ops.apply_retention()::text`).Scan(&result)
	return json.RawMessage(result), err
}

func (p *Postgres) expireSeasonTransitions(ctx context.Context) error {
	tx, err := p.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)
	if _, err := tx.Exec(ctx, `SELECT pg_advisory_xact_lock(hashtextextended('gaylemon-season-lifecycle',0))`); err != nil {
		return err
	}
	if _, err := tx.Exec(ctx, `WITH expired AS (
		UPDATE gaylemon_ops.control_commands
		SET status='failed', acknowledged_at=now(), result_message='commande expirée avant acquittement'
		WHERE status='pending' AND expires_at<=now() AND kind IN ('season.archive','season.activate')
		RETURNING command_id,agent_id,kind,arguments
	), recovery_needed AS (
		SELECT seasons.season_id,seasons.slug,expired.command_id,expired.agent_id
		FROM gaylemon_ops.seasons seasons JOIN expired ON seasons.season_id=expired.arguments->>'seasonId'
		WHERE expired.kind='season.archive' AND seasons.state='finalizing'
	), compensation AS (
		INSERT INTO gaylemon_ops.control_commands(command_id,agent_id,kind,arguments,requested_by,expires_at)
		SELECT 'recover-'||command_id,agent_id,'season.activate',
			jsonb_build_object('seasonId',season_id,'slug',slug,'transition','recover'),'system',now()+interval '6 hours'
		FROM recovery_needed
		ON CONFLICT(command_id) DO NOTHING
		RETURNING command_id
	), recovery_failed AS (
		UPDATE gaylemon_ops.seasons seasons SET state='failed',updated_at=now()
		FROM expired
		WHERE expired.kind='season.activate' AND expired.arguments->>'transition'='recover'
			AND seasons.season_id=expired.arguments->>'seasonId' AND seasons.state='finalizing'
		RETURNING seasons.season_id,expired.command_id
	)
	INSERT INTO gaylemon_ops.season_lifecycle_events(season_id,event_type,actor,details)
	SELECT recovery_needed.season_id,'failed','system',jsonb_build_object('transition','archive','reason','command-expired','recovery','pending','compensationCommandId','recover-'||recovery_needed.command_id)
	FROM recovery_needed
	UNION ALL
	SELECT recovery_failed.season_id,'failed','system',jsonb_build_object('transition','recover','reason','compensation-expired','commandId',recovery_failed.command_id)
	FROM recovery_failed`); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

func scanSeason(row pgx.Row) (model.Season, error) {
	var season model.Season
	var manifest []byte
	var endsOn *string
	err := row.Scan(&season.ID, &season.Slug, &season.Title, &season.StartsOn, &endsOn, &season.State,
		&manifest, &season.FinalSHA256, &season.CreatedAt, &season.UpdatedAt, &season.ArchivedAt)
	if err != nil {
		return model.Season{}, err
	}
	if endsOn != nil {
		season.EndsOn = *endsOn
	}
	season.Manifest = append(json.RawMessage(nil), manifest...)
	return season, nil
}

const seasonColumns = `season_id,slug,title,starts_on::text,ends_on::text,state,manifest::text,final_sha256,created_at,updated_at,archived_at`

func (p *Postgres) ResolveSeason(ctx context.Context, slug string) (model.Season, bool, error) {
	var row pgx.Row
	if slug == "" {
		row = p.pool.QueryRow(ctx, `SELECT `+seasonColumns+` FROM gaylemon_ops.seasons
			WHERE state IN ('active','finalizing','archived')
			ORDER BY CASE state WHEN 'active' THEN 0 WHEN 'finalizing' THEN 1 ELSE 2 END, archived_at DESC NULLS LAST, starts_on DESC LIMIT 1`)
	} else {
		row = p.pool.QueryRow(ctx, `SELECT `+seasonColumns+` FROM gaylemon_ops.seasons
			WHERE slug=$1 AND state IN ('active','finalizing','archived')`, slug)
	}
	season, err := scanSeason(row)
	if errors.Is(err, pgx.ErrNoRows) {
		return model.Season{}, false, nil
	}
	return season, err == nil, err
}

func (p *Postgres) ListSeasons(ctx context.Context) ([]model.Season, error) {
	rows, err := p.pool.Query(ctx, `SELECT `+seasonColumns+` FROM gaylemon_ops.seasons ORDER BY starts_on DESC,season_id DESC`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	seasons := make([]model.Season, 0)
	for rows.Next() {
		season, err := scanSeason(rows)
		if err != nil {
			return nil, err
		}
		seasons = append(seasons, season)
	}
	return seasons, rows.Err()
}

func validateSeasonCreate(input model.SeasonCreate) error {
	if !seasonSlugPattern.MatchString(input.Slug) || len(input.Slug) > 80 || len(strings.TrimSpace(input.Title)) == 0 || len(input.Title) > 120 {
		return ErrInvalidBatch
	}
	parsed, err := time.Parse(time.DateOnly, input.StartsOn)
	if err != nil || parsed.Format(time.DateOnly) != input.StartsOn {
		return ErrInvalidBatch
	}
	return nil
}

func (p *Postgres) CreateSeason(ctx context.Context, input model.SeasonCreate, actor string) (model.Season, error) {
	input.Slug = strings.TrimSpace(strings.ToLower(input.Slug))
	input.Title = strings.TrimSpace(input.Title)
	if err := validateSeasonCreate(input); err != nil {
		return model.Season{}, err
	}
	sum := sha256.Sum256([]byte(input.Slug + "\x00" + actor + "\x00" + time.Now().UTC().Format(time.RFC3339Nano)))
	seasonID := "season-" + hex.EncodeToString(sum[:12])
	tx, err := p.pool.BeginTx(ctx, pgx.TxOptions{IsoLevel: pgx.Serializable})
	if err != nil {
		return model.Season{}, err
	}
	defer tx.Rollback(ctx)
	season, err := scanSeason(tx.QueryRow(ctx, `INSERT INTO gaylemon_ops.seasons(season_id,slug,title,starts_on,state)
		VALUES($1,$2,$3,$4::date,'draft') RETURNING `+seasonColumns, seasonID, input.Slug, input.Title, input.StartsOn))
	if err != nil {
		return model.Season{}, err
	}
	if _, err := tx.Exec(ctx, `INSERT INTO gaylemon_ops.season_lifecycle_events(season_id,event_type,actor,details)
		VALUES($1,'created',$2,jsonb_build_object('slug',$3::text))`, seasonID, actor, input.Slug); err != nil {
		return model.Season{}, err
	}
	return season, tx.Commit(ctx)
}

func (p *Postgres) ActivateSeasonWithCommand(ctx context.Context, seasonID, agentID, commandID, actor string, expiresAt time.Time) (model.Season, model.Command, error) {
	tx, err := p.pool.BeginTx(ctx, pgx.TxOptions{IsoLevel: pgx.Serializable})
	if err != nil {
		return model.Season{}, model.Command{}, err
	}
	defer tx.Rollback(ctx)
	if _, err := tx.Exec(ctx, `SELECT pg_advisory_xact_lock(hashtextextended('gaylemon-season-lifecycle',0))`); err != nil {
		return model.Season{}, model.Command{}, err
	}
	var occupied bool
	if err := tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM gaylemon_ops.seasons WHERE state IN ('active','finalizing') AND season_id<>$1)`, seasonID).Scan(&occupied); err != nil {
		return model.Season{}, model.Command{}, err
	}
	if occupied {
		return model.Season{}, model.Command{}, ErrSeasonConflict
	}
	season, err := scanSeason(tx.QueryRow(ctx, `SELECT `+seasonColumns+` FROM gaylemon_ops.seasons
		WHERE season_id=$1 AND state IN ('draft','failed') FOR UPDATE`, seasonID))
	if errors.Is(err, pgx.ErrNoRows) {
		return model.Season{}, model.Command{}, ErrSeasonConflict
	}
	if err != nil {
		return model.Season{}, model.Command{}, err
	}
	var pending bool
	if err := tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM gaylemon_ops.control_commands WHERE kind='season.activate' AND status='pending' AND expires_at>now())`).Scan(&pending); err != nil {
		return model.Season{}, model.Command{}, err
	}
	if pending {
		return model.Season{}, model.Command{}, ErrSeasonConflict
	}
	arguments, _ := json.Marshal(map[string]string{"seasonId": season.ID, "slug": season.Slug, "transition": "activate"})
	var command model.Command
	if err := tx.QueryRow(ctx, `INSERT INTO gaylemon_ops.control_commands(command_id,agent_id,kind,arguments,requested_by,expires_at)
		VALUES($1,$2,'season.activate',$3::jsonb,$4,$5) RETURNING command_id,sequence,agent_id,kind,arguments::text,requested_at,expires_at,status`, commandID, agentID, string(arguments), actor, expiresAt).
		Scan(&command.ID, &command.Sequence, &command.AgentID, &command.Kind, &command.Arguments, &command.RequestedAt, &command.ExpiresAt, &command.Status); err != nil {
		return model.Season{}, model.Command{}, err
	}
	if err := tx.Commit(ctx); err != nil {
		return model.Season{}, model.Command{}, err
	}
	return season, command, nil
}

func (p *Postgres) BeginSeasonArchive(ctx context.Context, seasonID, agentID, commandID, actor string, expiresAt time.Time) (model.Command, error) {
	tx, err := p.pool.BeginTx(ctx, pgx.TxOptions{IsoLevel: pgx.Serializable})
	if err != nil {
		return model.Command{}, err
	}
	defer tx.Rollback(ctx)
	if _, err := tx.Exec(ctx, `SELECT pg_advisory_xact_lock(hashtextextended('gaylemon-season-lifecycle',0))`); err != nil {
		return model.Command{}, err
	}
	var slug string
	if err := tx.QueryRow(ctx, `UPDATE gaylemon_ops.seasons SET state='finalizing',updated_at=now()
		WHERE season_id=$1 AND state='active' RETURNING slug`, seasonID).Scan(&slug); errors.Is(err, pgx.ErrNoRows) {
		return model.Command{}, ErrSeasonConflict
	} else if err != nil {
		return model.Command{}, err
	}
	details, _ := json.Marshal(map[string]string{"seasonId": seasonID, "slug": slug})
	var command model.Command
	if err := tx.QueryRow(ctx, `INSERT INTO gaylemon_ops.control_commands(command_id,agent_id,kind,arguments,requested_by,expires_at)
		VALUES($1,$2,'season.archive',$3::jsonb,$4,$5)
		RETURNING command_id,sequence,agent_id,kind,arguments::text,requested_at,expires_at,status`, commandID, agentID, string(details), actor, expiresAt).
		Scan(&command.ID, &command.Sequence, &command.AgentID, &command.Kind, &command.Arguments, &command.RequestedAt, &command.ExpiresAt, &command.Status); err != nil {
		return model.Command{}, err
	}
	if _, err := tx.Exec(ctx, `INSERT INTO gaylemon_ops.season_lifecycle_events(season_id,event_type,actor,details)
		VALUES($1,'finalizing',$2,jsonb_build_object('commandId',$3::text))`, seasonID, actor, commandID); err != nil {
		return model.Command{}, err
	}
	return command, tx.Commit(ctx)
}

func (p *Postgres) ReopenSeason(ctx context.Context, seasonID, agentID, commandID, actor string, expiresAt time.Time) (model.Season, model.Command, error) {
	tx, err := p.pool.BeginTx(ctx, pgx.TxOptions{IsoLevel: pgx.Serializable})
	if err != nil {
		return model.Season{}, model.Command{}, err
	}
	defer tx.Rollback(ctx)
	if _, err := tx.Exec(ctx, `SELECT pg_advisory_xact_lock(hashtextextended('gaylemon-season-lifecycle',0))`); err != nil {
		return model.Season{}, model.Command{}, err
	}
	var blocked bool
	if err := tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM gaylemon_ops.seasons WHERE state IN ('active','finalizing') OR (season_id<>$1 AND created_at>(SELECT created_at FROM gaylemon_ops.seasons WHERE season_id=$1)))`, seasonID).Scan(&blocked); err != nil {
		return model.Season{}, model.Command{}, err
	}
	if blocked {
		return model.Season{}, model.Command{}, ErrSeasonConflict
	}
	season, err := scanSeason(tx.QueryRow(ctx, `SELECT `+seasonColumns+` FROM gaylemon_ops.seasons
		WHERE season_id=$1 AND state IN ('archived','failed') FOR UPDATE`, seasonID))
	if errors.Is(err, pgx.ErrNoRows) {
		return model.Season{}, model.Command{}, ErrSeasonConflict
	}
	if err != nil {
		return model.Season{}, model.Command{}, err
	}
	var pending bool
	if err := tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM gaylemon_ops.control_commands WHERE kind='season.activate' AND status='pending' AND expires_at>now())`).Scan(&pending); err != nil {
		return model.Season{}, model.Command{}, err
	}
	if pending {
		return model.Season{}, model.Command{}, ErrSeasonConflict
	}
	arguments, _ := json.Marshal(map[string]string{"seasonId": season.ID, "slug": season.Slug, "transition": "reopen"})
	var command model.Command
	if err := tx.QueryRow(ctx, `INSERT INTO gaylemon_ops.control_commands(command_id,agent_id,kind,arguments,requested_by,expires_at)
		VALUES($1,$2,'season.activate',$3::jsonb,$4,$5) RETURNING command_id,sequence,agent_id,kind,arguments::text,requested_at,expires_at,status`, commandID, agentID, string(arguments), actor, expiresAt).
		Scan(&command.ID, &command.Sequence, &command.AgentID, &command.Kind, &command.Arguments, &command.RequestedAt, &command.ExpiresAt, &command.Status); err != nil {
		return model.Season{}, model.Command{}, err
	}
	if err := tx.Commit(ctx); err != nil {
		return model.Season{}, model.Command{}, err
	}
	return season, command, nil
}

func (p *Postgres) UpsertHeartbeat(ctx context.Context, status model.AgentStatus) error {
	_, err := p.pool.Exec(ctx, `INSERT INTO gaylemon_ops.agents(agent_id,version,profile,last_seen_at,queue_depth,last_error)
		VALUES($1,$2,$3,now(),$4,$5) ON CONFLICT(agent_id) DO UPDATE SET version=excluded.version,profile=excluded.profile,last_seen_at=now(),queue_depth=excluded.queue_depth,last_error=excluded.last_error`, status.AgentID, status.Version, status.Profile, status.QueueDepth, status.LastError)
	return err
}

func (p *Postgres) PendingCommands(ctx context.Context, agentID string, after int64) ([]model.Command, error) {
	if err := p.expireSeasonTransitions(ctx); err != nil {
		return nil, err
	}
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
	details := ack.Details
	if len(details) == 0 || !json.Valid(details) {
		details = json.RawMessage(`{}`)
	}
	tx, err := p.pool.BeginTx(ctx, pgx.TxOptions{IsoLevel: pgx.Serializable})
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)
	var kind string
	var arguments []byte
	err = tx.QueryRow(ctx, `UPDATE gaylemon_ops.control_commands SET status=$1,acknowledged_at=now(),result_message=$2,result_details=$3::jsonb
		WHERE command_id=$4 AND agent_id=$5 AND status='pending' RETURNING kind,arguments::text`, status, ack.Message, string(details), commandID, agentID).
		Scan(&kind, &arguments)
	if errors.Is(err, pgx.ErrNoRows) {
		return errors.New("commande introuvable ou déjà acquittée")
	}
	if err != nil {
		return err
	}
	if kind == "season.activate" {
		var request struct {
			SeasonID   string `json:"seasonId"`
			Slug       string `json:"slug"`
			Transition string `json:"transition"`
		}
		if json.Unmarshal(arguments, &request) != nil || request.SeasonID == "" || request.Slug == "" ||
			(request.Transition != "activate" && request.Transition != "reopen" && request.Transition != "recover") {
			return errors.New("commande d'activation de saison invalide")
		}
		if _, err := tx.Exec(ctx, `SELECT pg_advisory_xact_lock(hashtextextended('gaylemon-season-lifecycle',0))`); err != nil {
			return err
		}
		if status == "completed" {
			if err := validateSeasonActivateProof(details, request.SeasonID, request.Slug); err != nil {
				return err
			}
			allowedState := "draft"
			if request.Transition == "reopen" {
				allowedState = "archived"
			} else if request.Transition == "recover" {
				allowedState = "finalizing"
			}
			var occupied bool
			if err := tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM gaylemon_ops.seasons WHERE state IN ('active','finalizing') AND season_id<>$1)`, request.SeasonID).Scan(&occupied); err != nil {
				return err
			}
			if occupied {
				return ErrSeasonConflict
			}
			var tag pgconn.CommandTag
			if request.Transition == "recover" {
				tag, err = tx.Exec(ctx, `UPDATE gaylemon_ops.seasons SET state='active',updated_at=now() WHERE season_id=$1 AND state=$2`, request.SeasonID, allowedState)
			} else {
				tag, err = tx.Exec(ctx, `UPDATE gaylemon_ops.seasons SET state='active',updated_at=now(),archived_at=NULL,manifest='{}'::jsonb,final_sha256=''
					WHERE season_id=$1 AND (state=$2 OR state='failed')`, request.SeasonID, allowedState)
			}
			if err != nil || tag.RowsAffected() != 1 {
				if err != nil {
					return err
				}
				return ErrSeasonConflict
			}
			eventType := "activated"
			if request.Transition == "reopen" {
				eventType = "reopened"
			} else if request.Transition == "recover" {
				eventType = "recovered"
			}
			if _, err := tx.Exec(ctx, `INSERT INTO gaylemon_ops.season_lifecycle_events(season_id,event_type,actor,details)
				VALUES($1,$2,$3,jsonb_build_object('commandId',$4::text))`, request.SeasonID, eventType, agentID, commandID); err != nil {
				return err
			}
		} else {
			if request.Transition == "activate" {
				if _, err := tx.Exec(ctx, `UPDATE gaylemon_ops.seasons SET state='failed',updated_at=now() WHERE season_id=$1 AND state IN ('draft','failed')`, request.SeasonID); err != nil {
					return err
				}
			} else if request.Transition == "recover" {
				if _, err := tx.Exec(ctx, `UPDATE gaylemon_ops.seasons SET state='failed',updated_at=now() WHERE season_id=$1 AND state='finalizing'`, request.SeasonID); err != nil {
					return err
				}
			}
			if _, err := tx.Exec(ctx, `INSERT INTO gaylemon_ops.season_lifecycle_events(season_id,event_type,actor,details)
				VALUES($1,'failed',$2,jsonb_build_object('commandId',$3::text,'transition',$4::text,'status',$5::text,'message',$6::text))`, request.SeasonID, agentID, commandID, request.Transition, status, ack.Message); err != nil {
				return err
			}
		}
	}
	if kind == "season.archive" {
		var request struct {
			SeasonID string `json:"seasonId"`
			Slug     string `json:"slug"`
		}
		if json.Unmarshal(arguments, &request) != nil || request.SeasonID == "" || request.Slug == "" {
			return errors.New("commande de saison invalide")
		}
		if _, err := tx.Exec(ctx, `SELECT pg_advisory_xact_lock(hashtextextended('gaylemon-season-lifecycle',0))`); err != nil {
			return err
		}
		if status == "completed" {
			if err := validateSeasonArchiveProof(details, request.SeasonID, request.Slug); err != nil {
				return err
			}
			var manifest []byte
			err := tx.QueryRow(ctx, `SELECT jsonb_build_object(
				'schema','gaylemon.season-manifest.v1','seasonId',$1::text,
				'manifestedThrough',(SELECT updated_at FROM gaylemon_ops.seasons WHERE season_id=$1::text),
				'agentResult',$2::jsonb,
				'documents',COALESCE((SELECT jsonb_agg(jsonb_build_object('path',path,'sha256',sha256,'generationId',generation_id) ORDER BY path) FROM gaylemon_public.documents WHERE season_id=$1::text),'[]'::jsonb),
				'versions',COALESCE((SELECT jsonb_agg(jsonb_build_object('path',path,'sha256',sha256,'capturedAt',captured_at,'generationId',generation_id) ORDER BY captured_at,path,version_id) FROM gaylemon_public.document_versions WHERE season_id=$1::text),'[]'::jsonb),
				'events',COALESCE((SELECT jsonb_agg(jsonb_build_object('key',event_key,'revision',source_revision,'occurredAt',occurred_at) ORDER BY occurred_at,event_id,event_key) FROM gaylemon_public.events WHERE season_id=$1::text),'[]'::jsonb),
				'batches',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',batch_id,'stream',stream,'sequence',sequence,'sha256',body_sha256) ORDER BY stream,sequence,batch_id) FROM gaylemon_ops.ingest_batches WHERE season_id=$1::text),'[]'::jsonb),
				'streams',COALESCE((SELECT jsonb_agg(jsonb_build_object('agentId',agent_id,'stream',stream,'activeSequence',active_sequence,'sourceRevision',source_revision) ORDER BY agent_id,stream) FROM gaylemon_ops.agent_stream_state WHERE season_id=$1::text),'[]'::jsonb)
			)::text`, request.SeasonID, string(details)).Scan(&manifest)
			if err != nil {
				return err
			}
			digest := sha256.Sum256(manifest)
			finalSHA := hex.EncodeToString(digest[:])
			tag, err := tx.Exec(ctx, `UPDATE gaylemon_ops.seasons SET state='archived',ends_on=COALESCE(ends_on,current_date),manifest=$2::jsonb,final_sha256=$3,archived_at=now(),updated_at=now()
				WHERE season_id=$1 AND state='finalizing'`, request.SeasonID, string(manifest), finalSHA)
			if err != nil || tag.RowsAffected() != 1 {
				if err != nil {
					return err
				}
				return ErrSeasonConflict
			}
			if _, err := tx.Exec(ctx, `INSERT INTO gaylemon_ops.season_lifecycle_events(season_id,event_type,actor,details)
				VALUES($1,'archived',$2,jsonb_build_object('commandId',$3::text,'finalSha256',$4::text))`, request.SeasonID, agentID, commandID, finalSHA); err != nil {
				return err
			}
		} else {
			if _, err := tx.Exec(ctx, `UPDATE gaylemon_ops.seasons SET state='active',updated_at=now() WHERE season_id=$1 AND state='finalizing'`, request.SeasonID); err != nil {
				return err
			}
			if _, err := tx.Exec(ctx, `INSERT INTO gaylemon_ops.season_lifecycle_events(season_id,event_type,actor,details)
				VALUES($1,'failed',$2,jsonb_build_object('commandId',$3::text,'transition','archive','rolledBackTo','active','status',$4::text,'message',$5::text))`, request.SeasonID, agentID, commandID, status, ack.Message); err != nil {
				return err
			}
		}
	}
	return tx.Commit(ctx)
}

func validateSeasonArchiveProof(details json.RawMessage, seasonID, slug string) error {
	var proof struct {
		SeasonID         string `json:"seasonId"`
		Slug             string `json:"slug"`
		ImmutableBackup  string `json:"immutableBackup"`
		BackupSHA256     string `json:"backupSha256"`
		Receipt          string `json:"receipt"`
		ReceiptSHA256    string `json:"receiptSha256"`
		QueueDepth       int64  `json:"queueDepth"`
		PalworldPID      string `json:"palworldPid"`
		PalworldRestarts string `json:"palworldRestarts"`
	}
	if err := json.Unmarshal(details, &proof); err != nil {
		return errors.New("preuves de clôture invalides")
	}
	if proof.SeasonID != seasonID || proof.Slug != slug || proof.QueueDepth != 0 {
		return errors.New("preuves de clôture incohérentes")
	}
	backupReference := fmt.Sprintf("urn:gaylemon:season-archive:%s:%s", slug, proof.BackupSHA256)
	receiptReference := fmt.Sprintf("urn:gaylemon:season-receipt:%s:%s", slug, proof.BackupSHA256)
	if !hexDigestPattern.MatchString(proof.BackupSHA256) || proof.ImmutableBackup != backupReference || proof.Receipt != receiptReference ||
		!hexDigestPattern.MatchString(proof.ReceiptSHA256) ||
		!processIDPattern.MatchString(proof.PalworldPID) || !counterPattern.MatchString(proof.PalworldRestarts) {
		return errors.New("preuves de clôture incomplètes")
	}
	return nil
}

func validateSeasonActivateProof(details json.RawMessage, seasonID, slug string) error {
	var proof struct {
		SeasonID         string `json:"seasonId"`
		Slug             string `json:"slug"`
		Activated        bool   `json:"activated"`
		PalworldPID      string `json:"palworldPid"`
		PalworldRestarts string `json:"palworldRestarts"`
	}
	if err := json.Unmarshal(details, &proof); err != nil || proof.SeasonID != seasonID || proof.Slug != slug || !proof.Activated ||
		!processIDPattern.MatchString(proof.PalworldPID) || !counterPattern.MatchString(proof.PalworldRestarts) {
		return errors.New("preuves d'activation de saison invalides")
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
	seasonRows, err := p.pool.Query(ctx, `SELECT `+seasonColumns+` FROM gaylemon_ops.seasons ORDER BY starts_on DESC,season_id DESC`)
	if err != nil {
		return snapshot, err
	}
	for seasonRows.Next() {
		season, err := scanSeason(seasonRows)
		if err != nil {
			seasonRows.Close()
			return snapshot, err
		}
		snapshot.Seasons = append(snapshot.Seasons, season)
	}
	if err := seasonRows.Err(); err != nil {
		seasonRows.Close()
		return snapshot, err
	}
	seasonRows.Close()
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
