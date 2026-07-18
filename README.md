# Gaylémon

[![Licence MIT](https://img.shields.io/badge/licence-MIT-2f855a.svg)](LICENSE)

Gaylémon regroupe les outils autour d'un serveur Palworld privé: console d'exploitation, scripts Ubuntu, collecteurs, projections publiques, terminal des échos et microsite.

Le principe est simple: Palworld reste stable, les sauvegardes sont lues en lecture seule, et le site ne reçoit que des données filtrées. Les secrets, les sauvegardes réelles et les données privées ne vont pas dans Git.

## Ce que contient le dépôt

- `server/`: scripts Ubuntu, unités `systemd`, collecteurs et tests.
- `scripts/`: console et outils Windows.
- `portal/`: microsite statique, routes `/`, `/terminal`, `/resume`, `/classements`, `/carte`, `/github` et exemples JSON.
- `docker/`: Nginx local pour le microsite et image du tunnel API Palworld.
- `docs/`: guides courts, contrats de données et notes d'exploitation.
- `dependencies/`: verrous des dépendances externes, sans cloner leur code.

Uptime Kuma, cloudflared, SteamCMD et Palworld ne sont pas possédés par ce dépôt. Gaylémon peut s'y brancher, mais ne doit pas en prendre le contrôle.

## Démarrer en local

```powershell
.\scripts\initialiser-projet.ps1
.\scripts\valider-depot.ps1
```

L'initialisation prépare les dossiers ignorés et copie des exemples JSON si aucune donnée réelle n'existe. Elle ne contacte pas Ubuntu, Docker, Uptime Kuma ou Cloudflare.

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

Pour exposer localement l'API REST Palworld au robot Discord via Docker Desktop:

```powershell
.\scripts\palworld-api-tunnel.ps1 start
.\scripts\palworld-api-tunnel.ps1 status
```

Le port reste lié à `127.0.0.1`. Le bot doit utiliser l'exemple [bot.env.example](config/exemples/bot.env.example), hors Git une fois rempli.
Si Docker Desktop ne peut pas joindre le LAN à cause d'un subnet Docker concurrent, le même script peut démarrer un tunnel SSH Windows local:

```powershell
.\scripts\palworld-api-tunnel.ps1 start -Mode windows-ssh
```

## Commandes utiles

```powershell
# Validation locale
.\scripts\valider-depot.ps1

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

Les exports publics réels restent non versionnés. Le site lit notamment:

- `public-metrics.json` pour l'état live, les joueurs connectés et `onlineSinceAt`;
- `public-stats.json` pour les sessions et agrégats joueurs;
- `public-save-index.json`, `public-save-snapshot.json`, `public-save-bases.json`, `public-save-diagnostics.json` et `players/{slug}.json` pour les fiches, Pals, bases et exports JSON d'analyse; ces fichiers partagent une génération et l'index devient actif en dernier;
- `public-events-channel.json` pour l'observation et la promotion, `public-events-head-v6.json` comme pointeur actif, le manifeste de compatibilité, les générations immuables `public-events-v6/` et les résumés `public-daily/` pour `/terminal`, `/resume` et les derniers échos de l'accueil;
- les contrats `public-events*.json` v5 pendant la période de compatibilité;
- `public-uptime.json`, `public-uptime-history.json` et `public-availability.json` pour l'état Kuma filtré.

Nginx sert les pages et les JSON v5 dynamiques en `no-store`. Le pointeur actif et le manifeste de compatibilité v6 sont revalidés avec ETag; les manifestes et têtes de génération, fragments, résumés et assets versionnés restent en cache immuable.

Le flux des échos est traité comme une donnée chaude: projection canonique près de SQLite, pointeur actif léger, tête de génération, fragments journaliers immuables et réconciliation complète espacée. L'export v5 complet reste disponible temporairement sans être chargé par les routes v6 normales.

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
- [Opérations](docs/OPERATIONS.md)
- [Bot Discord](docs/BOT-DISCORD.md)
- [Publication GitHub](docs/PUBLIC-REPOSITORY.md)
- [Démarche GitHub du microsite](https://gaylemon.mathieu.pro/github)

## Licence

Le code Gaylémon est sous licence MIT. Palworld, ses ressources et ses marques appartiennent à leurs ayants droit. PalworldSaveTools reste une dépendance séparée avec ses propres licences.

Voir aussi [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
