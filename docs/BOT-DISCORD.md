# Bot Discord

Le code du bot Discord n'est pas dans ce dépôt. Gaylémon fournit le tunnel local et le contrat de configuration qui permettent au bot de lire l'API REST Palworld sans exposer ce port sur le réseau.

## Tunnel local

```powershell
.\scripts\palworld-api-tunnel.ps1 start
.\scripts\palworld-api-tunnel.ps1 status
```

Le conteneur Docker publie seulement `127.0.0.1:8212` côté Windows et redémarre avec `restart: unless-stopped`. Le port distant reste le port REST Palworld sur Ubuntu.

Si Docker Desktop ne peut pas joindre l'IP LAN du serveur à cause d'un bridge Docker concurrent, utiliser le mode SSH Windows:

```powershell
.\scripts\palworld-api-tunnel.ps1 start -Mode windows-ssh
.\scripts\palworld-api-tunnel.ps1 status
```

Ce mode garde le même bind local `127.0.0.1:8212`, mais le client SSH tourne côté Windows au lieu du conteneur. Pour l'utiliser aussi au démarrage Windows, définir `GAYLEMON_API_TUNNEL_MODE=windows-ssh` dans `.env`.

Pour limiter l'accès Docker aux clés SSH, créer un dossier dédié contenant uniquement les fichiers nécessaires au tunnel:

```text
config
known_hosts
id_ed25519
id_ed25519.pub
```

Puis définir `GAYLEMON_SSH_DIR` dans `.env`. Si cette variable est vide, le tunnel utilise le dossier SSH par défaut du compte Windows.

## Configuration du bot

Copier l'exemple dans le projet privé du bot, jamais dans ce dépôt:

```powershell
Copy-Item .\config\exemples\bot.env.example C:\chemin\du\bot\.env
```

Valeurs attendues:

```text
BOT_PALWORLD_REST_API_URL=http://127.0.0.1:8212/v1/api
BOT_PALWORLD_REST_API_USERNAME=admin
BOT_PALWORLD_REST_API_PASSWORD=REMPLACER_PAR_LE_MOT_DE_PASSE_ADMIN
```

Le mot de passe correspond au mot de passe admin Palworld. Il doit rester dans la configuration privée du bot ou sur Ubuntu, pas dans Git.

## Comportement attendu du bot

- Appeler uniquement l'URL locale `127.0.0.1`.
- Utiliser un timeout court, autour de 5 secondes.
- Mettre en cache les commandes de statut quelques secondes pour éviter de spammer l'API.
- Limiter les commandes Discord par rôle et par fréquence.
- Afficher des erreurs sobres dans Discord, sans URL complète, en-têtes, mot de passe ou réponse brute de l'API.
- Réserver toute commande d'administration aux rôles explicitement autorisés.

## Diagnostic

```powershell
.\scripts\diagnostiquer-integrations.ps1
.\scripts\valider-depot.ps1
```

Le diagnostic vérifie le conteneur Docker, le mode SSH Windows, la politique de redémarrage, le bind local du port, le dossier SSH, l'exemple de configuration du bot et la réponse HTTP locale sans identifiants. La validation locale échoue si le tunnel Docker devient public ou si les garde-fous principaux disparaissent.
