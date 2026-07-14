# Opérations Palworld

> Le Compose Gaylémon possède uniquement le microsite Nginx. Uptime Kuma et cloudflared sont des services externes partagés: les commandes de ce projet ne doivent jamais les arrêter, les recréer ou modifier leur cycle de vie.

Ce dossier documente l'exploitation du serveur Ubuntu `gaylemon` et du serveur Palworld 1.0.

## État rapide

Depuis ce poste Windows:

```powershell
.\scripts\palworld-console.ps1
```

Depuis l’Explorateur Windows, le fichier à ouvrir est:

```text
Gaylemon Ops Console.cmd
```

Le `.cmd` existe pour une raison pratique: Windows n’exécute pas toujours les `.ps1` au double-clic et peut les ouvrir dans un éditeur ou les bloquer via ExecutionPolicy. Le `.cmd` force l’UTF-8, lance PowerShell avec `-ExecutionPolicy Bypass` pour cet outil local, puis garde la fenêtre ouverte. Le vrai moteur reste `scripts\palworld-console.ps1`.

Usage:

- propose un menu interactif pour les actions courantes;
- vérifie l’accès SSH local avec un prévol dédié;
- affiche l'état rapide;
- ouvre les logs;
- lance les backups, updates et redémarrages avec garde-fous;
- permet d'envoyer des annonces en jeu;
- regroupe l'audit et les livraisons dans le menu `Maintenance Ubuntu guidée`;
- utilise l'alias SSH local `gaylemon`

Commandes directes recommandées:

```powershell
.\scripts\palworld-console.ps1 -Action CheckAccess
.\scripts\palworld-console.ps1 -Action Status
.\scripts\palworld-console.ps1 -Action Metrics
.\scripts\palworld-console.ps1 -Action Players
```

Important: les actions sudo prévues par la console utilisent `sudo -n /usr/bin/systemctl ...` et une règle sudoers limitée. Si la règle manque, la commande échoue au lieu de demander le mot de passe. Pour une commande sudo manuelle non prévue par la console, utiliser une session SSH interactive.

Si une commande ne répond pas, lancer d’abord:

```powershell
.\scripts\palworld-console.ps1 -Action CheckAccess
```

Ce prévol confirme que `ssh.exe` est disponible, que l’alias `gaylemon` existe, et que la connexion sans invite fonctionne.

## Maintenance du code Ubuntu

La voie normale passe par `Gaylemon Ops Console.cmd`, puis `Maintenance Ubuntu guidée`:

1. `Auditer` compare le dépôt aux fichiers réellement actifs, sans `sudo` ni modification.
2. `Prévisualiser` affiche toutes les destinations et les politiques de redémarrage, sans contacter Ubuntu.
3. `Mettre en scène` valide le dépôt, envoie une archive sous `/tmp/gaylemon-staging` et exécute les validateurs Ubuntu sans remplacer de fichier actif.
4. `Installer` refait les validations, demande une confirmation et une seule élévation `sudo`, sauvegarde les versions remplacées puis effectue des remplacements atomiques.

Aucun service n'est redémarré par défaut. Les changements de scripts utilisés par des tâches ponctuelles seront pris en compte à leur prochaine exécution. Un watcher persistant peut être redémarré explicitement après la livraison. Le serveur de jeu exige toujours une autorisation et une confirmation distinctes.

Les reçus et copies précédentes sont conservés sous `/var/backups/gaylemon-deploy/<horodatage>-<livraison>/`. Ils ne contiennent pas les secrets de `/etc/palworld`, qui ne font pas partie des livraisons.

Le menu `Bilan général de maintenance` exécute en une fois la validation du dépôt, l'audit de dérive Ubuntu, le diagnostic Docker/intégrations et la vérification en lecture seule de PalworldSaveTools. Son équivalent direct est:

```powershell
.\scripts\auditer-maintenance.ps1
```

## Redémarrage automatique

Il y a deux côtés à gérer.

Côté Ubuntu, les services critiques sont gérés par `systemd` et doivent rester `enabled`:

