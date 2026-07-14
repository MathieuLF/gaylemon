# Configuration locale

La configuration propre à une machine reste hors Git. Le fichier `.env` sert aux scripts PowerShell et à Docker Compose.

## Mise en place

```powershell
.\scripts\initialiser-projet.ps1
```

Cette commande crée les fichiers attendus sans écraser une configuration existante.

Les scripts lisent les valeurs dans cet ordre:

1. variable d'environnement du processus;
2. fichier `.env`;
3. valeur par défaut prudente.

Le modèle complet est [.env.example](../.env.example).

## Variables utiles

| Variable | Usage |
|---|---|
| `GAYLEMON_SSH_ALIAS` | alias SSH du serveur |
| `GAYLEMON_REMOTE_PROJECT_ROOT` | dossier du projet sur Ubuntu |
| `GAYLEMON_REMOTE_STEAM_ROOT` | dossier Steam/Palworld |
| `GAYLEMON_MICROSITE_PORT` | port local du microsite Docker |
| `GAYLEMON_MICROSITE_PUBLIC_URL` | URL publique ouverte par la console |
| `GAYLEMON_API_LOCAL_PORT` | port local du tunnel REST |
| `GAYLEMON_API_REMOTE_PORT` | port REST Palworld sur Ubuntu |
| `GAYLEMON_UPTIME_KUMA_*` | lecture de la page Kuma publique |
| `GAYLEMON_GAME_HOST` / `GAYLEMON_GAME_PORT` | adresse publique du serveur de jeu |

## Secrets

Le `.env` du dépôt ne doit pas contenir de secrets durables.

- Clé SSH: `~/.ssh`.
- Mot de passe admin Palworld: configuration Palworld sur Ubuntu.
- Push Uptime Kuma: `/etc/palworld/kuma.env`.
- Jetons DNS ou tunnel Cloudflare: fichiers d'infrastructure, hors dépôt.

Ne pas copier ces valeurs dans une issue, une capture ou un rapport.

## Notes locales

`config/local/` peut contenir des notes et listes propres à la machine. Le dossier est ignoré par Git.

Test SSH rapide:

```powershell
ssh gaylemon "hostname"
```

Le tunnel REST utilisé par le robot Discord est lancé par Docker Desktop:

```powershell
docker compose up -d --build palworld-api-tunnel
.\scripts\palworld-api-tunnel.ps1 status
```
