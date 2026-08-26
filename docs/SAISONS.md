# Saisons et archives

Gaylémon sépare chaque aventure Palworld en saison. Une saison active accepte les projections signées de l’agent. Une saison archivée conserve ses documents, événements, versions et séquences sous `/saisons/{slug}/...`, sans sondage périodique ni libellé « en direct ».

## États

- `draft` : saison préparée, sans ingestion;
- `active` : saison courante et synchronisée;
- `finalizing` : collecte finale en cours; l’ingestion signée reste ouverte jusqu’à l’acquittement de la commande;
- `archived` : projections figées, ingestion refusée en `423 season-archived`;
- `failed` : activation initiale incomplète qui exige une intervention; une clôture échouée revient plutôt à `active`.

Le journal `season_lifecycle_events` est append-only. Une activation demeure en attente dans la commande agent : la saison ne passe à `active` qu’après l’acquittement structuré confirmant la remise en marche des minuteries. Une réouverture est permise seulement pour récupérer la dernière saison, avant la création ou l’activation d’une suivante, et suit le même acquittement.

## Clôture opérateur

`POST /ops/api/seasons/{id}/archive` exige une session de moins de cinq minutes, la confirmation `ARCHIVER` et l’agent visé. L’opération :

1. prend le verrou PostgreSQL du cycle de saison et passe la saison à `finalizing`;
2. transmet une commande `season.archive` strictement typée à l’agent;
3. prend le verrou Ubuntu `/run/lock/gaylemon-season.lock`;
4. désactive les sept minuteries de collecte/publication et la mise à jour Palworld;
5. attend les unités ponctuelles, produit la sauvegarde finale, la copie dans l’espace saisonnier root-only et la rend immuable (`chattr +i`), puis écrit un reçu lui aussi immuable avec leurs SHA-256;
6. exécute les dernières projections pendant que la boucle agent continue de vider la file locale, jusqu’à zéro;
7. vérifie que le PID et `NRestarts` de `palworld.service` sont inchangés;
8. acquitte la commande avec des preuves JSON structurées;
9. construit transactionnellement un manifeste trié et enregistre son SHA-256 avant de passer à `archived`.

La commande ne contient aucun chemin permettant de redémarrer `palworld.service`. Si une étape échoue, le helper restaure explicitement l’état antérieur des minuteries. Si l’acquittement expire malgré tout, le serveur maintient la saison en `finalizing`, journalise l’échec et émet une commande compensatoire `season.activate` qui rétablit les minuteries sans réinitialiser la déduplication locale. Son acquittement prouvé ramène ensuite la saison à `active`. Cette compensation reste disponible six heures; au-delà, la saison passe à `failed` et l’opérateur peut relancer la récupération depuis l’interface. L’archive n’est jamais déclarée réussie dans ces cas. Le serveur refuse aussi de la sceller si le reçu, les chemins exacts liés aux empreintes, la file vide et les invariants Palworld ne sont pas tous présents et cohérents.

## API publique

- `GET /api/public/seasons/v1` : saisons actives, en clôture ou archivées;
- `GET /api/public/site-state/v1` : mode courant, lecture seule et politique de sondage;
- `GET /saisons/{slug}/api/public/events/v1` : événements de l’archive;
- `GET /saisons/{slug}/data/{path}` : document public de l’archive.

La racine `/` pointe vers la saison active. En son absence, elle sert la dernière archive. Les routes privées, les commandes et les sauvegardes ne sont jamais placées dans le cache hors ligne.