- `palworld.service`
- `palworld-welcome.service`
- `palworld-backup.timer`
- `palworld-update.timer`
- `palworld-kuma-push.timer`
- `palworld-stats.timer`
- `palworld-performance.service`

Le push Uptime Kuma vient du serveur Ubuntu via `palworld-kuma-push.timer`; il ne dépend pas du microsite Windows.

Le service `palworld-performance.service` est un `oneshot`: il applique les optimisations puis redevient `inactive (dead)`. C’est normal si le dernier lancement est en `status=0/SUCCESS`.

Côté Windows, ce PC héberge les outils locaux:

- tunnel SSH local `127.0.0.1:8212` pour le bot Discord;
- microsite public `https://gaylemon.mathieu.pro/`, servi par Cloudflare Tunnel vers Docker Desktop;
- rafraîchisseur local des métriques du microsite.

Installer l’autostart Windows:

```powershell
.\scripts\palworld-console.ps1 -Action InstallWindowsStartup
```

Vérifier l’autostart et les services locaux:

```powershell
.\scripts\palworld-console.ps1 -Action StartupStatus
```

Ce statut affiche aussi le dernier audit de reprise du microsite. Lancer l'audit manuellement:

```powershell
.\scripts\verify-microsite-recovery.ps1
```

Au démarrage local, l'audit compare le snapshot et le journal Windows avec les révisions Ubuntu. Une copie en retard déclenche une resynchronisation ciblée. Si le réseau n'est pas encore disponible, le watcher réessaie après une minute jusqu'à obtenir un résultat exploitable.

Les rapports restent dans le projet, hors Git et hors du dossier servi publiquement:

```text
runtime/recovery/microsite-recovery-latest.json
runtime/recovery/microsite-recovery-history.jsonl
```

`complete` signifie que Windows couvre les dernières données Ubuntu. `warning` signifie que la synchronisation est à jour, mais qu'une archive horaire historique manque. `error` signifie que la copie locale reste en retard ou qu'une source distante n'a pas pu être validée.

Démarrer manuellement tout ce qui est local à ce PC:

```powershell
.\scripts\palworld-console.ps1 -Action StartLocalServices
```

Arrêter les helpers locaux:

```powershell
.\scripts\palworld-console.ps1 -Action StopLocalServices
```

Désinstaller l’autostart Windows:

```powershell
.\scripts\palworld-console.ps1 -Action UninstallWindowsStartup
```

Limite importante: l’autostart Windows démarre à l’ouverture de session. Si le PC redémarre mais que personne ne se connecte, le tunnel local et le microsite local ne démarrent pas. Si ton bot Discord est installé comme vrai service Windows qui démarre avant login, il faudra aussi transformer le tunnel en service Windows.

Le microsite est servi par Docker Compose depuis le dossier du projet:

```powershell
docker compose up -d microsite
docker compose stop microsite
```

Le conteneur s'appelle `gaylemon-microsite`. Il ne sert que `portal/`, bloque les fichiers bruts `portal/data/metrics.json` et `portal/data/stats.json`, puis expose les exports publics filtrés.

Pour l'instance Gaylémon, Cloudflare route `gaylemon.mathieu.pro` vers un tunnel externe qui pointe vers l'origine privée `http://host.docker.internal:8787`. Le nom et les identifiants du tunnel restent dans la configuration cloudflared externe. L'origine locale `127.0.0.1:8787` sert seulement au tunnel et au diagnostic; l'URL d'usage est `https://gaylemon.mathieu.pro/`.

Le hostname `gaylemon.mathieu.pro/*` passe aussi par le Worker Cloudflare `maintenance-fallback`. Si Docker Desktop, le conteneur microsite ou la connexion locale tombe, Cloudflare peut afficher la page 503 personnalisée au lieu de l'erreur brute du tunnel.

## Logs à suivre

Le log le plus utile au quotidien est le journal systemd du service:

```powershell
.\scripts\palworld-console.ps1 -Action Logs -LogMode service -Follow
```

