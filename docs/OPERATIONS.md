# Opérations

Le dépôt gère le microsite, les scripts d'exploitation et les projections publiques. Uptime Kuma et cloudflared restent externes: ne pas les arrêter, les recréer ou les déployer depuis ce projet.

## Console

Depuis Windows:

```powershell
.\Gaylemon Ops Console.ps1
```

Le lanceur racine prépare l'encodage de la console et délègue au vrai menu `scripts\palworld-console.ps1`.

Commandes utiles:

```powershell
.\scripts\palworld-console.ps1 -Action CheckAccess
.\scripts\palworld-console.ps1 -Action Status
.\scripts\palworld-console.ps1 -Action Metrics
.\scripts\palworld-console.ps1 -Action Players
```

Si une commande bloque, commencer par `CheckAccess`.

## Logs

```powershell
.\scripts\palworld-console.ps1 -Action Logs -LogMode service -Follow
.\scripts\palworld-console.ps1 -Action Logs -LogMode game -Follow
.\scripts\palworld-console.ps1 -Action Logs -LogMode backup
.\scripts\palworld-console.ps1 -Action Logs -LogMode update
.\scripts\palworld-console.ps1 -Action Logs -LogMode welcome
.\scripts\palworld-console.ps1 -Action Logs -LogMode kuma
```

`Ctrl+C` quitte le suivi live.

## Maintenance Ubuntu

La voie normale passe par la console, menu `Maintenance Ubuntu guidée`.

| Étape | Effet |
|---|---|
| Auditer | compare le dépôt aux fichiers actifs |
| Prévisualiser | affiche les destinations, sans toucher Ubuntu |
| Mettre en scène | envoie une archive sous `/tmp/gaylemon-staging` et valide |
| Installer | sauvegarde les fichiers remplacés et applique les changements |

Aucun redémarrage de `palworld.service` n'est implicite. Un redémarrage doit être demandé et confirmé à part.

Quand une zone de stage existe déjà, l'installation root non interactive peut être appliquée par le wrapper borné:

```bash
sudo -n /usr/local/sbin/gaylemon-deploy-install /tmp/gaylemon-staging/AAAAMMJJ-HHMMSS
```

Ce wrapper ne donne pas un accès `sudo` général. Il valide le chemin de stage et appelle seulement le script de déploiement Gaylémon.

Reçus et backups de livraison:

```text
/var/backups/gaylemon-deploy/
```

Bilan complet:

```powershell
.\scripts\auditer-maintenance.ps1
```

PalworldSaveTools est aussi vérifié par la tâche Windows `Gaylemon PalworldSaveTools Maintenance`.
Le passage génère `portal/data/palworld-save-tools-update-report.md` et `.json`: révisions comparées, zones touchées, nouveautés utiles, risques et pistes d'optimisation pour Gaylémon.
La mise à jour Ubuntu n'est activée qu'après les tests upstream et un snapshot réel validé; `palworld.service` n'est pas redémarré.

## Services Ubuntu

Ces unités doivent rester `enabled`:

- `palworld.service`
- `palworld-welcome.service`
- `palworld-backup.timer`
- `palworld-update.timer`
- `palworld-kuma-push.timer`
- `palworld-stats.timer`
- `palworld-save-snapshot.timer`
- `palworld-events.timer`
- `palworld-performance.service`

`palworld-performance.service` est un `oneshot`: `inactive (dead)` est normal après succès.

## Microsite local

Le microsite est servi par Docker Compose depuis `portal/`.

```powershell
docker compose up -d microsite
docker compose stop microsite
```

Le conteneur `gaylemon-microsite` sert les exports publics filtrés. Les fichiers bruts de stats ne sont pas exposés.

URL publique:

```text
https://gaylemon.mathieu.pro/
```

Origine locale:

```text
http://127.0.0.1:8787/
```

## Autostart Windows

Ce PC héberge aussi les helpers locaux: tunnel API Docker, microsite Docker et synchronisation des données publiques.

