# Développement

## Initialiser une copie

```powershell
git clone https://github.com/MathieuLF/Gaylemon.git Gaylemon
Set-Location .\Gaylemon
.\scripts\initialiser-projet.ps1
```

Les JSON de démonstration permettent d'ouvrir le microsite sans serveur Ubuntu.

## Validation locale

```powershell
.\scripts\valider-depot.ps1
```

Options:

```powershell
# Ne pas interroger Docker
.\scripts\valider-depot.ps1 -SansDocker

# Validation syntaxique rapide
.\scripts\valider-depot.ps1 -SansDocker -SansTestsPython -SansBash
```

La commande complète vérifie:

- présence des fichiers essentiels;
- syntaxe de tous les scripts PowerShell;
- validité des JSON d'exemple;
- syntaxe JavaScript;
- tests Python;
- syntaxe Bash lorsque Git Bash est disponible;
- exclusions Git des données locales;
- validité du Compose sans lancer de conteneur.

## Tests Python

```powershell
python -m unittest discover -s .\server\tests -p "test_*.py" -v
```

Les fixtures doivent rester fictives et ne contenir aucun identifiant issu d'une sauvegarde réelle.

## Microsite de démonstration

```powershell
.\scripts\initialiser-projet.ps1
docker compose up -d microsite
```

Le conteneur monte `portal/` en lecture seule. Les données d'exemple sont copiées vers leurs noms canoniques uniquement si aucun fichier réel n'existe.

## Contrats JSON

Lorsqu'un contrat change:

1. augmenter sa version si la compatibilité est rompue;
2. adapter le producteur Ubuntu;
3. adapter la projection Windows;
4. adapter le consommateur du microsite;
5. ajouter ou corriger les tests;
6. actualiser le fichier `*.example.json` correspondant;
7. documenter la confidentialité des nouveaux champs.

## Git

Avant de publier:

```powershell
.\scripts\valider-depot.ps1
git status --short
git status --ignored --short
git diff --check
```

Ne jamais forcer l'ajout d'un fichier ignoré avec `git add -f` sans comprendre pourquoi il est exclu.
