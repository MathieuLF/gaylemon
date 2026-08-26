CREATE TABLE gaylemon_ops.seasons (
    season_id text PRIMARY KEY,
    slug text NOT NULL UNIQUE CHECK (slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'),
    title text NOT NULL CHECK (length(btrim(title)) BETWEEN 1 AND 120),
    starts_on date NOT NULL,
    ends_on date,
    state text NOT NULL CHECK (state IN ('draft','active','finalizing','archived','failed')),
    manifest jsonb NOT NULL DEFAULT '{}'::jsonb,
    final_sha256 text NOT NULL DEFAULT '',
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    archived_at timestamptz,
    CHECK (ends_on IS NULL OR ends_on >= starts_on),
    CHECK ((state = 'archived') = (archived_at IS NOT NULL))
);
CREATE UNIQUE INDEX seasons_single_active_idx ON gaylemon_ops.seasons((true)) WHERE state IN ('active','finalizing');

INSERT INTO gaylemon_ops.seasons(season_id,slug,title,starts_on,state)
VALUES ('season-2026','saison-2026','Saison 2026',DATE '2026-01-01','active');

CREATE TABLE gaylemon_ops.season_lifecycle_events (
    event_id bigserial PRIMARY KEY,
    season_id text NOT NULL REFERENCES gaylemon_ops.seasons(season_id),
    event_type text NOT NULL CHECK (event_type IN ('created','activated','finalizing','archived','failed','reopened','recovered')),
    actor text NOT NULL,
    details jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX season_lifecycle_events_history_idx ON gaylemon_ops.season_lifecycle_events(season_id,created_at,event_id);
CREATE OR REPLACE FUNCTION gaylemon_ops.reject_lifecycle_event_mutation()
RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'season_lifecycle_events est append-only'; END; $$;
CREATE TRIGGER season_lifecycle_events_append_only
BEFORE UPDATE OR DELETE ON gaylemon_ops.season_lifecycle_events
FOR EACH ROW EXECUTE FUNCTION gaylemon_ops.reject_lifecycle_event_mutation();
INSERT INTO gaylemon_ops.season_lifecycle_events(season_id,event_type,actor,details)
VALUES ('season-2026','activated','migration',jsonb_build_object('backfill',true));

ALTER TABLE gaylemon_ops.agent_stream_state ADD COLUMN season_id text REFERENCES gaylemon_ops.seasons(season_id);
UPDATE gaylemon_ops.agent_stream_state SET season_id='season-2026';
ALTER TABLE gaylemon_ops.agent_stream_state ALTER COLUMN season_id SET NOT NULL;
ALTER TABLE gaylemon_ops.agent_stream_state DROP CONSTRAINT agent_stream_state_pkey;
ALTER TABLE gaylemon_ops.agent_stream_state ADD PRIMARY KEY(agent_id,season_id,stream);

ALTER TABLE gaylemon_ops.ingest_batches ADD COLUMN season_id text REFERENCES gaylemon_ops.seasons(season_id);
UPDATE gaylemon_ops.ingest_batches SET season_id='season-2026';
ALTER TABLE gaylemon_ops.ingest_batches ALTER COLUMN season_id SET NOT NULL;
ALTER TABLE gaylemon_ops.ingest_batches DROP CONSTRAINT ingest_batches_agent_id_stream_sequence_key;
ALTER TABLE gaylemon_ops.ingest_batches ADD UNIQUE(agent_id,season_id,stream,sequence);
CREATE INDEX ingest_batches_season_idx ON gaylemon_ops.ingest_batches(season_id,accepted_at,batch_id);

ALTER TABLE gaylemon_ops.sync_runs ADD COLUMN season_id text REFERENCES gaylemon_ops.seasons(season_id);
UPDATE gaylemon_ops.sync_runs SET season_id='season-2026';
ALTER TABLE gaylemon_ops.sync_runs ALTER COLUMN season_id SET NOT NULL;
CREATE INDEX sync_runs_season_time_idx ON gaylemon_ops.sync_runs(season_id,captured_at DESC);

ALTER TABLE gaylemon_public.documents ADD COLUMN season_id text REFERENCES gaylemon_ops.seasons(season_id);
UPDATE gaylemon_public.documents SET season_id='season-2026';
ALTER TABLE gaylemon_public.documents ALTER COLUMN season_id SET NOT NULL;
ALTER TABLE gaylemon_public.documents DROP CONSTRAINT documents_pkey;
ALTER TABLE gaylemon_public.documents ADD PRIMARY KEY(season_id,path);
CREATE INDEX public_documents_active_path_idx ON gaylemon_public.documents(path,season_id);

ALTER TABLE gaylemon_public.document_versions ADD COLUMN season_id text REFERENCES gaylemon_ops.seasons(season_id);
UPDATE gaylemon_public.document_versions SET season_id='season-2026';
ALTER TABLE gaylemon_public.document_versions ALTER COLUMN season_id SET NOT NULL;
DROP INDEX gaylemon_public.document_versions_batch_path_idx;
CREATE UNIQUE INDEX document_versions_batch_path_idx ON gaylemon_public.document_versions(batch_id,season_id,path) WHERE batch_id IS NOT NULL;
CREATE INDEX document_versions_season_path_time_idx ON gaylemon_public.document_versions(season_id,path,captured_at DESC);

ALTER TABLE gaylemon_public.events ADD COLUMN season_id text REFERENCES gaylemon_ops.seasons(season_id);
UPDATE gaylemon_public.events SET season_id='season-2026';
ALTER TABLE gaylemon_public.events ALTER COLUMN season_id SET NOT NULL;
ALTER TABLE gaylemon_public.events DROP CONSTRAINT events_pkey;
ALTER TABLE gaylemon_public.events ADD PRIMARY KEY(season_id,event_key);
DROP INDEX gaylemon_public.public_events_time_idx;
DROP INDEX gaylemon_public.public_events_type_idx;
DROP INDEX gaylemon_public.public_events_player_idx;
DROP INDEX gaylemon_public.public_events_search_idx;
CREATE INDEX public_events_time_idx ON gaylemon_public.events(season_id,occurred_at DESC,event_id DESC,event_key DESC);
CREATE INDEX public_events_type_idx ON gaylemon_public.events(season_id,event_type,occurred_at DESC);
CREATE INDEX public_events_player_idx ON gaylemon_public.events(season_id,player,occurred_at DESC) WHERE player IS NOT NULL;
CREATE INDEX public_events_search_idx ON gaylemon_public.events USING gin(search_text gin_trgm_ops);

ALTER TABLE gaylemon_public.event_state ADD COLUMN season_id text REFERENCES gaylemon_ops.seasons(season_id);
UPDATE gaylemon_public.event_state SET season_id='season-2026';
ALTER TABLE gaylemon_public.event_state ALTER COLUMN season_id SET NOT NULL;
ALTER TABLE gaylemon_public.event_state DROP CONSTRAINT event_state_pkey;
ALTER TABLE gaylemon_public.event_state ADD PRIMARY KEY(season_id);

ALTER TABLE gaylemon_ops.control_commands ADD COLUMN result_details jsonb NOT NULL DEFAULT '{}'::jsonb;

CREATE OR REPLACE FUNCTION gaylemon_public.replace_events_from_document(
    source jsonb,
    source_batch_id text,
    source_season_id text
)
RETURNS bigint
LANGUAGE plpgsql
AS $$
DECLARE
    incoming_revision text := COALESCE(source->>'revision', '');
    source_updated_at timestamptz;
    current_revision text;
    projected bigint := 0;
    incoming_count bigint := 0;
    source_facets jsonb;
BEGIN
    IF incoming_revision = '' OR jsonb_typeof(source->'events') <> 'array' THEN
        RAISE EXCEPTION 'document public-events invalide';
    END IF;
    SELECT revision INTO current_revision FROM gaylemon_public.event_state WHERE season_id=source_season_id;
    IF current_revision = incoming_revision THEN RETURN 0; END IF;
    BEGIN source_updated_at := (source->>'updatedAt')::timestamptz;
    EXCEPTION WHEN others THEN source_updated_at := now(); END;

    CREATE TEMP TABLE gaylemon_incoming_events ON COMMIT DROP AS
    WITH incoming AS (SELECT value AS event FROM jsonb_array_elements(source->'events'))
    SELECT
        COALESCE(NULLIF(event->>'key',''),'event-' || CASE WHEN event->>'id' ~ '^[0-9]+$' THEN event->>'id' ELSE '0' END) AS event_key,
        CASE WHEN event->>'id' ~ '^[0-9]+$' THEN (event->>'id')::bigint ELSE 0 END AS event_id,
        NULLIF(event->>'occurredAt','')::timestamptz AS occurred_at,
        COALESCE(NULLIF(event->>'type',''),'server') AS event_type,
        NULLIF(event->>'player','') AS player,
        ARRAY(SELECT DISTINCT value FROM (
            SELECT NULLIF(event->>'type','') AS value
            UNION ALL SELECT jsonb_array_elements_text(CASE WHEN jsonb_typeof(event#>'{details,types}')='array' THEN event#>'{details,types}' ELSE '[]'::jsonb END)
            UNION ALL SELECT category->>'type' FROM jsonb_array_elements(CASE WHEN jsonb_typeof(event#>'{details,categories}')='array' THEN event#>'{details,categories}' ELSE '[]'::jsonb END) category
        ) facets WHERE value IS NOT NULL AND value <> '') AS facet_types,
        lower(concat_ws(' ',event->>'player',event->>'guild',event->>'base',event->>'title',event->>'message',event->>'type',event#>>'{display,headline}',event#>>'{display,body}')) AS search_text,
        event AS payload
    FROM incoming WHERE NULLIF(event->>'occurredAt','') IS NOT NULL;
    CREATE UNIQUE INDEX ON gaylemon_incoming_events(event_key);
    SELECT count(*) INTO incoming_count FROM gaylemon_incoming_events;

    INSERT INTO gaylemon_public.events(season_id,event_key,event_id,occurred_at,event_type,player,facet_types,search_text,payload,source_revision,updated_at)
    SELECT source_season_id,event_key,event_id,occurred_at,event_type,player,facet_types,search_text,payload,incoming_revision,now()
    FROM gaylemon_incoming_events
    ON CONFLICT(season_id,event_key) DO UPDATE SET event_id=excluded.event_id,occurred_at=excluded.occurred_at,event_type=excluded.event_type,
        player=excluded.player,facet_types=excluded.facet_types,search_text=excluded.search_text,payload=excluded.payload,source_revision=excluded.source_revision,updated_at=now();
    GET DIAGNOSTICS projected = ROW_COUNT;
    DELETE FROM gaylemon_public.events stored WHERE stored.season_id=source_season_id
      AND NOT EXISTS (SELECT 1 FROM gaylemon_incoming_events incoming WHERE incoming.event_key=stored.event_key);

    SELECT jsonb_build_object(
        'types',COALESCE((SELECT jsonb_agg(jsonb_build_object('value',value,'count',count) ORDER BY value) FROM
            (SELECT facet.value,count(*) count FROM gaylemon_public.events CROSS JOIN LATERAL unnest(facet_types) facet(value) WHERE season_id=source_season_id GROUP BY facet.value) t),'[]'::jsonb),
        'players',COALESCE((SELECT jsonb_agg(jsonb_build_object('value',player,'count',count) ORDER BY player) FROM
            (SELECT player,count(*) count FROM gaylemon_public.events WHERE season_id=source_season_id AND player IS NOT NULL AND player<>'' GROUP BY player) p),'[]'::jsonb)
    ) INTO source_facets;
    INSERT INTO gaylemon_public.event_state(season_id,singleton,revision,source_updated_at,total_echoes,summary,facets,batch_id,updated_at)
    VALUES(source_season_id,true,incoming_revision,source_updated_at,incoming_count,COALESCE(source->'summary','{}'::jsonb),source_facets,source_batch_id,now())
    ON CONFLICT(season_id) DO UPDATE SET revision=excluded.revision,source_updated_at=excluded.source_updated_at,total_echoes=excluded.total_echoes,
      summary=excluded.summary,facets=excluded.facets,batch_id=excluded.batch_id,updated_at=now();
    RETURN projected;
END;
$$;

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

    DELETE FROM gaylemon_ops.sync_runs runs
    USING gaylemon_ops.seasons seasons
    WHERE runs.season_id=seasons.season_id AND seasons.state<>'archived'
      AND runs.captured_at < reference_time - interval '365 days';
    GET DIAGNOSTICS removed_runs = ROW_COUNT;

    WITH ranked AS (
        SELECT versions.version_id,
               row_number() OVER (PARTITION BY versions.season_id,versions.path ORDER BY versions.captured_at DESC,versions.version_id DESC) AS position
        FROM gaylemon_public.document_versions versions
        JOIN gaylemon_ops.seasons seasons USING(season_id)
        WHERE seasons.state<>'archived' AND versions.stream='snapshot' AND versions.daily_checkpoint=false
    )
    DELETE FROM gaylemon_public.document_versions versions USING ranked
    WHERE versions.version_id=ranked.version_id AND ranked.position>7;
    GET DIAGNOSTICS affected = ROW_COUNT;
    removed_versions := removed_versions + affected;

    DELETE FROM gaylemon_public.document_versions versions
    USING gaylemon_ops.seasons seasons
    WHERE versions.season_id=seasons.season_id AND seasons.state<>'archived'
      AND versions.stream='snapshot' AND versions.daily_checkpoint=true
      AND versions.captured_at < reference_time - interval '365 days';
    GET DIAGNOSTICS affected = ROW_COUNT;
    removed_versions := removed_versions + affected;

    DELETE FROM gaylemon_public.document_versions versions
    USING gaylemon_ops.seasons seasons
    WHERE versions.season_id=seasons.season_id AND seasons.state<>'archived'
      AND versions.stream IN ('metrics','stats','public')
      AND versions.captured_at < reference_time - interval '365 days';
    GET DIAGNOSTICS affected = ROW_COUNT;
    removed_versions := removed_versions + affected;

    DELETE FROM gaylemon_ops.ingest_batches batches
    USING gaylemon_ops.seasons seasons
    WHERE batches.season_id=seasons.season_id AND seasons.state<>'archived'
      AND batches.accepted_at < reference_time - interval '365 days'
      AND NOT EXISTS (SELECT 1 FROM gaylemon_public.documents documents WHERE documents.batch_id=batches.batch_id)
      AND NOT EXISTS (SELECT 1 FROM gaylemon_public.document_versions versions WHERE versions.batch_id=batches.batch_id);

    DELETE FROM gaylemon_public.document_contents contents
    WHERE NOT EXISTS (SELECT 1 FROM gaylemon_public.documents documents WHERE documents.sha256=contents.sha256)
      AND NOT EXISTS (SELECT 1 FROM gaylemon_public.document_versions versions WHERE versions.sha256=contents.sha256);
    GET DIAGNOSTICS removed_contents = ROW_COUNT;

    RETURN jsonb_build_object('removedRuns',removed_runs,'removedVersions',removed_versions,'removedContents',removed_contents,'appliedAt',reference_time);
END;
$$;
