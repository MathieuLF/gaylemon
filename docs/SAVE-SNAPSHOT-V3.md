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
portal/data/public-save-diagnostics.json
portal/data/players/{slug}.json
```

Le diagnostic peut être mis à jour même si le dernier snapshot valide est conservé.

## Exécution

`palworld-save-snapshot.timer` vérifie les sauvegardes toutes les minutes.

La synchronisation Windows publie les données joueurs, profils, Pals, bases et index à la minute. Le diagnostic technique visible dans le bloc `Données du monde` du microsite, lui, est conservé entre deux passages et rafraîchi une fois par jour vers 04:00.

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
- bases, travailleurs, structures agrégées et ressources publiques;
- diagnostics légers sur la fraîcheur et le poids des données.

Les valeurs inconnues restent `null`. Un `0` signifie une vraie mesure à zéro.

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