```powershell
.\scripts\palworld-console.ps1 -Action InstallWindowsStartup
.\scripts\palworld-console.ps1 -Action StartupStatus
.\scripts\palworld-console.ps1 -Action StartLocalServices
.\scripts\palworld-console.ps1 -Action StopLocalServices
.\scripts\palworld-console.ps1 -Action UninstallWindowsStartup
```

Le tunnel API est un service Docker Compose avec `restart: unless-stopped`; Docker Desktop le relance quand son moteur redémarre. L'autostart Windows reste utile pour la synchronisation des données publiques et le watcher du microsite.

Audit de reprise:

```powershell
.\scripts\verify-microsite-recovery.ps1
```

Rapports locaux, hors Git:

```text
runtime/recovery/
```

Apres une panne electrique, Internet ou un redemarrage force, lancer:

```powershell
.\scripts\export-uptime-kuma-history.ps1
.\scripts\verify-microsite-recovery.ps1
.\scripts\register-kuma-downtime.ps1
```

Si le rapport `register-kuma-downtime.ps1` liste des candidats valides, appliquer explicitement:

```powershell
.\scripts\register-kuma-downtime.ps1 -Apply
```

Cette commande corrige l'historique Kuma pour les trous ou Kuma etait lui-meme indisponible. Elle cree d'abord une sauvegarde SQLite dans le volume Kuma.

## Updates et backups

Version Steam:

```powershell
.\scripts\palworld-console.ps1 -Action Version
```

Update manuelle:

```powershell
.\scripts\palworld-console.ps1 -Action Update
```

Backup manuel:

```powershell
.\scripts\palworld-console.ps1 -Action Backup
.\scripts\palworld-console.ps1 -Action ListBackups
```

Rappels:

- backup quotidien à 04:00;
- update automatique à 05:00 seulement si Steam publie une nouvelle build;
- update reportée si des joueurs sont connectés;
- sauvegarde obligatoire avant arrêt technique;
- push Uptime Kuma `down` puis `up` pendant une vraie maintenance.

## API Palworld

Palworld écoute localement sur `8212/tcp`, mais UFW bloque l'accès entrant. Les scripts passent par SSH ou par des appels locaux Ubuntu.

```powershell
.\scripts\palworld-console.ps1 -Action Metrics
.\scripts\palworld-console.ps1 -Action Players
.\scripts\palworld-api.ps1 info
.\scripts\palworld-api.ps1 settings
```

Le mot de passe admin est lu sur Ubuntu. Il n'a pas à être copié dans ce dépôt.

Les wrappers qui utilisent l'API REST Palworld sont limités au groupe `steam`. L'utilisateur SSH utilisé pour la console doit donc être membre de ce groupe s'il doit lancer `Metrics`, `Players`, `Update`, `Backup` ou les annonces.

Pour le robot Discord, le tunnel local est géré par Docker Desktop:

```powershell
.\scripts\palworld-api-tunnel.ps1 start
.\scripts\palworld-api-tunnel.ps1 status
```

Le conteneur publie seulement `127.0.0.1:8212` côté Windows. Il monte le dossier `GAYLEMON_SSH_DIR`, ou `~/.ssh` par défaut, en lecture seule. Au démarrage, il copie la configuration pour corriger les permissions OpenSSH, valide les ports, désactive l'agent/X11 et les commandes locales SSH, puis ouvre le forward vers le port REST distant.

Si Docker Desktop ne peut pas joindre l'IP LAN du serveur parce qu'un autre bridge Docker recouvre le même subnet, utiliser le mode SSH Windows:

```powershell
.\scripts\palworld-api-tunnel.ps1 start -Mode windows-ssh
```

Ce mode ouvre le même port local `127.0.0.1:8212` sans passer par le routage réseau de Docker. Pour rendre ce choix persistant avec l'autostart Windows, définir `GAYLEMON_API_TUNNEL_MODE=windows-ssh` dans `.env`.

