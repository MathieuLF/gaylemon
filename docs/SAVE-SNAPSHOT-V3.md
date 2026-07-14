# Sauvegardes publiques Palworld v3

## But

Le worker `server/bin/palworld-save-snapshot.py` lit une sauvegarde intégrée de Palworld en lecture seule, la copie dans un répertoire temporaire, puis produit deux fichiers:

```text
/srv/example/game-project/runtime/public-save-snapshot.json
/srv/example/game-project/runtime/public-save-diagnostics.json
```

Le premier contient uniquement les données publiques du microsite. Le second décrit la santé de l'analyse. Une erreur de collecte met à jour le diagnostic, mais ne remplace jamais le dernier snapshot public valide.

## Exécution

`palworld-save-snapshot.timer` lance le worker toutes les 15 secondes. Si la dernière génération de sauvegarde a déjà été traitée avec la même révision du parser, le worker termine immédiatement sans redécoder les données. Le service utilise:

- une priorité CPU basse;
- une priorité disque `idle`;
- des poids CPU et I/O minimaux;
- une limite mémoire de 768 Mio;
- un délai maximal de 120 secondes;
- un verrou exclusif dans `runtime` pour refuser tout chevauchement.

Le worker n'écrit jamais dans les sauvegardes Palworld et ne nécessite aucun redémarrage de `palworld.service`.

## Contrat v3

Le snapshot expose les familles suivantes:

- `summary`: joueurs, Pals, guildes et bases;
- `world`: tailles des catalogues Paldex, voyage, zones et boss;
- `guilds`: nom visible, membres, bases et niveau du camp;
- `players[].character`: niveau, expérience, état et allocations;
- `players[].progress.paldex`: catalogue complet des espèces avec numéro, image, état rencontré/capturé, nombre de captures et progression du défi 5/5;
- `players[].progress.quests`: quêtes publiques terminées et quêtes actives, sans identifiants techniques;
- `players[].progress.challenges`: paliers de défis Palworld dont la récompense a été enregistrée;
- `players[].progress.records`: trésors, donjons, pêche, artisanat et autres compteurs persistants fiables;
- `players[].progress.bosses`: victoires normales et tours;
- `players[].progress.exploration`: voyages rapides, zones et cartes;
- `players[].progress.technologies`: technologies résolues par le catalogue;
- `players[].progress.relics`: rangs de bonus permanents;

La sous-version `projection.version` force une nouvelle analyse lorsqu'un champ public est ajouté sans casser le contrat JSON v3.
- `players[].pals.collection`: Pals, talents, passifs, attaques, condensation, âmes, statistiques calculées, aptitude au travail et état;
- `players[].inventory`: inventaires personnels déjà décodés et allowlistés.

Une valeur inconnue reste `null`. Une valeur `0` signifie qu'elle a réellement été mesurée à zéro.

## Confidentialité

Deux allowlists successives sont appliquées:

1. projection Python sur Ubuntu;
2. reconstruction PowerShell dans `scripts/sync-palworld-save-snapshot.ps1`.

Un test bloque les clés contenant `uid`, `guid`, `instance`, `container`, `account`, `steam`, `password`, `token` ou `dynamic_id`. La seule exception est `container`, dont les valeurs publiques sont limitées à `party`, `palbox` ou `other` et ne sont jamais des identifiants Unreal.

Les coordonnées mondiales `x`, `y` et `z` ne sont plus publiées. Le microsite conserve seulement les coordonnées transformées nécessaires aux marqueurs de la carte. Les coordonnées extrêmes situées simultanément dans un coin hors de l'archipel sont marquées `mapVisible: false`: elles correspondent notamment à des zones instanciées ou intérieures et sont présentées comme « zone non cartographiée » plutôt que projetées à tort sur la carte extérieure.

## Diagnostics

Le diagnostic Ubuntu mesure:

- taille de `Level.sav`;
- nombre et taille des fichiers joueurs;
- taille totale de la génération;
- âge du backup sélectionné;
- durée et statut du parse;
- nombres de joueurs, Pals et bases analysés;
- compteurs de structures non résolues, sans leur contenu;
- poids JSON et gzip du snapshot;
- poids de l'archive horaire;
- révision de PalworldSaveTools.

La projection Windows ajoute le poids de l'index, du snapshot public et des cartes WebP. Le microsite affiche ces mesures dans le volet repliable « Données du monde ».

## Chargement du microsite

`public-save-index.json` demeure inférieur à 100 Kio et contient uniquement les résumés utiles à l'accueil. `public-save-snapshot.json` est téléchargé seulement lorsqu'un joueur ouvre une fiche. `public-save-diagnostics.json` est léger et chargé avec les autres résumés.

## Validation locale

```powershell
python -m py_compile .\server\bin\palworld-save-snapshot.py
python -m unittest discover -s .\server\tests -v
node --check .\portal\assets\app.js

$errors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile(
    (Resolve-Path '.\scripts\sync-palworld-save-snapshot.ps1'),
    [ref]$null,
    [ref]$errors
)
$errors
```

Pour tester un candidat Ubuntu sans toucher aux sorties officielles:

```bash
nice -n 19 ionice -c3 \
  /srv/example/game-project/vendor/PalworldSaveTools-current/.venv/bin/python \
  /tmp/palworld-save-snapshot-v3.py \
  --output /srv/example/game-project/runtime/public-save-snapshot.v3.test.json \
  --diagnostics /srv/example/game-project/runtime/public-save-diagnostics.v3.test.json \
  --lock /srv/example/game-project/runtime/palworld-save-snapshot.v3.test.lock \
  --no-archive
```

Projection Windows du candidat:

```powershell
.\scripts\sync-palworld-save-snapshot.ps1 `
  -RemoteSnapshotPath '/srv/example/game-project/runtime/public-save-snapshot.v3.test.json' `
  -RemoteDiagnosticsPath '/srv/example/game-project/runtime/public-save-diagnostics.v3.test.json'
```

## Vérification en exploitation

```powershell
ssh gaylemon "systemctl status palworld-save-snapshot.service --no-pager"
ssh gaylemon "systemctl list-timers palworld-save-snapshot.timer --no-pager"
ssh gaylemon "journalctl -u palworld-save-snapshot.service -n 50 --no-pager"
ssh gaylemon "python3 -m json.tool /srv/example/game-project/runtime/public-save-diagnostics.json >/dev/null"
```

## Extension Bases v1

Les bases, travailleurs, coffres, productions et objets dynamiques sont maintenant décodés dans une sortie lourde distincte. La projection publique agrégée et le snapshot privé sont documentés dans `docs/SAVE-BASES-V1.md`. Les tendances historiques seront dérivées des archives horaires lorsque plusieurs jours de snapshots stables auront été observés.