Usage:

- `service`: logs systemd principaux du serveur Palworld
- `game`: fichier `Pal.log` généré par Palworld
- `backup`: logs des backups automatisés
- `update`: logs des updates SteamCMD
- `welcome`: logs des messages de bienvenue automatiques
- `kuma`: logs du heartbeat envoyé à Uptime Kuma
- `-Lines 200`: change le nombre de lignes affichées
- `-Follow`: reste attaché aux logs en direct jusqu’à `Ctrl+C`

Le log jeu brut est ici:

```powershell
.\scripts\palworld-console.ps1 -Action Logs -LogMode game -Follow
```

Selon la version/configuration de Palworld, aucun fichier `Pal.log` séparé peut être créé. Dans ce cas, la console bascule automatiquement vers `journalctl -u palworld.service` au lieu d'échouer.

Les logs des automatisations:

```powershell
.\scripts\palworld-console.ps1 -Action Logs -LogMode backup
.\scripts\palworld-console.ps1 -Action Logs -LogMode update
.\scripts\palworld-console.ps1 -Action Logs -LogMode welcome
.\scripts\palworld-console.ps1 -Action Logs -LogMode kuma
```

Quand `-Follow` est actif, utiliser `Ctrl+C` pour quitter le suivi live.

## Version et update

Vérifier si Steam publie une nouvelle build:

```powershell
.\scripts\palworld-console.ps1 -Action Version
```

Usage:

- lit la build actuellement installée dans `appmanifest_2394010.acf`
- interroge SteamCMD pour la build publique de `2394010`
- affiche `up to date` ou `update available`

Installer manuellement une update:

```powershell
.\scripts\palworld-console.ps1 -Action Update
```

L’update automatique est programmée tous les jours à `05:00`. Elle compare d’abord la build installée à la build publique Steam. Si elles sont identiques, elle quitte sans backup, arrêt ni redémarrage.

Lorsqu’une build est disponible, le même garde-fou s’applique à l’update automatique et à l’action manuelle de la console:

1. lire `/players` avant toute opération;
2. reporter l’update si un joueur est connecté ou si la présence ne peut pas être vérifiée;
3. programmer une nouvelle tentative 30 minutes plus tard;
4. annoncer la maintenance à 5 minutes, 1 minute et 30 secondes, avec une nouvelle vérification des joueurs entre chaque étape;
5. exiger le succès de l’appel Palworld `/save`, puis créer obligatoirement l’archive pré-maintenance;
6. arrêter Palworld seulement après le succès de cette sauvegarde et une dernière vérification sans joueur;
7. signaler la maintenance à Uptime Kuma, installer la build, attendre le retour de l’API REST puis renvoyer l’état `UP`.

Un verrou commun empêche une sauvegarde planifiée et une update de manipuler le monde simultanément. Si la sauvegarde pré-maintenance échoue, l’update s’arrête immédiatement et `palworld.service` reste en ligne. Les reports, le compte à rebours, la sauvegarde, l’arrêt technique, la reprise et les échecs sont publiés dans le `Journal des échos` du microsite par `palworld-events.service`.

## Backups

Un backup systemd est programmé tous les jours à `04:00`.

Ce backup quotidien est un backup à chaud: il ne redémarre pas Palworld et ne coupe pas les joueurs. Avant d'archiver les fichiers, le script appelle la REST API locale `POST /v1/api/save`, attend quelques secondes, puis crée l'archive `.tar.zst`.

Si l'appel `/save` échoue, le script continue quand même l'archive pour éviter de manquer complètement le backup planifié. Les backups internes de Palworld restent aussi actifs via `bIsUseBackupSaveData=True`.

L'update automatique de `05:00` ne touche au serveur que si la build publique diffère de la build installée. Dans ce cas, le backup pré-update et son appel `/save` ont lieu avant l'arrêt. Une coupure réellement observée est envoyée explicitement à Uptime Kuma, puis le retour `UP` est envoyé seulement lorsque l'API REST répond de nouveau.

