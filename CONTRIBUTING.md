# Contribuer

Les contributions sont bienvenues si elles préservent la confidentialité des joueurs, la cohérence des saisons et la stabilité du portail.

## Règles

- utiliser des données fictives ou anonymisées;
- éviter tout fichier propre à un hébergement ou à un environnement personnel;
- garder les changements de contrat cohérents de bout en bout;
- mettre à jour les exemples et tests lors d’un changement de contrat;
- conserver l’identité visuelle et l’accessibilité du portail;
- versionner CSS et JavaScript par leur contenu, sans cache immuable sur un nom stable.

## Validation

```powershell
.\scripts\upgrade-preflight.ps1 -Mode Inventory
.\scripts\verify-local.ps1 -Mode Quick
git diff --check
```

La description d’une proposition doit préciser les contrats modifiés, les validations exécutées et les risques produit.
