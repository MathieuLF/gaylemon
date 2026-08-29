# Gaylémon

[![Licence MIT](https://img.shields.io/badge/licence-MIT-2f855a.svg)](LICENSE)

Gaylémon est un microsite saisonnier pour raconter une aventure Palworld à partir de projections publiques filtrées. Il présente l’état courant, les joueurs, les échos, les classements, la carte et les archives de saisons sans publier les sauvegardes brutes ni les identifiants techniques.

Le dépôt public contient le produit réutilisable. Les domaines, hôtes, chemins d’installation, secrets, sauvegardes, reçus et procédures d’exploitation d’une instance réelle sont volontairement conservés hors de ce dépôt.

## Composants

- `cmd/gaylemon-web` et `internal/web` : service HTTP Go et portail public;
- `cmd/gaylemon` et `internal/agent` : agent sortant signé avec file durable;
- `internal/collector` et `internal/projection` : lecture de sources déjà filtrées et création des documents publics;
- `db/migrations` : PostgreSQL 16, rétention et cycle multi-saisons;
- `portal` : pages, styles, scripts, PWA et exemples JSON fictifs;
- `scripts` : validation locale, inventaire, sécurité et release;
- `docs` : contrats publics, développement et cycle des saisons.

## Développement local

Prérequis : Go 1.27, Node.js et PostgreSQL 16.

```powershell
Copy-Item .env.example .env
go test ./...
npm ci
npm test
go run ./cmd/gaylemon-web
```

Les valeurs de `.env.example` sont fictives. Le service doit recevoir ses secrets et ses chemins réels par un mécanisme privé propre à l’environnement d’exécution.

## Validation commune

```powershell
.\scripts\upgrade-preflight.ps1 -Mode Inventory
.\scripts\verify-local.ps1 -Mode Quick
.\scripts\verify-local.ps1 -Mode Full
```

Gaylémon suit la révision 2.3.0 de `suite-foundation-v2` avec le profil `seasonal-go-microsite`. `VERSION` est la source SemVer. Quick couvre les contrats Go, les migrations, le portail et la frontière publique; Full ajoute PostgreSQL isolé, navigateur/Axe, race, vulnérabilités, deux SBOM, image OCI et preuves de signature.

## Cache et continuité

Le service calcule une empreinte SHA-256 de `assets/app.js` et `assets/styles.css`, publie `/assets-manifest.json`, réécrit les pages vers leurs noms liés au contenu et réserve `immutable` à ces noms. HTML, manifeste PWA, service worker, version et manifeste d’actifs sont revalidés. Le service worker respecte l’identité exacte des requêtes et conserve la release d’actifs précédente pour permettre un retour arrière.

## Frontière publique

Ne jamais versionner :

- domaine, identifiant d’hôte ou chemin d’une instance réelle;
- runbook, adaptateur de déploiement ou configuration d’infrastructure;
- clé, jeton, certificat, mot de passe ou fichier d’environnement réel;
- sauvegarde, base locale, journal, PID ou reçu d’exploitation;
- export contenant des identifiants privés de joueur.

Le script `scripts/valider-depot.ps1` bloque ces surfaces dans la branche active. Les détails d’installation et d’exploitation appartiennent à une autorité privée distincte.

## Documentation

- [Sommaire](docs/README.md)
- [Architecture publique](docs/ARCHITECTURE.md)
- [Saisons et archives](docs/SAISONS.md)
- [Développement](docs/DEVELOPPEMENT.md)
- [Échos publics v6](docs/EVENEMENTS-PUBLICS-V6.md)
- [Confidentialité et sécurité](SECURITY.md)
- [Avis tiers](THIRD_PARTY_NOTICES.md)

## Licence

Le code Gaylémon est sous licence MIT. Palworld et ses ressources appartiennent à leurs ayants droit respectifs.
