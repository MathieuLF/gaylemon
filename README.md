# Gaylémon

[![Licence MIT](https://img.shields.io/badge/licence-MIT-2f855a.svg)](LICENSE)

Gaylémon regroupe les outils autour d'un serveur Palworld privé: console d'exploitation, scripts Ubuntu, collecteurs, projections publiques et microsite.

Le principe est simple: Palworld reste stable, les sauvegardes sont lues en lecture seule, et le site ne reçoit que des données filtrées. Les secrets, les sauvegardes réelles et les données privées ne vont pas dans Git.

## Ce que contient le dépôt

- `server/`: scripts Ubuntu, unités `systemd`, collecteurs et tests.
- `scripts/`: console et outils Windows.
- `portal/`: microsite statique et exemples JSON.
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

Pour exposer localement l'API REST Palworld au robot Discord via Docker Desktop:

```powershell
docker compose up -d --build palworld-api-tunnel
```

Le port reste lié à `127.0.0.1`.

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

## Documentation

- [Sommaire](docs/README.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Configuration locale](docs/CONFIGURATION-LOCALE.md)
- [Développement](docs/DEVELOPPEMENT.md)
- [Déploiement](docs/DEPLOIEMENT.md)
- [Opérations](docs/OPERATIONS.md)
- [Publication GitHub](docs/PUBLIC-REPOSITORY.md)
- [Démarche GitHub du microsite](https://gaylemon.mathieu.pro/github)

## Licence

Le code Gaylémon est sous licence MIT. Palworld, ses ressources et ses marques appartiennent à leurs ayants droit. PalworldSaveTools reste une dépendance séparée avec ses propres licences.

Voir aussi [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
