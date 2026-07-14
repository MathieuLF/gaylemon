# Rapport PalworldSaveTools

Genere le 2026-07-14 08:20:58

Base: 8cb429ae3b14
Target upstream: ea6592ebfbb7
Fork: 673505c1abdb
Ubuntu actif: 8cb429ae3b14

## A retenir
- Lecture des guildes/groupes modifiee, dont le format Palworld 2026-07.
- Nouveau diagnostic de sauvegarde pour joueurs orphelins et anomalies de structure.
- Donnees items/skills mises a jour.
- Nouvelles icones de jeu detectees.
- Coeur de decodage des sauvegardes modifie.
- Plusieurs changements concernent Game Pass/XGP.
- Une part importante des commits concerne CI, packaging et releases.

## Pistes Gaylemon
- Verifier si les roles, permissions ou marqueurs de guilde peuvent enrichir les bases et les profils publics sans exposer d'identifiants.
- Ajouter un passage diagnostic hors publication pour expliquer les profils absents, guildes vides ou saves atypiques.
- Rafraichir les libelles, icones et categories utilises dans les evenements craft, production, recherche et inventaire.
- Resynchroniser les assets visuels pour reduire les icones manquantes dans le microsite.
- Impact direct faible pour le serveur dedie Ubuntu, mais utile pour les outils de recuperation hors serveur.

## Points a surveiller
- Contrat a surveiller: membres de guilde, niveau de camp, bases et rattachements joueurs.
- Toujours valider sur une vraie copie de sauvegarde avant activation du lien PalworldSaveTools-current.

## Zones touchees
- icones_jeu: 134 fichier(s), 0 changement(s)
- application_desktop: 31 fichier(s), 1824 changement(s)
- autre: 14 fichier(s), 443 changement(s)
- ci_release: 12 fichier(s), 1233 changement(s)
- traductions: 10 fichier(s), 290 changement(s)
- outils_cli: 5 fichier(s), 376 changement(s)
- donnees_jeu: 3 fichier(s), 10806 changement(s)
- parseur_sauvegarde: 3 fichier(s), 397 changement(s)
- xgp_gamepass: 2 fichier(s), 240 changement(s)
- tests: 1 fichier(s), 182 changement(s)

## Commits recents
- de04f0fb3fe6 - feat: fold Nexus Mods upload into Build All & Release
- 0fd1ae97e1ee - feat: add skip_github_release option with input validation
- a6a15687a470 - refine: compact option titles, remove validate job
- e4ec46efa55a - fix: macOS nexus upload glob (DMG has no V/nk prefix)
- 9de6fe31da31 - feat: standalone nexus-upload workflow, PE metadata flags, unified naming
- 33ebdcce9808 - ci: optimize 5 workflows — composite action, Discord rich embed, template-based release notes
- 156b2721fb63 - fix(discord): correct description string concatenation in embed
- 28df284bd1f5 - fix(ci): checkout before local composite action (cannot self-checkout)
- 7a22ab01e273 - fix(discord): POST via curl to bypass Cloudflare 1010 + add dry_run mode
- c72f36fdaabf - refine(discord): trim redundant embed content
- db6811c71a9e - refine(discord): switch mock/test embed color to light blue
- 3c971f7ddde1 - refine(discord): flatten version fields into single description line
