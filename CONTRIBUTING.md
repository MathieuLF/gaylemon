# Contribuer à Gaylémon

Les contributions sont bienvenues lorsqu'elles préservent la sécurité du serveur, la confidentialité des joueurs et la simplicité d'exploitation.

## Avant de commencer

1. Ouvrir une issue pour les changements de contrat JSON, de déploiement ou d'architecture.
2. Créer une branche courte et ciblée.
3. Utiliser uniquement des données fictives dans les tests et exemples.
4. Ne jamais joindre une sauvegarde Palworld réelle, un fichier `.env`, une clé SSH ou un jeton.

## Installation locale

```powershell
.\scripts\initialiser-projet.ps1
.\scripts\valider-depot.ps1
```

L'initialisation ne doit pas écraser une configuration ou des données existantes.

## Règles techniques

- Conserver PowerShell 5.1 compatible pour la console Windows.
- Conserver les scripts Ubuntu compatibles Bash.
- Ajouter ou adapter les tests Python lors d'un changement de collecteur.
- Versionner tout changement de contrat JSON et fournir un exemple fictif.
- Actualiser le verrou PalworldSaveTools seulement après une validation Ubuntu réussie.
- Exécuter l'audit de source avant de proposer un changement aux scripts Ubuntu.
- Ajouter chaque nouveau fichier Ubuntu actif à `server/deployment-manifest.json` avec une destination, des permissions et une politique de redémarrage minimales.
- Ne pas ajouter Uptime Kuma ou cloudflared au Compose Gaylémon.
- Ne pas introduire de commande de redémarrage implicite.
- Toute action destructive ou distante doit être explicite et documentée.

## Validation

Avant une demande de fusion:

```powershell
.\scripts\valider-depot.ps1
git diff --check
git status --short --ignored
```

La validation ne doit pas dépendre d'un serveur Palworld réel.

## Demande de fusion

Expliquer:

- le problème résolu;
- les comportements modifiés;
- les risques d'exploitation;
- les validations réellement exécutées;
- les migrations manuelles requises, s'il y en a.