Lancer un backup manuel:

```powershell
.\scripts\palworld-console.ps1 -Action Backup
```

Lister les backups:

```powershell
.\scripts\palworld-console.ps1 -Action ListBackups
```

Palworld garde aussi ses propres backups internes quand `bIsUseBackupSaveData=True`.

## API locale Palworld

La REST API Palworld est active sur le serveur, mais elle n'est pas ouverte dans UFW.

Usage prévu:

- Palworld écoute sur `8212/tcp`
- UFW bloque explicitement `8212/tcp` en entrée
- accessible depuis le serveur via l'appel local des scripts
- appelee depuis ce poste au travers de SSH
- non exposee a Internet
- non exposee directement au LAN

Voir l’état API:

```powershell
.\scripts\palworld-console.ps1 -Action Metrics
.\scripts\palworld-console.ps1 -Action Players
.\scripts\palworld-api.ps1 info
```

Usage:

- `info`: version, nom, description et identifiant du monde
- `metrics`: joueurs connectés, FPS serveur, uptime, base camps
- `players`: liste des joueurs connectés
- `settings`: configuration exposée par l’API Palworld
- le script lit le `AdminPassword` directement sur le serveur via SSH; il n'a pas besoin que le mot de passe soit dans ce dossier

## Statistiques locales

Le microsite conserve un historique local dans:

```text
portal/data/stats.json
```

La source fiable est côté Ubuntu:

```text
/srv/storage/steam/servers/palworld/stats/stats.json
palworld-stats.service
palworld-stats.timer
```

Le timer `palworld-stats.timer` collecte toutes les 30 secondes, même si ce PC Windows est fermé. Le microsite synchronise ensuite une copie locale dans `portal/data/stats.json`, puis génère:

```text
portal/data/public-metrics.json
portal/data/public-stats.json
portal/data/public-uptime.json
portal/data/public-save-index.json
portal/data/public-save-snapshot.json
portal/data/public-save-diagnostics.json
```

Le site lit uniquement les fichiers `public-*`. Ils retirent les identifiants techniques, arrondissent les positions REST avant affichage, et publient la barre Uptime Kuma sans exposer la configuration interne de Kuma.

### Progression issue des sauvegardes

Le worker Ubuntu suivant complète les données REST sans dépendre de `/game-data`:

```text
palworld-save-snapshot.service
palworld-save-snapshot.timer
/home/gaylemon/Gaylemon/runtime/public-save-snapshot.json
/home/gaylemon/Gaylemon/runtime/public-save-bases.json
/home/gaylemon/Gaylemon/runtime/private-save-bases.json
/home/gaylemon/Gaylemon/runtime/public-save-diagnostics.json
```

Toutes les 15 secondes, il vérifie la dernière sauvegarde intégrée complète. Une génération déjà publiée avec la même révision du parser est ignorée immédiatement; une nouvelle génération est copiée dans un répertoire temporaire puis analysée avec une priorité CPU et disque basse. Il ne déclenche pas de sauvegarde supplémentaire, ne modifie jamais une sauvegarde et ne redémarre jamais `palworld.service`.

`bIsUseBackupSaveData=True` demande déjà à Palworld de conserver cinq sauvegardes espacées de 30 secondes, six espacées de 10 minutes, douze horaires et sept quotidiennes. Le worker lit simplement la génération terminée la plus récente. Le backup d'archives quotidien de 4 h reste un mécanisme distinct qui appelle REST `/save` avant de créer son archive `tar.zst`.

Le JSON public contient:

- nom visible, niveau, expérience, statistiques, guilde et dernière position sauvegardée;
- inventaires personnels regroupés avec quantités et icônes;
- collection détaillée des Pals: niveau, PV, talents, passifs, compétences, condensation, âmes, statistiques calculées, aptitudes de travail, équipe ou Palbox;
- Paldex, captures, boss vaincus, exploration, voyages rapides, reliques et technologies détaillées;
- points technologiques, quêtes, guildes et bases.

