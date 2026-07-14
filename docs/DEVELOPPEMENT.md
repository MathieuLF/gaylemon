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

## Changer un contrat JSON

Quand un champ public change:

1. adapter le producteur Ubuntu;
2. adapter la synchronisation Windows;
3. adapter le microsite;
4. mettre à jour l'exemple `*.example.json`;
5. ajouter ou corriger les tests;
6. documenter les champs sensibles.

Augmenter la version du contrat quand la compatibilité est rompue.

## Avant un commit

```powershell
.\scripts\valider-depot.ps1
git diff --check
git status --short --ignored
```

Ne pas forcer un fichier ignoré avec `git add -f` sans comprendre pourquoi il est ignoré.
