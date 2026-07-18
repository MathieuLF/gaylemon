# Snapshot public v3

`server/bin/palworld-save-snapshot.py` lit une copie terminée des sauvegardes Palworld et publie les données utiles au microsite. Il ne modifie jamais les saves et ne redémarre pas `palworld.service`.

## Fichiers produits

Sur Ubuntu:

```text
/home/gaylemon/Gaylemon/runtime/public-save-snapshot.json
/home/gaylemon/Gaylemon/runtime/public-save-diagnostics.json
```

Sur le microsite:

```text
portal/data/public-save-index.json
portal/data/public-save-snapshot.json
portal/data/public-save-bases.json
portal/data/public-save-diagnostics.json
portal/data/players/{slug}.json
portal/joueur/{slug}.html
```

Tous ces artefacts portent le même `generationId`. Le diagnostic peut conserver
une observation technique antérieure, mais sa publication reste rattachée au
même snapshot public que l'index, les bases et les fiches joueurs.

## Exécution

`palworld-save-snapshot.timer` vérifie les sauvegardes toutes les 30 secondes, avec `OnUnitInactiveSec` pour éviter les chevauchements si une génération prend plus longtemps.

La synchronisation Windows vérifie les données joueurs, profils, Pals, bases et
index publics toutes les 60 secondes. Le diagnostic technique visible dans le
bloc `Données du monde` du microsite, lui, est conservé entre deux analyses
lourdes et rafraîchi aux deux heures, sur les créneaux impairs `01:00`, `03:00`,
..., `21:00`, `23:00`.

La publication prépare et valide la génération entière dans un répertoire
temporaire. Les artefacts sont remplacés avec reprise temporisée, les fiches et
pages joueurs sont publiées comme un lot, puis `public-save-index.json` devient
actif en dernier. Un verrou empêche deux synchronisations de se chevaucher. En
cas d'échec, la génération précédente est restaurée intégralement. Le portail
refuse un snapshot, des bases, un diagnostic ou une fiche dont le
`generationId` diffère de celui de l'index actif.

Le service utilise:

- priorité CPU basse;
- I/O idle;
- verrou exclusif;
- limite mémoire;
- écriture atomique.

Une génération déjà analysée avec la même révision du parseur est ignorée.

## Données publiques

Le contrat v3 expose:

- résumé du monde, joueurs, guildes et bases;
- progression Paldex, boss, exploration, quêtes, technologies et reliques;
- Pals possédés avec statistiques utiles, passifs, attaques et aptitudes;
- inventaires personnels allowlistés;
- données de personnage parsées quand PalworldSaveTools les fournit dans une forme publiable;
- bases, travailleurs, structures agrégées et ressources publiques;
- diagnostics légers sur la fraîcheur et le poids des données.

Les valeurs inconnues restent `null`. Un `0` signifie une vraie mesure à zéro.

## Fiches et export JSON

Le tableau de bord charge `public-save-index.json` au départ, puis `players/{slug}.json` seulement quand une fiche joueur est ouverte.

Chaque fiche peut exporter un JSON d'analyse localement depuis le navigateur. Cet export utilise uniquement les données publiques en vigueur:

- profil, guilde, niveau, position publique et données de personnage disponibles;
- Pals en équipe;
- Pals en Palbox;
- autres Pals publics;
- bases reliées au joueur ou à sa guilde;
- constructions, travailleurs, recherches de base et stockage agrégé;
- métadonnées de version et d'horodatage des snapshots.

L'export ne contient pas de GUID, Steam ID, conteneur privé, chemin système ou détail exact de coffre. Il ne remplace pas les contrats publics; il les regroupe dans un fichier pratique pour analyse.

La visualisation 3D ou portrait fidèle du personnage n'est pas encore un contrat garanti. Les champs de style, coupe, yeux, sexe ou apparence peuvent être conservés si le parseur les expose de façon stable et non sensible, mais le microsite doit rester capable d'afficher la fiche sans rendu visuel complet.

## Confidentialité

Deux projections filtrent les données:

1. Python sur Ubuntu;
2. PowerShell dans `scripts/sync-palworld-save-snapshot.ps1`.

Le public ne reçoit pas:

- GUID, UID, Steam ID ou identifiants de conteneur;
- mots de passe, tokens, chemins système;
- coordonnées Unreal brutes;
- contenu exact des coffres privés.

Les marqueurs de carte utilisent seulement une position publique arrondie ou transformée.

## Validation

```powershell
python -m py_compile .\server\bin\palworld-save-snapshot.py
python -m unittest discover -s .\server\tests -v
node --check .\portal\assets\app.js
node --test .\portal\tests\portal-v6-static.test.mjs
pwsh -NoProfile -File .\scripts\test-public-save-snapshot-sync.ps1
```

Syntaxe PowerShell:

```powershell
$errors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile(
    (Resolve-Path '.\scripts\sync-palworld-save-snapshot.ps1'),
    [ref]$null,
    [ref]$errors
)
$errors
```

Vérification Ubuntu:

```powershell
ssh gaylemon "systemctl status palworld-save-snapshot.service --no-pager"
ssh gaylemon "journalctl -u palworld-save-snapshot.service -n 50 --no-pager"
```
