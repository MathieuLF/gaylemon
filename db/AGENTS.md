# PostgreSQL

Ajouter une migration pour faire évoluer le schéma; ne pas réécrire une migration appliquée. Préserver l'isolation des saisons, les archives et les transactions d'ingestion. Tester avec `python3 -B scripts/project.py check-integration` (Windows : `python`, `--postgres docker`). Cette commande crée une base neuve locale; ne pas employer une base réelle.

Compléter le contrôle quotidien décrit dans `../docs/DEVELOPPEMENT.md`; sa réussite seule ne vérifie pas les migrations ni une release. Suppression de données, rétention réelle, archivage d'une installation ou opérations destructrices exigent une instruction explicite.
