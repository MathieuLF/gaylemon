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

Pour les échos v6, modifier ensemble la projection canonique, le manifeste, la tête, les fragments journaliers, les résumés et leurs exemples. `/terminal` reste un journal filtrable par curseur sans paramètre de journée; `/resume` lit le résumé précalculé de la journée sélectionnée. Les fabrications et productions peuvent rester compilées en fenêtres publiques de 5 minutes, avec les quantités cumulées dans `details.items`. Une journée inchangée doit conserver son fragment immuable, une génération partielle ne doit jamais devenir active et les observations privées ne doivent pas être supprimées lors d'une correction publique. Les contrats v5 restent testés tant que la période de compatibilité n'est pas terminée. Voir [Échos publics v6](EVENEMENTS-PUBLICS-V6.md).

Pour les fiches joueurs, vérifier que l'export JSON reste déclenché seulement par le bouton d'en-tête de la fiche et qu'il ne contient que les données publiques déjà prévues: profil complet, activité, progression, inventaire, Pals en équipe, Pals en Palbox, bases, constructions, stocks agrégés et métadonnées de snapshot.

## Avant un commit

```powershell
.\scripts\valider-depot.ps1
git diff --check
git status --short --ignored
```

Ne pas forcer un fichier ignoré avec `git add -f` sans comprendre pourquoi il est ignoré.
