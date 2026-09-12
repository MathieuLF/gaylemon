# Dépendances externes

Ce répertoire contient les manifestes et verrous reproductibles, pas les logiciels tiers eux-mêmes.

## PalworldSaveTools

PalworldSaveTools conserve son historique Git, ses auteurs et ses licences dans un dépôt séparé. Gaylémon suit:

- le dépôt amont;
- la branche suivie;
- la révision validée;
- les fichiers copiés dans l'image de release.

Le verrou est [palworld-save-tools.lock.json](palworld-save-tools.lock.json).

Le clone local sous `vendor/PalworldSaveTools/` reste exclu de Git. L'intégrer directement à Gaylémon supprimerait son historique et compliquerait le respect de ses licences. Le fork doit plutôt rester public dans son propre dépôt GitHub.

À la révision verrouillée, le projet principal est sous licence MIT, le composant `src/palsav` sous GPL-3.0 et `src/palworld_xgp_import` sous Unlicense. Ces licences restent celles de PalworldSaveTools et ne remplacent pas la licence MIT du code propre à Gaylémon.

## SteamCMD, Palworld et images Docker

Les binaires de SteamCMD, Palworld et les images Docker ne sont pas redistribués. Les versions et références suivies servent à reconstruire l’environnement de développement ou une release selon les besoins du fork.
