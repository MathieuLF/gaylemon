# Déploiement

Le dépôt peut préparer une livraison Ubuntu, mais rien ne doit partir en production par surprise.

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

Le Compose du projet contient les services locaux possédés par Gaylémon: `microsite` et `palworld-api-tunnel`. Ne pas y ajouter Uptime Kuma ou cloudflared.

Le tunnel API reste local:

```powershell
docker compose up -d --build palworld-api-tunnel
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

Pour redémarrer un auxiliaire touché:

```powershell
.\scripts\deployer-ubuntu.ps1 -Install `
  -RestartUnit palworld-welcome.service
```

Pour redémarrer le jeu, il faut le demander explicitement:

```powershell
.\scripts\deployer-ubuntu.ps1 -Install `
  -RestartUnit palworld.service `
  -AllowPalworldRestart
```

Cette option doit rester réservée à une fenêtre annoncée.

## Manifeste

`server/deployment-manifest.json` liste les fichiers Ubuntu gérés par le dépôt: source, destination, propriétaire, mode, validation et politique de redémarrage.

Tout nouveau fichier sous `server/bin`, `server/systemd`, `server/sysctl` ou `server/sudoers` doit être ajouté au manifeste.

## Retour arrière

Chaque installation produit un reçu et une sauvegarde des fichiers remplacés sous `/var/backups/gaylemon-deploy/`.

Le retour arrière reste manuel. Ne jamais lancer de remise à zéro globale sur les données Palworld.