La sortie Bases ajoute les Pals travailleurs, leur état et leur tâche, les structures, travaux, coffres, ressources agrégées et recherches de guilde. Le détail exact des conteneurs reste dans le fichier privé Ubuntu en mode `0600`; il n'est ni synchronisé vers Windows, ni monté dans Docker, ni servi publiquement. Les mesures de charge et le contrat complet sont documentés dans `docs/SAVE-BASES-V1.md`.

Il exclut toujours les identifiants joueur/Steam, identifiants de conteneurs, coordonnées Unreal précises, mots de passe et autres clés techniques. Une seconde projection allowlist est appliquée sur Windows par:

```powershell
.\scripts\sync-palworld-save-snapshot.ps1
```

Le rafraîchisseur normal `update-microsite-metrics.ps1` exécute déjà cette synchronisation. Le watcher Windows relance un cycle 10 secondes après le précédent et le navigateur vérifie les JSON toutes les 15 secondes sans recharger la page. Avec les sauvegardes Palworld, les timers Ubuntu et les temps de traitement observés, la chaîne vise une fraîcheur publique maximale inférieure à deux minutes, y compris après deux cycles locaux expirés au timeout de 30 secondes.

Les ressources visuelles sont statiques entre deux mises à jour de PalworldSaveTools. Leur vérification exhaustive est exécutée au plus toutes les six heures plutôt qu'à chaque cycle live, afin de réserver les synchronisations fréquentes aux données qui changent réellement.

Le fichier de diagnostic mesure la taille de la génération, la durée du parse, la taille des sorties et la révision du parser. Le microsite en publie une projection limitée dans le volet « Données du monde ». Les compteurs détaillés de structures inconnues restent sur Ubuntu.

Une archive détaillée compressée est conservée au maximum une fois par heure pendant 30 jours:

```text
/home/gaylemon/Gaylemon/runtime/save-snapshot-history/YYYY/MM/DD/HH.json.gz
```

Ces archives ne sont pas synchronisées vers le microsite et ne sont jamais versionnées dans Git.

Le collecteur d'événements les utilise comme journal de reprise. Après une interruption, il sélectionne seulement les heures postérieures à son dernier snapshot traité, les rejoue chronologiquement, puis applique le snapshot courant. Une archive déjà traitée est ignorée, les empreintes SQLite empêchent les doublons et les heures absentes sont inscrites dans:

```text
/home/gaylemon/Gaylemon/runtime/events/palworld-events-recovery.json
```

Les ressources visuelles runtime sont synchronisées depuis PalworldSaveTools par:

```powershell
.\scripts\sync-palworld-game-assets.ps1
```

Le synchroniseur copie tous les catalogues d'icônes disponibles, notamment `pals`, `items`, `technologies`, `structures`, `npcs`, `passives`, `elements` et `ui`. Son marqueur contient la révision du parser et la version du contrat de synchronisation. Même lorsque cette révision n'a pas changé, il vérifie que chaque fichier source existe dans `portal/assets/game` avec la bonne taille avant de déclarer les ressources à jour.

Le Paldex du microsite utilise les 288 espèces affichables du même catalogue. Les espèces inconnues restent sous forme de silhouettes verrouillées; leurs images natives sont tout de même synchronisées afin que la fiche se révèle automatiquement dès qu'une rencontre est enregistrée. Les chemins d'images publiés sont validés contre `portal/assets/game`, et l'interface affiche un monogramme de secours si une future mise à jour introduit momentanément une ressource sans image.

Chaque joueur dispose aussi d'une projection publique individuelle sous `portal/data/players/{slug}.json`. La fiche charge ce fichier plutôt que le snapshot global, puis rend le Paldex, les Pals, l'inventaire, les bases et les technologies uniquement à leur première ouverture. L'onglet `Mon Paldex` possède également sa propre route partageable `/joueur/{slug}/paldex/`. La carte personnelle a été remplacée par les coordonnées publiques arrondies déjà présentes dans le profil.

