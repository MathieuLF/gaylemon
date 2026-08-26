# Déploiement

Le déploiement public sur PostgreSQL 16 et DockPanel est décrit dans [Publication sur la VPS Nethercore](VPS-NETHERCORE.md). Cette page reste consacrée aux fichiers d'exploitation du serveur Ubuntu.

Le dépôt peut préparer une livraison Ubuntu, mais rien ne doit partir en production par surprise.

La clé de signature de release s'initialise une seule fois avec `scripts/setup-signing-key.ps1`. Sa clé privée reste sous `~/.gaylemon`, avec un mot de passe protégé par DPAPI; seule `security/cosign.pub` est versionnée.

## Avant de livrer

```powershell
.\scripts\valider-depot.ps1
.\scripts\auditer-source-ubuntu.ps1
```

L'audit compare Git avec les fichiers actifs sur Ubuntu sans utiliser `sudo` et sans modifier le serveur.

## Microsite local

```powershell
docker compose up -d microsite
docker compose ps
```

Le Compose du projet contient les services locaux possédés par Gaylémon: `microsite` et `palworld-api-tunnel`. Ne pas y ajouter cloudflared ni un service de monitoring externe.

Le tunnel API reste local:

```powershell
.\scripts\palworld-api-tunnel.ps1 start
```

## Voir ce qui serait livré

```powershell
.\scripts\deployer-ubuntu.ps1
```

Cette commande affiche le plan. Elle ne téléverse rien.

## Mettre en scène

```powershell
.\scripts\deployer-ubuntu.ps1 -Stage
```

`-Stage` crée une archive, l'envoie sur Ubuntu et l'extrait sous `/tmp/gaylemon-staging/...`.

Cette étape ne copie rien vers `/etc` ou `/srv`, n'appelle pas `sudo` et ne redémarre aucun service.

## Installer

```powershell
.\scripts\deployer-ubuntu.ps1 -Install
```

L'installation:

1. relance la validation locale;
2. prépare une nouvelle zone de stage;
3. demande de retaper l'identifiant de livraison;
4. utilise une seule élévation `sudo`;
5. valide Bash, Python, systemd, sudoers et sysctl côté Ubuntu;
6. sauvegarde les fichiers remplacés;
7. copie les fichiers actifs;
8. exécute `systemctl daemon-reload` si une unité change;
9. ne redémarre aucun service par défaut;
10. relance l'audit.

Quand le wrapper privilégié est installé, la phase root demande toujours une session interactive et une empreinte de manifeste:

```bash
sudo /usr/local/sbin/gaylemon-deploy-install \
  /tmp/gaylemon-staging/AAAAMMJJ-HHMMSS \
  --manifest-sha256 EMPREINTE_SHA256
```

Ce wrapper est borné aux zones de stage Gaylémon et appelle seulement le moteur root-owned sous `/usr/local/libexec/gaylemon`. Le manifeste et chaque source sont revérifiés dans une copie root privée avant installation.

Pour redémarrer un auxiliaire touché:

```powershell
.\scripts\deployer-ubuntu.ps1 -Install `
  -RestartUnit palworld-welcome.service
```

Une livraison Gaylémon refuse toujours `palworld.service`, même lorsqu’un argument de redémarrage est fourni. Une opération sur le jeu passe par la console d’exploitation distincte, avec sa propre autorité et sa propre fenêtre.

## Manifeste

`server/deployment-manifest.json` liste les fichiers Ubuntu gérés par le dépôt: source, destination, propriétaire, mode, validation et politique de redémarrage.

Tout nouveau fichier sous `server/bin`, `server/systemd`, `server/sysctl` ou `server/sudoers` doit être ajouté au manifeste.

Les fichiers privilégiés d'installation sont aussi suivis:

- `server/sbin/gaylemon-deploy-install` -> `/usr/local/sbin/gaylemon-deploy-install`;
- `server/deploy/gaylemon_deploy.py` -> `/usr/local/libexec/gaylemon/gaylemon-deploy`;
- `server/sudoers/palworld-api` -> `/etc/sudoers.d/palworld-api`;
- `server/sudoers/palworld-stats` -> `/etc/sudoers.d/palworld-stats`.

Les scripts qui lisent ou utilisent le mot de passe admin Palworld doivent rester limités au groupe `steam`, ou être appelés par une règle sudoers strictement allowlistée. Ne pas les déployer en `0755`.

Pour les lectures API du microsite et de la console, `palworld-api` autorise seulement:

```text
palworld-api.sh GET /info
palworld-api.sh GET /players
palworld-api.sh GET /metrics
palworld-api.sh GET /settings
palworld-api.sh GET /game-data
```

Si une nouvelle action doit être lancée par SSH, choisir explicitement entre l'appartenance au groupe `steam` et un wrapper/sudoers limité. Ne pas élargir les permissions d'un script pour régler un problème d'accès.

## Retour arrière

Chaque installation produit un reçu et une sauvegarde des fichiers remplacés sous `/var/backups/gaylemon-deploy/`.

Le retour arrière reste manuel. Ne jamais lancer de remise à zéro globale sur les données Palworld.
