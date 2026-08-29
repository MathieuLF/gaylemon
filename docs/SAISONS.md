# Saisons et archives

Gaylémon sépare chaque aventure en saison. Une saison active accepte des projections signées; une archive conserve ses documents publics en lecture seule et cesse le sondage périodique.

## États

- `draft` : préparation sans ingestion;
- `active` : saison courante;
- `finalizing` : clôture en cours;
- `archived` : projections figées, ingestion refusée;
- `failed` : transition incomplète à récupérer.

Le journal de cycle de vie est append-only. Les commandes d’activation, d’archivage et de récupération sont typées, signées et acquittées avec des preuves structurées. Le dépôt public décrit le contrat, pas la procédure d’exploitation ni les chemins d’une instance.

## API publique

- `GET /api/public/seasons/v1`;
- `GET /api/public/site-state/v1`;
- `GET /saisons/{slug}/api/public/events/v1`;
- `GET /saisons/{slug}/data/{path}`.

Une archive affiche clairement que la saison est terminée, conserve recherche et pagination et ne prétend plus être en direct.

## Validation

Quick couvre les transitions pures et la signature de l’agent. Full rejoue migrations, concurrence, compensation, archivage, refus d’ingestion et réouverture sur PostgreSQL 16 isolé.
