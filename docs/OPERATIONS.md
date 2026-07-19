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

Les scripts qui lisent ou modifient le serveur doivent rester bornés. Deux modèles existent:

- appartenance de l'utilisateur d'exploitation au groupe `steam` quand le script est exécutable par ce groupe;
- sudoers limité quand une action précise doit rester appelée sans ouvrir les permissions du fichier.

La règle `server/sudoers/palworld-api` autorise seulement ces lectures:

```text
/srv/storage/steam/bin/palworld-api.sh GET /info
/srv/storage/steam/bin/palworld-api.sh GET /players
/srv/storage/steam/bin/palworld-api.sh GET /metrics
/srv/storage/steam/bin/palworld-api.sh GET /settings
/srv/storage/steam/bin/palworld-api.sh GET /game-data
```

Elle ne donne pas accès à `bash`, `python`, `systemctl` ou une commande arbitraire. Pour `Update`, `Backup` ou les annonces, garder les permissions alignées avec le groupe `steam` ou ajouter un wrapper aussi borné que celui-ci.

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
portal/data/players/{slug}.json
portal/data/public-events.json
portal/data/public-events-recent.json
portal/data/public-events-index.json
portal/data/public-events-page-0001.json
portal/data/public-events-manifest-v6.json
portal/data/public-events-head-v6.json
portal/data/public-events-v6/{fragmentGenerationId}/{jour}.json
portal/data/public-daily/{dailyGenerationId}/{jour}.json
portal/public-events-channel.json
```

Synchronisations utiles:

```powershell
.\scripts\sync-palworld-stats.ps1
.\scripts\export-uptime-kuma-history.ps1
.\scripts\sync-palworld-save-snapshot.ps1
.\scripts\sync-palworld-events.ps1
.\scripts\sync-palworld-game-assets.ps1
```

Les métriques rapides, les échos et les fiches joueurs ont des cadences distinctes. Par défaut, le watcher local relit les métriques aux 20 secondes, tente la sync des échos aux 20 secondes et lance une synchronisation indépendante des snapshots joueurs aux 60 secondes, sans chevauchement si la copie précédente est encore en cours. Les données joueurs, profils, Pals, bases, fichiers `players/{slug}.json` et index publics ne dépendent donc plus de la réussite des métriques rapides. Snapshot, bases, diagnostic, fiches et pages joueurs sont préparés avec un `generationId` commun; l'index est remplacé en dernier et le navigateur refuse toute génération mélangée. Une publication interrompue restaure le lot précédent. Le navigateur sonde uniquement la petite tête v6 toutes les 20 secondes, avec validation conditionnelle, puis charge un fragment journalier seulement lorsque son curseur ou sa génération change. Le panneau technique `Données du monde` garde son dernier diagnostic publié et le rafraîchit aux deux heures, sur les créneaux impairs `01:00`, `03:00`, ..., `21:00`, `23:00`.

`public-metrics.json` est la source de l'infobulle des joueurs connectés. Chaque joueur public peut y recevoir `onlineSinceAt`, dérivé de l'historique de sessions, pour afficher l'heure d'arrivée et la durée détectée en ligne.

Les fiches joueurs chargent `players/{slug}.json` à la demande. Le bouton d'export JSON de l'en-tête regroupe les données publiques déjà disponibles: profil complet, activité, progression, inventaire, apparence parsée quand elle existe, Pals en équipe, Pals en Palbox, autres Pals, bases, constructions, travailleurs, stockage et métadonnées des snapshots. Aucun bandeau d'export n'est affiché dans le bas de la fiche.

Les projections publiques retirent les identifiants techniques, secrets, coordonnées brutes et détails de coffres. Un `accountName`, `playerId`, `userId`, Steam ID ou GUID Unreal ne doit pas être publié, même comme nom de secours.

## Journal des événements

Le collecteur `palworld-events.timer` alimente:

```text
/home/gaylemon/Gaylemon/runtime/events/palworld-events.sqlite3
/home/gaylemon/Gaylemon/runtime/public-events.json
/home/gaylemon/Gaylemon/runtime/public-events-recent.json
```

Il publie les événements fiables: arrivées, départs, reconnexions, progression, captures déduites des compteurs, crafts, constructions regroupées, productions confirmées, recherches, bases, réparations, pêche et éclosions strictes.

Les fabrications et productions de sauvegarde sont compilées dans l'export public par fenêtres de 5 minutes, par joueur et par type d'écho. Les événements bruts restent dans SQLite pour audit, mais le terminal reçoit un écho synthétique quand plusieurs lots tombent dans la même fenêtre, avec les quantités et objets fusionnés dans `details.items`.

Il ne publie pas les destructions, transferts, récoltes, coffres ouverts, butins aléatoires ou attributions ambiguës quand la sauvegarde ne permet pas de relier l'action à un joueur avec certitude.

La projection canonique est calculée près de SQLite. Les observations brutes restent privées et auditables; une correction de publication les masque ou les requalifie sans les supprimer. L'identité métier empêche qu'une collecte directe et sa reprise produisent deux niveaux ou deux recherches identiques. Une recherche est publiée une fois par guilde et une attribution estimée reste marquée `derived`; côté portail, elle est libellée comme joueur estimé.

### Reprojection publique contrôlée

Le passage courant met à jour `public-events-recent.json` depuis la queue matérialisée. L'export complet v5 reste froid: il est régénéré au démarrage de la projection, après une reprojection, sur demande, ou au plus tard toutes les 900 secondes. Il peut donc accuser jusqu'à 15 minutes de retard; la synchronisation rapide doit continuer de lire l'export récent.

Une correction ou un backfill antérieur à la queue ouverte produit `canonicalExport.status=reprojection-required` dans le rapport de reprise. Ce statut conserve la projection matérialisée et les deux JSON précédents. Lorsque le poste Windows détecte que la tête chaude est plus avancée que l'export complet froid, il dépose automatiquement une demande de rattrapage complet, puis réessaie la réconciliation jusqu'à retrouver une continuité prouvée. Pour une correction historique volontaire, l'exploitant peut aussi déposer une demande ponctuelle sans arrêter le minuteur:

```bash
install -m 600 /dev/null \
  /home/gaylemon/Gaylemon/runtime/events/public-reprojection.request
