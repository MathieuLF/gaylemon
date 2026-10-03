# Développement et validation

Lire `../docs/DEVELOPPEMENT.md` pour le setup et le périmètre des profils.
Après le setup, utiliser `python3 -B scripts/project.py check-dev` (Windows : `python`). Compléter avec `check-integration` pour métier, permissions, ingestion ou migrations et `check-browser` pour UI. Le profil quotidien n'est pas une certification Full ou de release.

Préserver les commandes Quick/Full et leurs exigences de publication. Ne jamais utiliser une clé de release, publier, contacter une instance réelle ou modifier ses services sans instruction explicite. Les scripts doivent échouer sur un contrôle en échec, préserver les fichiers suivis et retirer uniquement leurs propres ressources temporaires. Ne pas restaurer automatiquement les fichiers pour masquer une différence de build.
