CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE INDEX IF NOT EXISTS public_events_search_idx
    ON gaylemon_public.events USING gin(search_text gin_trgm_ops);

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
    incoming_count bigint := 0;
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

    CREATE TEMP TABLE gaylemon_incoming_events ON COMMIT DROP AS
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
    SELECT
        COALESCE(NULLIF(event->>'key', ''), 'event-' || event_id::text) AS event_key,
        event_id, occurred_at, event_type, player,
        facet_types, search_text, event AS payload
    FROM normalized
    WHERE occurred_at IS NOT NULL;

    CREATE UNIQUE INDEX ON gaylemon_incoming_events(event_key);
    ANALYZE gaylemon_incoming_events;

    SELECT count(*) INTO incoming_count FROM gaylemon_incoming_events;

    INSERT INTO gaylemon_public.events(
        event_key, event_id, occurred_at, event_type, player,
        facet_types, search_text, payload, source_revision, updated_at
    )
    SELECT
        event_key, event_id, occurred_at, event_type, player,
        facet_types, search_text, payload, incoming_revision, now()
    FROM gaylemon_incoming_events
    ON CONFLICT(event_key) DO UPDATE SET
        event_id = excluded.event_id,
        occurred_at = excluded.occurred_at,
        event_type = excluded.event_type,
        player = excluded.player,
        facet_types = excluded.facet_types,
        search_text = excluded.search_text,
        payload = excluded.payload,
        source_revision = excluded.source_revision,
        updated_at = now()
    WHERE (
        gaylemon_public.events.event_id,
        gaylemon_public.events.occurred_at,
        gaylemon_public.events.event_type,
        gaylemon_public.events.player,
        gaylemon_public.events.facet_types,
        gaylemon_public.events.search_text,
        gaylemon_public.events.payload
    ) IS DISTINCT FROM (
        excluded.event_id,
        excluded.occurred_at,
        excluded.event_type,
        excluded.player,
        excluded.facet_types,
        excluded.search_text,
        excluded.payload
    );
    GET DIAGNOSTICS projected = ROW_COUNT;

    DELETE FROM gaylemon_public.events AS stored
    WHERE NOT EXISTS (
        SELECT 1 FROM gaylemon_incoming_events incoming
        WHERE incoming.event_key = stored.event_key
    );

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
        true, incoming_revision, source_updated_at, incoming_count,
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

DELETE FROM gaylemon_public.document_versions
WHERE stream = 'events';

DELETE FROM gaylemon_public.documents
WHERE path IN (
        'data/public-events.json',
        'data/public-events-manifest-v6.json',
        'data/public-events-head-v6.json',
        'public-events-channel.json'
    )
   OR path LIKE 'data/public-events-v6/%'
   OR path LIKE 'data/public-daily/%';

DELETE FROM gaylemon_public.document_contents contents
WHERE NOT EXISTS (
        SELECT 1 FROM gaylemon_public.documents documents
        WHERE documents.sha256 = contents.sha256
    )
  AND NOT EXISTS (
        SELECT 1 FROM gaylemon_public.document_versions versions
        WHERE versions.sha256 = contents.sha256
    );