```

Le prochain passage consomme ce fichier seulement après une reprojection et un export complet réussis. En cas d'échec, la demande reste présente pour le passage suivant. Une intervention administrateur peut aussi isoler le collecteur puis exécuter directement la commande:

```bash
sudo systemctl stop palworld-events.timer
sudo systemctl stop palworld-events.service
sudo -u gaylemon /usr/bin/python3 \
  /home/gaylemon/Gaylemon/server/bin/palworld-events-collect.py \
  --skip-journal \
  --skip-archive-backfill \
  --reproject-public \
  --write-full-export
sudo systemctl start palworld-events.timer
```

Vérifier ensuite que `canonicalExport.projectionSync=reprojected`, que `canonicalExport.fullExport=written`, que `canonicalExport.reprojectionRequestConsumed=true` pour la voie par fichier et que le rapport ne contient plus `reprojection-required`. `--write-full-export` peut aussi produire un checkpoint complet hors cadence sans refaire la projection. Cette opération ne redémarre pas Palworld.

Le contrat v6 découpe l'historique en fragments journaliers immuables et prépare les résumés quotidiens côté synchronisation. Le terminal reste un journal filtrable par curseur sans paramètre de journée; `/resume` ne recalcule plus la journée depuis des milliers de pages. Le pointeur actif est remplacé en dernier, après vérification des manifestes, têtes, hachages et comptes. Une correction historique réécrit seulement le jour touché. Voir [Échos publics v6](EVENEMENTS-PUBLICS-V6.md).

Les échos publics sont synchronisés en priorité avec le watcher local, avant les métriques générales. La voie rapide remplace la queue canonique couverte par `projectionWindow`, met à jour la fenêtre v5 récente et la génération v6, sans republier les pages ordinales. Une réconciliation complète initiale puis espacée construit le manifeste et les journées. Si le poste redémarre après plusieurs heures et que le complet froid n'a pas encore rattrapé la tête, la synchronisation locale demande un checkpoint complet depuis SQLite côté Ubuntu au lieu de déclarer l'historique à jour. `portal/public-events-channel.json` active v6: le navigateur sonde le petit pointeur avec revalidation conditionnelle; l'export complet v5 reste froid et réservé au repli temporaire.

Lors d'un repli explicite sur v5, le navigateur applique aussi `projectionWindow` à l'historique complet et à la première fenêtre paginée : la queue froide couverte est retirée avant d'ajouter la queue récente canonique. Le total affiché vient alors du flux récent. Les pages ordinales plus profondes restent celles du dernier checkpoint froid et sont réalignées par la prochaine synchronisation complète; elles ne sont jamais décalées ou réécrites partiellement par la voie rapide.

Les contrats v5 continuent d'être publiés pendant la fenêtre de repli temporaire. Ils ne doivent être retirés qu'après confirmation opérationnelle des comptes, doublons, coupures et délais de v6 en exploitation.

Le canal v6 se confirme avec `.\scripts\set-public-events-channel.ps1 -ActiveContract v6`. La commande vérifie le pointeur et son manifeste immuable avant de remplacer le canal. Un repli contrôlé utilise la même commande avec `-ActiveContract v5`.

Les événements de bases utilisent le libellé public le plus utile possible. Quand une base peut être reliée à un joueur, le collecteur convertit les libellés globaux comme `Base 6` en `Base 1`, `Base 2`, etc. selon les bases de ce joueur. Le backfill `baseLabelBackfill` normalise aussi les anciens événements si le snapshot courant permet de retrouver la correspondance.

Un objet transitoire, notamment un dépôt au sol, n'entre jamais dans le calcul des structures. Une réparation est admissible seulement si la même structure passe d'un état endommagé à un état sain; sa disparition ne constitue pas une réparation.

## Sources REST complémentaires

Le collecteur de statistiques interroge `/settings` lentement. Seuls les réglages explicitement autorisés sont exportés: difficulté, taux de jeu, pénalité de mort, limites de bases et guildes, incubation, PvP, voyage rapide et sauvegardes. Toute clé inconnue, adresse, port ou URL reste privée. Les changements sont enregistrés par digest pour éviter les doublons.

`/game-data` est traité comme une capacité variable: `unknown`, `available`, `documented-but-unavailable`, `unsupported` ou `transient-error`. Un échec ne le désactive pas définitivement; un changement de version ou de build réarme la détection et les erreurs temporaires suivent une temporisation. Cette source sert à corroborer les snapshots, jamais à publier directement chaque action volatile.

Les journaux texte et JSON sont reconnus par le collecteur d'événements. Le passage du serveur réel en JSON reste une opération séparée, à faire dans une fenêtre contrôlée. RCON reste désactivé.

## Validation courante

```powershell
.\scripts\valider-depot.ps1
python -m unittest discover -s .\server\tests -v
node --check .\portal\assets\app.js
docker compose config
```