### Historique public des événements

`palworld-events.timer` exécute toutes les 30 secondes un collecteur indépendant. Son historique permanent et son export public se trouvent sur Ubuntu:

```text
/home/gaylemon/Gaylemon/runtime/events/palworld-events.sqlite3
/home/gaylemon/Gaylemon/runtime/public-events.json
```

Le premier passage importe tout l'historique encore retenu par `journald` et les archives horaires de sauvegarde disponibles. Les passages suivants utilisent le curseur du journal, le snapshot courant et uniquement la fenêtre d'archives susceptible de contenir un état plus récent que le dernier état traité. Une reprise après plusieurs heures conserve ainsi les étapes horaires disponibles au lieu de fusionner toute la progression dans un seul événement. Le collecteur conserve les arrivées, départs et jalons de progression. Il rejette les adresses IP, identifiants Steam/joueur, tentatives de connexion et messages de clavardage.

Le collecteur de statistiques conserve aussi, uniquement sur Ubuntu, les 200 dernières sessions REST échantillonnées de chaque joueur. Si une transition `/players` ne possède aucun événement `journald` équivalent à 60 secondes près, le journal ajoute cette arrivée ou ce départ avec la source interne `players`. La base SQLite reste le registre brut et ne supprime jamais un log Palworld. La réconciliation se fait seulement dans l'export public: lorsqu'un second départ est émis alors que le joueur est déjà hors ligne, puis qu'il revient dans les deux minutes, cette paire trompeuse est remplacée par une seule « Reconnexion ». Un vrai départ suivi d'un retour reste affiché comme deux événements distincts.

Palworld ne journalise pas les captures individuellement, mais la sauvegarde conserve `PalCaptureCount` par espèce. Le collecteur publie donc les premières captures, les captures supplémentaires et les défis 5/5 à partir des variations de ce compteur. Une simple hausse du nombre de Pals possédés reste une acquisition d'origine inconnue: elle peut provenir d'une éclosion, d'un élevage ou d'un transfert et n'est jamais présentée comme une capture.

Le premier passage de la projection enrichie rejoue une fois les archives horaires existantes afin de reconstruire les captures observables. Cette reprise est idempotente et commence au premier snapshot public conservé; elle ne fabrique pas de date antérieure. Le journal publie aussi les quêtes terminées, les paliers de défis, les trésors et les expéditions dont les compteurs sont persistants. Le jeu ne conserve pas le nombre de sphères lancées, leur type, les Pals ordinaires tués ni le lien entre un objet et sa source de butin. Ces informations ne doivent pas être inférées depuis l'inventaire.

Depuis le journal repliable de l'accueil, le bouton « Ouvrir le terminal en grand » ouvre la route `#terminal`. Cette vue conserve le header et le footer, affiche uniquement le terminal et permet de choisir 25, 50, 100 ou 250 échos par page.

La projection Windows applique une seconde liste blanche avant de publier les données:

```powershell
.\scripts\sync-palworld-events.ps1
```

Le microsite charge tout l'historique public, mais n'affiche que cinq événements par page. La recherche et les filtres sont exécutés localement sans nouvel appel au serveur.

### Date de lancement affichée

Le début officiel de l'aventure est fixé au 10 juillet 2026, le serveur ayant ouvert dans la nuit du 9 au 10. Le KPI « Jours d'aventure » compte le 10 juillet comme premier jour et ne dépend pas de l'uptime du processus Palworld. Son infobulle rappelle la date réelle de lancement.

Les fiches joueur utilisent une vue plein écran avec un seul conteneur de défilement. La page d'accueil est verrouillée pendant l'ouverture, puis revient exactement à sa position précédente à la fermeture.

Elles sont placées dans `portal/assets/game/`, servi par Docker mais ignoré par Git. Voir `docs/PUBLIC-REPOSITORY.md` avant toute publication.

### Maintenance de PalworldSaveTools

Le fork est public et reste séparé du dépôt Gaylémon:

```text
https://github.com/MathieuLF/PalworldSaveTools
```

