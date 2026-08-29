# Projections publiques enrichies

## Intention

Gaylémon transforme une source de jeu privée en observations publiques utiles : progression, captures, constructions, explorations et état des bases. Le produit ne publie jamais la sauvegarde brute ni les identifiants techniques qui permettent de la reconstruire.

## Contrat public

Le format `public-save-snapshot-v3` distingue :

- la provenance et l’instant de capture;
- les joueurs visibles et leur progression confirmée;
- les observations dérivées, formulées comme telles;
- les diagnostics publics bornés;
- les éléments volontairement absents parce qu’ils sont privés ou incertains.

Une observation n’est publiée que si sa source est cohérente. Une ancienne projection peut rester lisible pendant qu’une nouvelle génération est préparée; les deux ne sont jamais mélangées.

## Qualité et certitude

- Un fait directement lu est présenté comme observé.
- Une différence calculée est présentée comme une évolution.
- Une association incomplète reste prudente ou n’est pas affichée.
- Un joueur sans projection complète conserve un état d’attente naturel.
- Les exemples du dépôt sont fictifs et ne servent jamais de repli en production.

## Évolution

Les enrichissements doivent préserver la compatibilité du schéma, le caractère déterministe des projections et la possibilité de republier une saison archivée sans accès à la source privée.

Les collecteurs propres à une instance, les chemins sources, les fréquences, les reprises et les procédures d’exploitation sont maintenus par l’autorité privée correspondante.

## Validation

```powershell
.\scripts\verify-local.ps1 -Mode Quick
```

Les contrats Go et les exemples JSON couvrent le filtrage, la cohérence des générations et les erreurs de données. La validation d’une instance réelle est hors du dépôt public.
