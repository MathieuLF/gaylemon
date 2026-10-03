# Services et contrats

Lire `../docs/ARCHITECTURE.md` et `../docs/DEVELOPPEMENT.md`. Utiliser le profil quotidien `python3 -B scripts/project.py check-dev` (Windows : `python`); compléter avec `check-integration` pour métier, permissions, ingestion, rétention ou saisons. Le profil léger ne certifie pas Full ni une release.

Préserver signatures Ed25519, limites, protection contre le rejeu et activation transactionnelle des projections filtrées. Ne pas publier de sauvegardes, identifiants techniques ou secrets. Toute opération sur un agent, service, réseau ou base réelle exige une instruction explicite.