Vérifier seulement:

```powershell
.\scripts\check-palworld-save-tools.ps1
```

Synchroniser le fork et préparer une nouvelle version Ubuntu:

```powershell
.\scripts\check-palworld-save-tools.ps1 -SyncFork -UpdateRemote
```

Chaque candidat est cloné dans un dossier versionné, compilé et soumis aux tests unitaires du parseur ainsi qu'à une lecture réelle en mode lecture seule. Le lien symbolique `PalworldSaveTools-current` ne change qu'après tous les succès. Une version défectueuse reste inactive et n'affecte ni le jeu ni le snapshot public précédent.

La vérification périodique est un script interne au projet. Installer la tâche Windows hebdomadaire:

```powershell
.\scripts\install-palworld-save-tools-maintenance.ps1
```

La tâche `Gaylemon PalworldSaveTools Maintenance` exécute `run-palworld-save-tools-maintenance.ps1` le lundi à 9 h et écrit son journal dans `portal/data/palworld-save-tools-maintenance.log`. Elle dépend des authentifications `gh` et SSH de cet utilisateur Windows; elle ne contient aucun jeton dans le dépôt.

Une règle sudoers limitée permet à la console de déclencher les actions Palworld approuvées sans demander le mot de passe sudo:

```text
/etc/sudoers.d/palworld-console
```

Actions approuvées sans mot de passe:

```text
/usr/bin/systemctl start palworld-backup.service
/usr/bin/systemctl start palworld-update.service
/usr/bin/systemctl restart palworld.service
/usr/bin/systemctl restart palworld-welcome.service
/usr/bin/systemctl start palworld-kuma-push.service
/usr/bin/systemctl start palworld-stats.service
```

La synchronisation peut aussi être forcée à la main:

```powershell
.\scripts\palworld-console.ps1 -Action RefreshStats
```

Voir un résumé dans la console:

```powershell
.\scripts\palworld-console.ps1 -Action Stats
```

Ce qui est fiable:

- échantillons serveur via `/metrics`;
- joueurs actuellement connectés via `/players`;
- nombre de connexions observées par joueur;
- temps de jeu total estimé par joueur;
- dernier niveau, ping, position et `building_count` observés quand le joueur est en ligne.

Ce qui est estimé:

- les heures jouées et les connexions sont calculées par snapshots réguliers, pas par un compteur officiel Palworld;
- une session très courte entre deux snapshots peut ne pas être comptée.

Ce qui dépend de l’API avancée:

- `/game-data` peut exposer des acteurs du monde, des guildes et PalBox selon la version serveur;
- si le serveur retourne `404` ou `405`, les stats de base continuent, mais les bases par guilde et détails d’acteurs restent indisponibles;
- après un `404` ou `405`, le collecteur marque `collection.gameDataStatus=disabled` et ne reprobe plus automatiquement `/game-data`;
- le serveur actuel répond `PalGameDataBridge GameData API is not enabled`;
- la documentation officielle Palworld 1.0 décrit bien `GET /game-data`, mais la page de configuration ne publie que `RESTAPIEnabled` et `RESTAPIPort` pour la REST API;
- le build Linux 1.0 contient `EnableGameDataAPI`, `IsGameDataAPIEnabled` et `SetGameDataAPIEnabled`;
- les en-têtes générés du Palworld Modding Kit identifient `UPalCheatManager::EnableGameDataAPI()` comme une commande Unreal `Exec`, et non comme un paramètre INI documenté;
- cette commande cachée n'est pas dans la liste officielle des commandes administrateur et `/EnableGameDataAPI` retourne `Unknown command` après authentification admin en jeu;
- le binaire ne publie aucun endpoint REST générique pour exécuter une commande, et la liste officielle des arguments de démarrage 1.0 ne contient aucun argument d'activation de `game-data`;
- l'activation nécessiterait donc un chemin non pris en charge, comme un mod serveur ou une injection de commande Unreal. Ne pas utiliser ces méthodes sur le serveur live tant que leur compatibilité 1.0 et leur impact ne sont pas validés;
- pour retester `/game-data` après une mise à jour Palworld, il faudra remettre ce statut à `unknown` lors d’une fenêtre de maintenance, sans le faire en boucle pendant que le serveur est live.

