# Contribuer

Les contributions sont bienvenues si elles préservent la confidentialité des joueurs, la cohérence des saisons et la stabilité du portail.

## Règles

- utiliser uniquement des données fictives;
- ne jamais ajouter de domaine, d’hôte, de chemin ou de runbook propre à une instance;
- garder les mutations, leur audit et leur activation atomiques;
- mettre à jour les exemples et tests lors d’un changement de contrat;
- conserver l’identité visuelle et l’accessibilité du portail;
- versionner CSS et JavaScript par leur contenu, sans cache immuable sur un nom stable.

## Validation

```powershell
.\scripts\upgrade-preflight.ps1 -Mode Inventory
.\scripts\verify-local.ps1 -Mode Quick
git diff --check
```

La description d’une proposition doit préciser les contrats modifiés, les validations exécutées et les risques produit, sans inclure de détail d’exploitation privé.
