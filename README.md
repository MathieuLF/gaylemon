# Gaylémon

[![Licence MIT](https://img.shields.io/badge/licence-MIT-2f855a.svg)](LICENSE)

Gaylémon est un microsite saisonnier pour raconter une aventure Palworld à partir de projections publiques filtrées. Il présente l’état courant, les joueurs, les échos, les classements, la carte et les archives de saisons sans publier les sauvegardes brutes ni les identifiants techniques.

Ce dépôt public documente le microsite, son contrat de développement local et les fichiers nécessaires pour repartir du projet. Il ne décrit pas l’état d’une instance hébergée, son infrastructure privée, ses secrets ou ses données réelles.

## Composants

- `cmd/gaylemon-web` et `internal/web` : service HTTP Go et portail public;
- `cmd/gaylemon` et `internal/agent` : agent sortant signé avec file durable;
- `internal/collector` et `internal/projection` : lecture de sources déjà filtrées et création des documents publics;
- `db/migrations` : PostgreSQL 16, rétention et cycle multi-saisons;
- `portal` : pages, styles, scripts, PWA et exemples JSON fictifs;
- `scripts` : validation locale, inventaire, sécurité et release;
- `docs` : contrats publics, développement et cycle des saisons.

## Développement local

Pour explorer le portail avec les données fictives : Node.js 24, puis `npm ci` et `npm run dev`. Ouvrir `http://127.0.0.1:4179`. Ce serveur de développement utilise les exemples suivis dans Git, jamais les exports locaux réels.

Pour démarrer Go avec PostgreSQL 16 : Go 1.27, PowerShell 7 et Docker, puis :

```powershell
.\scripts\start-local.ps1
```

Le script prépare une base temporaire, des clés locales et le service sur `http://127.0.0.1:8080`. Ctrl+C arrête cette instance et retire sa base. L’option `-Check` vérifie le démarrage puis nettoie les processus. Le service Go ne charge pas automatiquement `.env`; copier `.env.example` ne suffit donc pas. Voir [Développement](docs/DEVELOPPEMENT.md) pour les deux parcours et leurs limites.

## Validation commune

```powershell
.\scripts\upgrade-preflight.ps1 -Mode Inventory
.\scripts\verify-local.ps1 -Mode Quick
.\scripts\verify-local.ps1 -Mode Full
```

Gaylémon suit la révision 2.3.0 de `suite-foundation-v2` avec le profil `seasonal-go-microsite`. `VERSION` est la source SemVer. Quick couvre les contrats Go, les migrations et le portail; Full ajoute PostgreSQL isolé, navigateur/Axe, race, vulnérabilités, SBOM et image de release.

## Données et confidentialité

Gaylémon est pensé pour publier une version racontable d’une saison Palworld, pas une sauvegarde de serveur. Le site affiche des données déjà préparées pour être vues : progression, joueurs, échos publics, classements, carte et archives.

Les exemples inclus dans `portal/data` sont fictifs et servent au développement local. Pour utiliser le projet avec votre propre monde, générez vos propres données publiques et adaptez les textes de confidentialité à votre communauté.

Les fichiers privés d’une installation, comme les secrets, sauvegardes, journaux et exports bruts, ne font pas partie du projet publié.

## Documentation

- [Sommaire](docs/README.md)
- [Architecture publique](docs/ARCHITECTURE.md)
- [Données publiques](docs/DONNEES-PUBLIQUES.md)
- [Saisons et archives](docs/SAISONS.md)
- [Développement](docs/DEVELOPPEMENT.md)
- [Échos publics v6](docs/EVENEMENTS-PUBLICS-V6.md)
- [Confidentialité et sécurité](SECURITY.md)
- [Avis tiers](THIRD_PARTY_NOTICES.md)

## Licence

Le code Gaylémon est sous licence MIT. Palworld et ses ressources appartiennent à leurs ayants droit respectifs.
