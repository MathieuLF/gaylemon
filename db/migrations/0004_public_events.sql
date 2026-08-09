CREATE TABLE IF NOT EXISTS gaylemon_public.events (
    event_key text PRIMARY KEY,
    event_id bigint NOT NULL,
    occurred_at timestamptz NOT NULL,
    event_type text NOT NULL,
    player text,
    facet_types text[] NOT NULL DEFAULT '{}',
    search_text text NOT NULL DEFAULT '',
    payload jsonb NOT NULL,
    source_revision text NOT NULL,
    updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS public_events_time_idx
    ON gaylemon_public.events(occurred_at DESC, event_id DESC, event_key DESC);
CREATE INDEX IF NOT EXISTS public_events_type_idx
    ON gaylemon_public.events(event_type, occurred_at DESC);
CREATE INDEX IF NOT EXISTS public_events_player_idx
    ON gaylemon_public.events(player, occurred_at DESC)
    WHERE player IS NOT NULL;
CREATE INDEX IF NOT EXISTS public_events_facets_idx
    ON gaylemon_public.events USING gin(facet_types);

CREATE TABLE IF NOT EXISTS gaylemon_public.event_state (
    singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
    revision text NOT NULL,
    source_updated_at timestamptz NOT NULL,
    total_echoes bigint NOT NULL DEFAULT 0,
    summary jsonb NOT NULL DEFAULT '{}'::jsonb,
    facets jsonb NOT NULL DEFAULT '{"types":[],"players":[]}'::jsonb,
    batch_id text NOT NULL DEFAULT '',
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE OR REPLACE FUNCTION gaylemon_public.replace_events_from_document(
    source jsonb,
    source_batch_id text DEFAULT ''
)
RETURNS bigint
LANGUAGE plpgsql
AS $$
DECLARE
    incoming_revision text := COALESCE(source->>'revision', '');
    source_updated_at timestamptz;
    current_revision text;
    projected bigint := 0;
    source_facets jsonb;
BEGIN
    IF incoming_revision = '' OR jsonb_typeof(source->'events') <> 'array' THEN
        RAISE EXCEPTION 'document public-events invalide';
    END IF;

    SELECT revision INTO current_revision
    FROM gaylemon_public.event_state
    WHERE singleton = true;
    IF current_revision = incoming_revision THEN
        RETURN 0;
    END IF;

    BEGIN
        source_updated_at := (source->>'updatedAt')::timestamptz;
    EXCEPTION WHEN others THEN
        source_updated_at := now();
    END;

    WITH incoming AS (
        SELECT value AS event
        FROM jsonb_array_elements(source->'events')
    ), normalized AS (
        SELECT
            event,
            CASE WHEN event->>'id' ~ '^[0-9]+$' THEN (event->>'id')::bigint ELSE 0 END AS event_id,
            NULLIF(event->>'occurredAt', '')::timestamptz AS occurred_at,
            COALESCE(NULLIF(event->>'type', ''), 'server') AS event_type,
            NULLIF(event->>'player', '') AS player,
            ARRAY(
                SELECT DISTINCT value
                FROM (
                    SELECT NULLIF(event->>'type', '') AS value
                    UNION ALL
                    SELECT jsonb_array_elements_text(
                        CASE WHEN jsonb_typeof(event#>'{details,types}') = 'array'
                            THEN event#>'{details,types}' ELSE '[]'::jsonb END
                    )
                    UNION ALL
                    SELECT category->>'type'
                    FROM jsonb_array_elements(
                        CASE WHEN jsonb_typeof(event#>'{details,categories}') = 'array'
                            THEN event#>'{details,categories}' ELSE '[]'::jsonb END
                    ) AS category
                ) facets
                WHERE value IS NOT NULL AND value <> ''
            ) AS facet_types,
            lower(concat_ws(' ',
                event->>'player', event->>'guild', event->>'base',
                event->>'title', event->>'message', event->>'type',
                event#>>'{display,headline}', event#>>'{display,body}',
                (
                    SELECT string_agg(value, ' ')
                    FROM jsonb_array_elements_text(
                        CASE WHEN jsonb_typeof(event#>'{display,bullets}') = 'array'
                            THEN event#>'{display,bullets}' ELSE '[]'::jsonb END
                    ) AS value
                )
            )) AS search_text
        FROM incoming
    )
    INSERT INTO gaylemon_public.events(
        event_key, event_id, occurred_at, event_type, player,
        facet_types, search_text, payload, source_revision, updated_at
    )
    SELECT
        COALESCE(NULLIF(event->>'key', ''), 'event-' || event_id::text),
        event_id, occurred_at, event_type, player,
        facet_types, search_text, event, incoming_revision, now()
    FROM normalized
    WHERE occurred_at IS NOT NULL
    ON CONFLICT(event_key) DO UPDATE SET
        event_id = excluded.event_id,
        occurred_at = excluded.occurred_at,
        event_type = excluded.event_type,
        player = excluded.player,
        facet_types = excluded.facet_types,
        search_text = excluded.search_text,
        payload = excluded.payload,
        source_revision = excluded.source_revision,
        updated_at = now();
    GET DIAGNOSTICS projected = ROW_COUNT;

    DELETE FROM gaylemon_public.events AS stored
    WHERE stored.source_revision <> incoming_revision;

    SELECT jsonb_build_object(
        'types', COALESCE((
            SELECT jsonb_agg(jsonb_build_object('value', value, 'count', count) ORDER BY value)
            FROM (
                SELECT facet.value, count(*) AS count
                FROM gaylemon_public.events
                CROSS JOIN LATERAL unnest(facet_types) AS facet(value)
                GROUP BY facet.value
            ) types
        ), '[]'::jsonb),
        'players', COALESCE((
            SELECT jsonb_agg(jsonb_build_object('value', player, 'count', count) ORDER BY player)
            FROM (
                SELECT player, count(*) AS count
                FROM gaylemon_public.events
                WHERE player IS NOT NULL AND player <> ''
                GROUP BY player
            ) players
        ), '[]'::jsonb)
    ) INTO source_facets;

    INSERT INTO gaylemon_public.event_state(
        singleton, revision, source_updated_at, total_echoes,
        summary, facets, batch_id, updated_at
    ) VALUES(
        true, incoming_revision, source_updated_at,
        (SELECT count(*) FROM gaylemon_public.events),
        COALESCE(source->'summary', '{}'::jsonb), source_facets,
        source_batch_id, now()
    )
    ON CONFLICT(singleton) DO UPDATE SET
        revision = excluded.revision,
        source_updated_at = excluded.source_updated_at,
        total_echoes = excluded.total_echoes,
        summary = excluded.summary,
        facets = excluded.facets,
        batch_id = excluded.batch_id,
        updated_at = now();

    RETURN projected;
END;
$$;

DO $$
DECLARE
    source jsonb;
    source_batch_id text;
BEGIN
    SELECT contents.content, documents.batch_id
    INTO source, source_batch_id
    FROM gaylemon_public.documents documents
    JOIN gaylemon_public.document_contents contents ON contents.sha256 = documents.sha256
    WHERE documents.path = 'data/public-events.json';

    IF source IS NOT NULL THEN
        PERFORM gaylemon_public.replace_events_from_document(source, source_batch_id);
    END IF;
END;
$$;

-- PostgreSQL devient la source d'historique. Les gros exports JSON mutables
-- restent disponibles comme repli actif, sans conserver une version complète
-- à chaque passage du collecteur.
DELETE FROM gaylemon_public.document_versions
WHERE stream = 'events' AND cache_policy <> 'immutable';

DELETE FROM gaylemon_public.documents documents
WHERE documents.generation_id <> COALESCE((
        SELECT active.generation_id
        FROM gaylemon_public.documents active
        WHERE active.path = 'data/public-events-head-v6.json'
    ), '')
  AND (
      documents.path LIKE 'data/public-events-v6/%'
      OR documents.path LIKE 'data/public-daily/%'
  );

WITH generations AS (
    SELECT generation_id,
           dense_rank() OVER (ORDER BY max(captured_at) DESC, generation_id DESC) AS position
    FROM gaylemon_public.document_versions
    WHERE stream = 'events' AND cache_policy = 'immutable' AND generation_id <> ''
    GROUP BY generation_id
), retired AS (
    SELECT generation_id FROM generations WHERE position > 3
)
DELETE FROM gaylemon_public.document_versions versions
USING retired
WHERE versions.stream = 'events' AND versions.generation_id = retired.generation_id;

DELETE FROM gaylemon_public.document_contents contents
WHERE NOT EXISTS (
        SELECT 1 FROM gaylemon_public.documents documents
        WHERE documents.sha256 = contents.sha256
    )
  AND NOT EXISTS (
        SELECT 1 FROM gaylemon_public.document_versions versions
        WHERE versions.sha256 = contents.sha256
    );

UPDATE gaylemon_ops.retention_policies
SET generations = 3, updated_at = now()
WHERE category = 'events';
