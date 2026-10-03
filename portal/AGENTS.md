# Portail

Les sources sont sous `src`; régénérer les bundles suivis avec `npm run build`, puis `python3 -B scripts/project.py check-dev` (Windows : `python`). Compléter avec `check-browser` pour les changements UI. Ce contrôle ne certifie pas une release.

Conserver l'ordre des imports CSS, l'accessibilité, le cache par empreinte, les contrats de générations et les archives sans sondage. Utiliser uniquement les exemples fictifs. Changer ensemble modèles, projections, exemples, consommateurs, tests et documentation lorsqu'un contrat évolue. Lire `../docs/DEVELOPPEMENT.md`.
