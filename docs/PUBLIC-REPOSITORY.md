# Publication GitHub

Le dépôt peut être public, mais pas les données du serveur.

## Publiable

- code PowerShell, Python, Bash, HTML, CSS et JavaScript;
- unités `systemd` et modèles de configuration;
- tests et fixtures fictives;
- documentation;
- polices et licences;
- favicon, carte sociale et assets propres à Gaylémon;
- Nginx, Compose et verrous de dépendances.

Les fichiers `*.example.json` sous `portal/data/` sont publiables seulement parce qu'ils sont fictifs. Ils doivent rester suffisants pour développer le microsite depuis un clone propre.

## À exclure

- `.env`, clés, jetons, certificats;
- sauvegardes, journaux, PID et bases SQLite;
- `portal/data/*.json`, sauf `*.example.json`;
- `portal/data/players/`;
- `portal/joueur/`;
- `portal/assets/game/`;
- `runtime/`;
- `vendor/PalworldSaveTools/`;
- caches, rapports, sorties Playwright et dépendances locales.

## Avant de pousser

```powershell
.\scripts\valider-depot.ps1
.\scripts\auditer-source-ubuntu.ps1
git status --short
git status --ignored --short
git ls-files --cached --others --exclude-standard
```

Relire surtout la dernière commande. Elle montre ce qui peut entrer dans Git.

Vérifier qu'il n'y a pas:

- mot de passe Palworld;
- URL Push Kuma avec jeton;
- jeton Cloudflare;
- clé SSH;
- sauvegarde ou profil réel;
- adresse IP publique;
- export brut de l'API REST.

Vérifier aussi qu'un export public réel ne contient pas de `accountName`, `playerId`, `userId`, Steam ID, GUID Unreal, chemin système, coordonnée brute ou détail de coffre.

## Créer le dépôt

```powershell
git branch -M main
git add --all
git commit -m "Publication initiale de Gaylémon"
gh repo create MathieuLF/Gaylemon --public --source . --remote origin --push
```

Après le push:

1. relancer la validation locale depuis le clone publié;
2. activer le signalement privé de vulnérabilité;
3. renseigner la description, le site et les sujets;
4. relire le README public.

## Données du microsite

Les fichiers `public-*` produits en exploitation sont faits pour être servis au public, mais ils ne sont pas versionnés. Les `*.example.json` suffisent pour travailler depuis un clone propre.

Contrats servis en production:

- `public-metrics.json`: état live, joueurs connectés, noms affichables et `onlineSinceAt`;
- `public-stats.json`: sessions, temps de jeu et agrégats joueurs;
- `public-save-index.json`: index léger des fiches joueurs;
- `players/{slug}.json`: profil public détaillé à la demande;
- `public-save-snapshot.json`: projection publique complète v3;
- `public-save-bases.json`: bases, constructions, travailleurs, productions et stocks agrégés;
- `public-save-diagnostics.json`: fraîcheur et poids des exports;
- `public-events.json`: historique complet des échos;
- `public-events-recent.json`: fenêtre récente de 2 000 échos pour le tableau de bord;
- `public-events-index.json` et `public-events-page-*.json`: pagination de `/terminal`;
- `public-uptime.json`, `public-uptime-history.json`, `public-availability.json`: état Kuma filtré.

`public-events-sync-state.json` est un état local de synchronisation, ignoré comme les autres données réelles. Il ne fait pas partie des contrats publics versionnés.

Les pages générées sous `portal/joueur/` et les données réelles sous `portal/data/players/` restent ignorées. La route publique des fiches s'appuie sur le JavaScript et les JSON synchronisés, pas sur une donnée joueur versionnée.

Nginx sert les JSON dynamiques et les pages principales avec `no-store`. Les assets versionnés peuvent être en cache long, mais un changement de contenu doit garder une version d'URL cohérente.

Pour créer les fichiers canoniques à partir des exemples:

```powershell
.\scripts\initialiser-projet.ps1
```

## Ressources Palworld

Les ressources extraites du jeu restent locales:

```powershell
.\scripts\sync-palworld-game-assets.ps1
```

Elles vivent sous `portal/assets/game/`, ignoré par Git.

## Si un secret fuit

Révoquer le secret, en créer un nouveau, puis nettoyer l'historique avant toute publication. Le supprimer du dernier commit ne suffit pas.