Les niveaux, guildes, bases, Pals, technologies et quêtes affichés sur le microsite ne dépendent plus de cet endpoint: ils proviennent du worker de sauvegarde décrit ci-dessus. `/game-data` resterait utile pour un véritable instantané des acteurs en direct, mais n'est plus bloquant pour les statistiques de progression.

### Bot Discord sur ce PC Windows

Si un bot Discord tourne sur ce PC Windows et attend une URL REST, ne pas utiliser directement `http://ADRESSE_LAN:8212`: le port est bloqué par UFW volontairement.

Démarrer plutôt le tunnel SSH local:

```powershell
.\scripts\palworld-console.ps1 -Action StartApiTunnel
```

Puis utiliser dans le `.env` du bot:

```env
BOT_PALWORLD_REST_API_URL=http://127.0.0.1:8212/v1/api
BOT_PALWORLD_REST_API_USERNAME=admin
BOT_PALWORLD_REST_API_PASSWORD=<Palworld AdminPassword>
```

Vérifier ou arrêter le tunnel:

```powershell
.\scripts\palworld-console.ps1 -Action ApiTunnelStatus
.\scripts\palworld-console.ps1 -Action StopApiTunnel
```

Envoyer une annonce en jeu:

```powershell
.\scripts\palworld-console.ps1 -Action Announce -Message "Bienvenue sur Gaylemon. Capturez fort, mourrez peu."
```

Usage:

- envoie une annonce en jeu via l'API REST Palworld
- conserve les accents et espaces grâce à un encodage base64 côté client
- exemple: `.\scripts\palworld-console.ps1 -Action Announce -Message "Événement ce soir: chasse aux boss à 20h30."`

## Bienvenue automatique

Le service `palworld-welcome.service` surveille la liste des joueurs via l'API locale et envoie un message fun quand un joueur rejoint.

Voir ses logs:

```powershell
.\scripts\palworld-console.ps1 -Action Logs -LogMode welcome -Follow
```

Redémarrer le watcher:

```powershell
.\scripts\palworld-console.ps1 -Action RestartWelcome
```

Le service choisit au hasard parmi plusieurs dizaines de messages humoristiques et parfois sarcastiques. Il évite une répétition immédiate pour un même joueur et garde un anti-spam de 30 minutes: une reconnexion rapide ne déclenche donc pas une nouvelle annonce.

## Mots de passe Palworld

Il y a deux mots de passe distincts:

- mot de passe serveur: demandé aux joueurs quand ils rejoignent le serveur
- mot de passe admin: donne les privilèges admin dans le chat et permet l’authentification REST API

Pour devenir admin en jeu:

```text
/AdminPassword MOT_DE_PASSE_ADMIN
```

Le mot de passe admin n’est pas demandé à la connexion initiale. Un admin se connecte comme joueur normal avec le mot de passe serveur, puis utilise `/AdminPassword` dans le chat en jeu.

Points à vérifier si la commande ne fonctionne pas:

- le `/` au début est requis;
- il faut un espace entre `/AdminPassword` et le mot de passe;
- la casse du mot de passe compte;
- le mot de passe admin ne remplace jamais le mot de passe serveur à l'écran de connexion;
- les privilèges admin sont liés à la session en cours et peuvent devoir être redemandés après reconnexion.

Lire les valeurs actuellement configurées:

```powershell
ssh gaylemon "perl -ne 'if (/(ServerPassword|AdminPassword)=\"([^\"]*)\"/) { print qq($1=SET\n) }' /srv/storage/steam/servers/palworld/game/Pal/Saved/Config/LinuxServer/PalWorldSettings.ini"
```

Par sécurité, les mots de passe réels ne sont pas documentés en clair dans ce dossier.
