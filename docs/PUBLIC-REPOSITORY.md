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
