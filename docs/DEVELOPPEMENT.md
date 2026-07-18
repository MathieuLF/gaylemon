# Développement

## Préparer un clone

```powershell
git clone https://github.com/MathieuLF/Gaylemon.git Gaylemon
Set-Location .\Gaylemon
.\scripts\initialiser-projet.ps1
```

Le script prépare les dossiers ignorés et copie des exemples JSON si les données réelles sont absentes. Il ne contacte pas Ubuntu.

## Valider

```powershell
.\scripts\valider-depot.ps1
```

Pour une passe plus rapide:

```powershell
.\scripts\valider-depot.ps1 -SansDocker -SansTestsPython -SansBash
```

La validation complète couvre surtout:

- syntaxe PowerShell, Bash et JavaScript;
- JSON d'exemple;
- tests Python;
- exclusions Git;
- configuration Compose.

## Tester les collecteurs

```powershell
python -m unittest discover -s .\server\tests -p "test_*.py" -v
```

Les fixtures doivent rester fictives. Pas de sauvegarde réelle, pas d'identifiant joueur réel.

## Ouvrir le microsite

```powershell
docker compose up -d microsite
```

Le conteneur monte `portal/` en lecture seule. Les exemples suffisent pour travailler sur l'interface sans serveur Palworld.

Routes locales utiles:

- `http://127.0.0.1:8787/`: tableau de bord;
- `http://127.0.0.1:8787/terminal`: terminal plein écran des échos;
- `http://127.0.0.1:8787/resume`: résumé quotidien des joueurs;
- `http://127.0.0.1:8787/classements`: palmarès dédié;
- `http://127.0.0.1:8787/carte`: carte dédiée de Palpagos;
- `http://127.0.0.1:8787/github`: page technique publique.

## Changer un contrat JSON

Quand un champ public change:

1. adapter le producteur Ubuntu;
2. adapter la synchronisation Windows;
3. adapter le microsite;
4. mettre à jour l'exemple `*.example.json` ou le contrat `players/{slug}.json` correspondant;
5. ajouter ou corriger les tests;
6. documenter les champs sensibles.

Augmenter la version du contrat quand la compatibilité est rompue.

Pour les échos, garder ensemble `public-events.json`, `public-events-recent.json`, `public-events-index.json` et `public-events-page-*.json`. Le dashboard peut lire le flux récent de 2 000 échos, mais `/terminal` doit rester capable de consulter l'historique complet et de filtrer sans changer de structure. `/resume` compile une journée en chargeant seulement les pages dont la plage horaire touche la date choisie. Les fabrications et productions peuvent être compilées en fenêtres publiques de 5 minutes; les tests doivent vérifier que `details.items` garde les quantités cumulées. `public-events-sync-state.json` est un état local ignoré. La sync rapide `-Fast` ne reconstruit que le flux récent, l'index et la première page; la sync sans `-Fast` reconstruit toute la pagination.

Pour les fiches joueurs, vérifier que l'export JSON ne contient que les données publiques déjà prévues: Pals en équipe, Pals en Palbox, bases, constructions, stocks agrégés et métadonnées de snapshot.

## Avant un commit

```powershell
.\scripts\valider-depot.ps1
git diff --check
git status --short --ignored
```

Ne pas forcer un fichier ignoré avec `git add -f` sans comprendre pourquoi il est ignoré.
