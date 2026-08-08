ALTER TABLE gaylemon_public.document_contents
    ADD COLUMN IF NOT EXISTS content_bytes bytea;

UPDATE gaylemon_public.document_contents
SET content_bytes = convert_to(content::text, 'UTF8')
WHERE content_bytes IS NULL;

ALTER TABLE gaylemon_public.document_contents
    ALTER COLUMN content_bytes SET NOT NULL;
