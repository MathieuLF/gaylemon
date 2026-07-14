# Configuration locale

## Fichier `.env`

Le fichier `.env` à la racine contient les valeurs propres à l'installation. Il est lu par Docker Compose et par les nouveaux utilitaires PowerShell.

Création sans écrasement:

```powershell
.\scripts\initialiser-projet.ps1
```

Ordre de priorité des scripts PowerShell:

1. variable d'environnement du processus;
2. valeur du fichier `.env`;
3. valeur par défaut sécuritaire.

## Variables

| Variable | Rôle |
|---|---|
| `GAYLEMON_SSH_ALIAS` | alias du serveur dans `~/.ssh/config` |
| `GAYLEMON_SERVER_LAN_IP` | adresse LAN informative |
| `GAYLEMON_REMOTE_PROJECT_ROOT` | racine du projet sur Ubuntu |
| `GAYLEMON_REMOTE_PROJECT_USER` | propriétaire Unix des outils du projet; déduit de `/home/<utilisateur>/` si omis |
| `GAYLEMON_REMOTE_STEAM_ROOT` | racine Steam et Palworld |
| `GAYLEMON_MICROSITE_PORT` | port Nginx lié à `127.0.0.1` |
| `GAYLEMON_MICROSITE_PUBLIC_URL` | URL ouverte par la console |
| `GAYLEMON_METRIC_INTERVAL_SECONDS` | pause du synchroniseur Windows |
| `GAYLEMON_API_LOCAL_PORT` | port local du tunnel REST |
| `GAYLEMON_API_REMOTE_PORT` | port REST sur Ubuntu |
| `GAYLEMON_UPTIME_KUMA_BASE_URL` | URL locale de l'instance Kuma externe |
| `GAYLEMON_UPTIME_KUMA_STATUS_SLUG` | identifiant de la page de statut |
| `GAYLEMON_UPTIME_KUMA_PUBLIC_URL` | page publique ouverte par la console |
| `GAYLEMON_CLOUDFLARED_CONTAINER_PATTERN` | nom utilisé uniquement pour le diagnostic |
| `GAYLEMON_GAME_HOST` | nom public du serveur de jeu |
| `GAYLEMON_GAME_PORT` | port UDP du jeu |
| `GAYLEMON_SAVE_TOOLS_FORK` | fork du parseur suivi |

Le modèle [.env.example](../.env.example) est la référence exhaustive.

## Secrets

Le `.env` du projet ne doit pas devenir un coffre à secrets. Les secrets restent au plus près de leur consommateur:

- clé SSH privée: `~/.ssh`;
- mot de passe admin Palworld: configuration Palworld sur Ubuntu;
- URL Push Uptime Kuma: `/etc/palworld/kuma.env`;
- jeton DNS Cloudflare: `/etc/palworld/palworld.env` si l'actualisation DNS est utilisée;
- jeton du tunnel Cloudflare: infrastructure cloudflared externe.

Ne jamais recopier ces valeurs dans un exemple, une issue, une capture ou un rapport de validation.

## Notes propres à l'instance

`config/local/` accueille les notes, listes de contrôle et fichiers non secrets propres à la machine. Ce répertoire est exclu de Git.

## SSH

Exemple de configuration:

```text
config/exemples/ssh-config.example
```

La clé privée reste hors du projet. Valider l'accès avec:

```powershell
ssh palworld "hostname"
```
