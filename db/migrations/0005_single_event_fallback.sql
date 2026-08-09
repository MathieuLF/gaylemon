-- La projection relationnelle contient l'historique des échos. Les documents
-- JSON d'événements ne gardent que la génération active nécessaire au repli.
DELETE FROM gaylemon_public.document_versions
WHERE stream = 'events';

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
SET generations = 1, updated_at = now()
WHERE category = 'events';
