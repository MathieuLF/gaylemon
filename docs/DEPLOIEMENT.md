# Déploiement prudent

## Objectif

Le dépôt distingue quatre opérations:

- préparer et valider le code local;
- auditer les fichiers réellement actifs;
- mettre en scène les fichiers Ubuntu dans `/tmp`;
- installer transactionnellement un changement approuvé.

Cette distinction empêche une publication GitHub ou un test local de toucher le serveur en production.

Avant toute livraison, vérifier que les fichiers actifs proviennent bien des sources Git:

```powershell
.\scripts\auditer-source-ubuntu.ps1
```

## Microsite local

Le seul service Compose appartenant au projet est `microsite`:

```powershell
docker compose up -d microsite
docker compose ps
```

Uptime Kuma et cloudflared doivent déjà exister dans leur propre environnement. Ne pas les ajouter au Compose Gaylémon.

## Aperçu Ubuntu

```powershell
.\scripts\deployer-ubuntu.ps1
```

Cette commande liste la cible, le répertoire de préproduction et tous les fichiers concernés. Elle ne crée aucune archive et ne contacte pas le serveur.

## Manifeste unique

`server/deployment-manifest.json` est la définition commune de l'audit et de l'installation. Il contient uniquement les fichiers actifs gérés par Gaylémon et précise:

- la source versionnée;
- la destination Ubuntu autorisée;
- le propriétaire, le groupe et le mode Unix;
- le validateur à exécuter;
- l'unité éventuellement concernée;
- la politique `none`, `recommended` ou `game`.

Un fichier sous `server/bin`, `server/systemd`, `server/sysctl` ou `server/sudoers` qui n'est pas déclaré fait échouer `valider-depot.ps1`.

Les jetons `{{REMOTE_PROJECT_ROOT}}`, `{{REMOTE_STEAM_ROOT}}` et `{{REMOTE_PROJECT_USER}}` sont résolus depuis le `.env` local au moment de créer la livraison. Le manifeste publié ne contient donc pas les particularités du compte Ubuntu d'une autre installation.

## Mise en scène Ubuntu

```powershell
.\scripts\deployer-ubuntu.ps1 -Stage
```

`-Apply` reste accepté comme alias historique de `-Stage`.

La commande:

1. crée une archive locale sous `runtime/deploy/`;
2. la téléverse par SSH;
3. l'extrait dans `/tmp/gaylemon-staging/<horodatage>`;
4. affiche les fichiers distants;
5. supprime l'archive temporaire distante.

Elle n'utilise pas `sudo`, ne copie rien vers `/etc` ou `/srv`, et n'exécute pas `systemctl`. Le plan distant signale les fichiers différents, inchangés ou protégés.

## Installation sur Ubuntu

```powershell
.\scripts\deployer-ubuntu.ps1 -Install
```

L'installation reste une opération d'exploitation explicite. La commande:

1. exécute la validation locale;
2. crée et valide une nouvelle zone de mise en scène;
3. demande de retaper l'identifiant exact de la livraison;
4. utilise une seule élévation `sudo`;
5. revalide Bash, Python, systemd, sudoers et sysctl sur Ubuntu;
6. sauvegarde les fichiers remplacés sous `/var/backups/gaylemon-deploy`;
7. remplace chaque fichier de manière atomique;
8. exécute `systemctl daemon-reload` seulement si une unité a changé;
9. ne redémarre aucun service par défaut;
10. relance l'audit de dérive après l'installation.

Si une copie échoue pendant l'installation, les fichiers déjà remplacés sont restaurés depuis la sauvegarde de la livraison.

Pour redémarrer un auxiliaire explicitement lié à un fichier modifié:

```powershell
.\scripts\deployer-ubuntu.ps1 -Install `
  -RestartUnit palworld-welcome.service
```

Le redémarrage du jeu est bloqué sans les deux garde-fous suivants et ne doit être utilisé que pendant une fenêtre annoncée:

```powershell
.\scripts\deployer-ubuntu.ps1 -Install `
  -RestartUnit palworld.service `
  -AllowPalworldRestart
```

Une seconde phrase de confirmation est alors exigée. Une modification de `palworld-start.sh` ou de `palworld.service` peut normalement attendre le prochain redémarrage planifié.

Avant toute livraison sensible:

1. comparer la version active et la zone de préproduction;
2. exécuter les tests et vérifications syntaxiques;
3. identifier précisément les unités touchées;
4. confirmer si un redémarrage du jeu est vraiment requis;
5. planifier une fenêtre si Palworld doit être interrompu.

Un changement de collecteur ou de watcher ne justifie pas automatiquement un redémarrage de `palworld.service`.

Lorsque le dépôt GitHub public existera, `/home/.../Gaylemon` pourra devenir un checkout de déploiement. Les fichiers actifs sous `/srv` et `/etc` resteront des copies installées explicitement; ils ne seront jamais remplacés par un `git pull` automatique.

## Reçus et retour arrière

Chaque installation produit un reçu `receipt.json` et une copie des seuls fichiers remplacés sous `/var/backups/gaylemon-deploy/<horodatage>-<livraison>/`. Le chemin du reçu est affiché à la fin de l'installation. Un retour arrière doit cibler uniquement les fichiers de ce reçu et l'unité concernée; il reste volontairement manuel pour éviter qu'une ancienne livraison écrase une correction plus récente.

Ne jamais utiliser une commande globale de remise à zéro ou supprimer récursivement les données Palworld.
