# Contribuer

Les contributions sont bienvenues si elles gardent le serveur stable et les données privées.

## Avant de coder

- Ouvrir une issue pour un changement de contrat JSON, de déploiement ou d'architecture.
- Travailler sur une branche courte.
- Utiliser seulement des données fictives.
- Ne jamais joindre de sauvegarde réelle, `.env`, clé SSH ou jeton.

## Préparer le dépôt

```powershell
.\scripts\initialiser-projet.ps1
.\scripts\valider-depot.ps1
```

L'initialisation ne doit pas écraser une config locale.

## Règles pratiques

- Garder la console compatible Windows PowerShell 5.1.
- Garder les scripts Ubuntu compatibles Bash.
- Tester les collecteurs Python quand ils changent.
- Mettre à jour les exemples JSON avec les contrats publics.
- Ajouter tout nouveau fichier Ubuntu actif dans `server/deployment-manifest.json`.
- Ne pas ajouter Uptime Kuma ou cloudflared au Compose.
- Ne pas introduire de redémarrage implicite, surtout pour `palworld.service`.

## Avant une demande de fusion

```powershell
.\scripts\valider-depot.ps1
git diff --check
git status --short --ignored
```

Dans la description, indiquer:

- ce qui change;
- les risques d'exploitation;
- les validations réellement faites;
- les actions manuelles à prévoir.