Configuration privée du bot:

```powershell
Copy-Item .\config\exemples\bot.env.example C:\chemin\du\bot\.env
```

Le fichier rempli ne doit pas revenir dans Git. Le bot doit appeler `http://127.0.0.1:8212/v1/api` depuis cette même machine, avec des délais courts et sans publier dans Discord les erreurs contenant l'URL complète, les en-têtes ou le mot de passe.

Si le conteneur reste `unhealthy` alors que SSH fonctionne depuis Windows, vérifier les réseaux Docker inutilisés qui recouvrent le LAN. Un bridge Docker comme `192.168.80.0/20` capture une adresse `192.168.86.x` avant qu'elle sorte vers le réseau local; supprimer le réseau Docker vide ou déplacer son subnet.

## Données publiques

Les données brutes restent côté Ubuntu ou dans `portal/data/` non public. Le microsite ne lit que les exports `public-*`.

Exports principaux:

```text
portal/data/public-metrics.json
portal/data/public-stats.json
portal/data/public-uptime.json
portal/data/public-uptime-history.json
portal/data/public-availability.json
portal/data/public-save-index.json
portal/data/public-save-snapshot.json
portal/data/public-save-bases.json
portal/data/public-save-diagnostics.json
portal/data/public-events.json
portal/data/public-events-recent.json
portal/data/public-events-index.json
portal/data/public-events-page-0001.json
```

Synchronisations utiles:

```powershell
.\scripts\sync-palworld-stats.ps1
.\scripts\export-uptime-kuma-history.ps1
.\scripts\sync-palworld-save-snapshot.ps1
.\scripts\sync-palworld-events.ps1
.\scripts\sync-palworld-game-assets.ps1
```

Les métriques rapides et les échos sont synchronisés à la minute. Les données joueurs, profils, Pals, bases et index publics passent par la synchronisation snapshot, admissible toutes les 15 minutes côté Windows. Le navigateur relit les exports toutes les 75 secondes pour laisser le temps aux JSON de se stabiliser. Le panneau technique `Données du monde` garde son dernier diagnostic publié et le rafraîchit aux deux heures, sur les créneaux impairs `01:00`, `03:00`, ..., `21:00`, `23:00`.

Les projections publiques retirent les identifiants techniques, secrets, coordonnées brutes et détails de coffres. Un `accountName`, `playerId`, `userId`, Steam ID ou GUID Unreal ne doit pas être publié, même comme nom de secours.

## Journal des événements

Le collecteur `palworld-events.timer` alimente:

```text
/home/gaylemon/Gaylemon/runtime/events/palworld-events.sqlite3
/home/gaylemon/Gaylemon/runtime/public-events.json
/home/gaylemon/Gaylemon/runtime/public-events-recent.json
```

Il publie les événements fiables: connexions, progression, captures déduites des compteurs, crafts, constructions regroupées, productions confirmées, recherches, bases, réparations, pêche et éclosions strictes.

Il ne publie pas les destructions, transferts, récoltes ou attributions ambiguës.

L'export public complet n'est pas plafonné: le terminal doit pouvoir afficher tous les échos publiés. Le flux `public-events-recent.json` reste limité aux derniers échos pour alléger le tableau de bord.

La synchronisation Windows découpe aussi l'historique en `public-events-index.json` et `public-events-page-0001.json`, `public-events-page-0002.json`, etc. Ces fichiers ne remplacent pas l'export complet: ils servent seulement au chargement paresseux du terminal. Les filtres et recherches qui doivent couvrir tout l'historique peuvent toujours relire `public-events.json`.

Les échos publics sont synchronisés à la minute avec le watcher local. Le tableau de bord relit le flux récent; le terminal paginé relit l'index et recharge la page visible quand la révision change.

## Validation courante

```powershell
.\scripts\valider-depot.ps1
python -m unittest discover -s .\server\tests -v
node --check .\portal\assets\app.js
docker compose config
```
