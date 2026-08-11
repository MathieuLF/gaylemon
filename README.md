# Gaylémon

[![Licence MIT](https://img.shields.io/badge/licence-MIT-2f855a.svg)](LICENSE)

Gaylémon regroupe les outils autour d'un serveur Palworld privé: console d'exploitation, scripts Ubuntu, collecteurs, projections publiques, terminal des échos et microsite.

Le principe est simple: Palworld reste stable, les sauvegardes sont lues en lecture seule, et le site ne reçoit que des données filtrées. Les secrets, les sauvegardes réelles et les données privées ne vont pas dans Git.

## Ce que contient le dépôt

- `cmd/` et `internal/`: service web Go, agent sortant, API signée et accès PostgreSQL 16.
- `db/`: migrations PostgreSQL, historique et rétention.
- `server/`: scripts Ubuntu, unités `systemd`, collecteurs et tests.
- `scripts/`: console et outils Windows.
- `portal/`: microsite statique, routes `/`, `/terminal`, `/resume`, `/classements`, `/carte`, `/github` et exemples JSON.
- `docker/`: Nginx local pour le microsite et image du tunnel API Palworld.
- `docs/`: guides courts, contrats de données et notes d'exploitation.
- `dependencies/`: verrous des dépendances externes, sans cloner leur code.

cloudflared, SteamCMD et Palworld ne sont pas possédés par ce dépôt. Gaylémon peut s'y brancher, mais ne doit pas en prendre le contrôle.

## Démarrer en local

```powershell
.\scripts\initialiser-projet.ps1
.\scripts\valider-depot.ps1
```

L'initialisation prépare les dossiers ignorés et copie des exemples JSON si aucune donnée réelle n'existe. Elle ne contacte pas Ubuntu, Docker ou Cloudflare.

Pour ouvrir la console:

```powershell
.\Gaylemon Ops Console.ps1
```

Pour servir le microsite:

```powershell
docker compose up -d microsite
```

Par défaut, Nginx écoute seulement sur `127.0.0.1`.

Routes utiles du microsite:

- `http://127.0.0.1:8787/`: tableau de bord public;
- `http://127.0.0.1:8787/terminal`: terminal plein écran des échos;
- `http://127.0.0.1:8787/resume`: résumé quotidien des joueurs;
- `http://127.0.0.1:8787/classements`: palmarès dédié;
- `http://127.0.0.1:8787/carte`: carte dédiée de Palpagos;
- `http://127.0.0.1:8787/github`: page technique publique du dépôt.

## Version du microsite

La version canonique du microsite se trouve dans `VERSION` au format `AAAA.MM.JJ.REVISION`. Le pied de page affiche cette version; en production, il ajoute le commit Git court et le canal de livraison. La route publique `/version` fournit les mêmes métadonnées en JSON et reste servie sans cache.

Pour comparer le dépôt local, la branche `main` sur GitHub et la VPS:

```powershell
.\scripts\comparer-version.ps1
```

Ajouter `-Strict` pour obtenir un code de sortie non nul dès qu’un écart est détecté, ou `-Json` pour une sortie exploitable par un autre outil.

Pour exposer localement l'API REST Palworld aux annonces Discord et aux sondes d'exploitation via Docker Desktop:

```powershell
.\scripts\palworld-api-tunnel.ps1 start
.\scripts\palworld-api-tunnel.ps1 status
```

Le port reste lié à `127.0.0.1`. Le bot lit les JSON publics par défaut et utilise l'exemple [bot.env.example](config/exemples/bot.env.example), hors Git une fois rempli; les variables REST restent vides sauf si une commande d'annonce en jeu est activée.
Si Docker Desktop ne peut pas joindre le LAN à cause d'un subnet Docker concurrent, le même script peut démarrer un tunnel SSH Windows local:

```powershell
.\scripts\palworld-api-tunnel.ps1 start -Mode windows-ssh
```

## Commandes utiles

```powershell
# Validation locale
.\scripts\valider-depot.ps1

# Comparaison local, GitHub et VPS
.\scripts\comparer-version.ps1

# Diagnostic en lecture seule
.\scripts\diagnostiquer-integrations.ps1

# Audit des fichiers Ubuntu actifs
.\scripts\auditer-source-ubuntu.ps1

# Aperçu d'une livraison Ubuntu
.\scripts\deployer-ubuntu.ps1

# Mise en scène sous /tmp sur Ubuntu
.\scripts\deployer-ubuntu.ps1 -Stage

# Installation explicite, avec sauvegarde
.\scripts\deployer-ubuntu.ps1 -Install
```

`-Install` ne redémarre aucun service par défaut. Le redémarrage de `palworld.service` demande une option et une confirmation explicites.

## Données privées

Ne jamais versionner:

- `.env`, clés SSH, jetons et mots de passe;
- sauvegardes Palworld, bases SQLite, journaux et PID;
- données réelles sous `portal/data/`;
- ressources extraites du jeu sous `portal/assets/game/`;
- archives et rapports sous `runtime/`;
- clones complets sous `vendor/`.

Les exemples `*.example.json` sont fictifs et servent au développement local.

Les ressources Palworld ne sont pas versionnées dans ce dépôt. L’image de production récupère uniquement les icônes et cartes nécessaires depuis la révision PalworldSaveTools verrouillée dans `dependencies/palworld-save-tools.lock.json`, puis les sert sous `/assets/game/`.

Les exports publics réels restent non versionnés. Le site lit notamment:

- `public-metrics.json` pour l'état live, les joueurs connectés et `onlineSinceAt`;
- `public-stats.json` pour les sessions et agrégats joueurs;
- `public-save-index.json`, `public-save-snapshot.json`, `public-save-bases.json`, `public-save-diagnostics.json` et `players/{slug}.json` pour les fiches, Pals, bases et exports JSON d'analyse; ces fichiers partagent une génération et l'index devient actif en dernier;
- l'API paginée `/api/public/events/v1`, alimentée par `gaylemon_public.events`, pour le Terminal;
- `public-events-recent.json` comme petit repli de continuité lorsque PostgreSQL est momentanément indisponible;
- `public-uptime.json`, `public-uptime-history.json` et `public-availability.json` pour la disponibilité calculée depuis l'API REST Palworld.

Le service Go sert les pages, l'API PostgreSQL et les petits documents de repli. Les JSON mutables sont servis en `no-store`.

Le flux des échos est traité comme une donnée chaude: projection canonique près de SQLite, transport compressé, ingestion relationnelle différentielle dans PostgreSQL, pagination et recherche indexées. L'export complet sert uniquement de véhicule transactionnel et n'est pas conservé dans la base; seul le petit repli récent reste servi.

## Documentation

- [Sommaire](docs/README.md)
- [Sécurité](SECURITY.md)
- [Support](SUPPORT.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Échos publics v6](docs/EVENEMENTS-PUBLICS-V6.md)
- [Sécurité d'exploitation](docs/SECURITE-EXPLOITATION.md)
- [Configuration locale](docs/CONFIGURATION-LOCALE.md)
- [Développement](docs/DEVELOPPEMENT.md)
- [Déploiement](docs/DEPLOIEMENT.md)
- [Publication sur la VPS Nethercore](docs/VPS-NETHERCORE.md)
- [Opérations](docs/OPERATIONS.md)
- [Bot Discord](docs/BOT-DISCORD.md)
- [Publication GitHub](docs/PUBLIC-REPOSITORY.md)
- [Démarche GitHub du microsite](https://gaylemon.nethercore.dev/github)

## Licence

Le code Gaylémon est sous licence MIT. Palworld, ses ressources et ses marques appartiennent à leurs ayants droit. PalworldSaveTools reste une dépendance séparée avec ses propres licences.

Voir aussi [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
