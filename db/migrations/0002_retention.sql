CREATE TABLE IF NOT EXISTS gaylemon_public.document_versions (
    version_id bigserial PRIMARY KEY,
    path text NOT NULL,
    sha256 text NOT NULL REFERENCES gaylemon_public.document_contents(sha256),
    cache_policy text NOT NULL CHECK (cache_policy IN ('no-store', 'revalidate', 'immutable')),
    generation_id text NOT NULL DEFAULT '',
    batch_id text REFERENCES gaylemon_ops.ingest_batches(batch_id) ON DELETE SET NULL,
    agent_id text NOT NULL,
    stream text NOT NULL,
    captured_at timestamptz NOT NULL,
    activated_at timestamptz NOT NULL DEFAULT now(),
    daily_checkpoint boolean NOT NULL DEFAULT false
);
CREATE INDEX IF NOT EXISTS document_versions_path_time_idx ON gaylemon_public.document_versions(path, captured_at DESC);
CREATE INDEX IF NOT EXISTS document_versions_stream_time_idx ON gaylemon_public.document_versions(stream, captured_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS document_versions_batch_path_idx ON gaylemon_public.document_versions(batch_id, path) WHERE batch_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS gaylemon_ops.retention_policies (
    category text PRIMARY KEY,
    retention_days integer,
    generations integer,
    updated_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO gaylemon_ops.retention_policies(category, retention_days, generations) VALUES
    ('metrics_and_runs', 365, NULL),
    ('events', NULL, NULL),
    ('snapshot_daily_checkpoints', 365, NULL),
    ('snapshot_detailed_generations', NULL, 7),
    ('audit_and_commands', 365, NULL)
ON CONFLICT(category) DO UPDATE SET retention_days=excluded.retention_days, generations=excluded.generations, updated_at=now();

CREATE OR REPLACE VIEW gaylemon_ops.stream_health AS
SELECT
    agent_id,
    stream,
    count(*) FILTER (WHERE captured_at >= now() - interval '24 hours') AS runs_24h,
    round(avg(duration_ms) FILTER (WHERE captured_at >= now() - interval '24 hours')) AS avg_duration_ms_24h,
    max(duration_ms) FILTER (WHERE captured_at >= now() - interval '24 hours') AS max_duration_ms_24h,
    max(max_rss_bytes) FILTER (WHERE captured_at >= now() - interval '24 hours') AS max_rss_bytes_24h,
    max(captured_at) AS last_captured_at,
    count(*) FILTER (WHERE status NOT IN ('active', 'success')) AS non_active_runs
FROM gaylemon_ops.sync_runs
GROUP BY agent_id, stream;

CREATE OR REPLACE FUNCTION gaylemon_ops.apply_retention(reference_time timestamptz DEFAULT now())
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    removed_runs bigint := 0;
    removed_versions bigint := 0;
    removed_contents bigint := 0;
    affected bigint := 0;
BEGIN
    DELETE FROM gaylemon_ops.ingest_nonces WHERE expires_at < reference_time;
    DELETE FROM gaylemon_ops.oauth_states WHERE expires_at < reference_time;
    DELETE FROM gaylemon_ops.sessions WHERE expires_at < reference_time;
    DELETE FROM gaylemon_ops.control_commands WHERE requested_at < reference_time - interval '365 days';
    DELETE FROM gaylemon_ops.audit_log WHERE created_at < reference_time - interval '365 days';

    DELETE FROM gaylemon_ops.sync_runs WHERE captured_at < reference_time - interval '365 days';
    GET DIAGNOSTICS removed_runs = ROW_COUNT;

    WITH ranked AS (
        SELECT version_id, row_number() OVER (PARTITION BY path ORDER BY captured_at DESC, version_id DESC) AS position
        FROM gaylemon_public.document_versions
        WHERE stream = 'snapshot' AND daily_checkpoint = false
    )
    DELETE FROM gaylemon_public.document_versions versions
    USING ranked
    WHERE versions.version_id = ranked.version_id AND ranked.position > 7;
    GET DIAGNOSTICS affected = ROW_COUNT;
    removed_versions := removed_versions + affected;

    DELETE FROM gaylemon_public.document_versions
    WHERE stream = 'snapshot' AND daily_checkpoint = true AND captured_at < reference_time - interval '365 days';
    GET DIAGNOSTICS affected = ROW_COUNT;
    removed_versions := removed_versions + affected;

    DELETE FROM gaylemon_public.document_versions
    WHERE stream IN ('metrics', 'stats', 'public') AND captured_at < reference_time - interval '365 days';
    GET DIAGNOSTICS affected = ROW_COUNT;
    removed_versions := removed_versions + affected;

    DELETE FROM gaylemon_ops.ingest_batches batches
    WHERE accepted_at < reference_time - interval '365 days'
      AND NOT EXISTS (SELECT 1 FROM gaylemon_public.documents documents WHERE documents.batch_id = batches.batch_id)
      AND NOT EXISTS (SELECT 1 FROM gaylemon_public.document_versions versions WHERE versions.batch_id = batches.batch_id);

    DELETE FROM gaylemon_public.document_contents contents
    WHERE NOT EXISTS (SELECT 1 FROM gaylemon_public.documents documents WHERE documents.sha256 = contents.sha256)
      AND NOT EXISTS (SELECT 1 FROM gaylemon_public.document_versions versions WHERE versions.sha256 = contents.sha256);
    GET DIAGNOSTICS removed_contents = ROW_COUNT;

    RETURN jsonb_build_object(
        'removedRuns', removed_runs,
        'removedVersions', removed_versions,
        'removedContents', removed_contents,
        'appliedAt', reference_time
    );
END;
$$;
