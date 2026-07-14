# Dépendances externes

Ce répertoire contient les manifestes et verrous reproductibles, pas les logiciels tiers eux-mêmes.

## PalworldSaveTools

PalworldSaveTools conserve son historique Git, ses auteurs et ses licences dans un dépôt séparé. Gaylémon suit:

- le dépôt amont;
- le fork utilisé en production;
- la branche suivie;
- la révision validée et active;
- les chemins locaux et Ubuntu attendus.

Le verrou est [palworld-save-tools.lock.json](palworld-save-tools.lock.json).

Le clone local sous `vendor/PalworldSaveTools/` reste exclu de Git. L'intégrer directement à Gaylémon supprimerait son historique et compliquerait le respect de ses licences. Le fork doit plutôt rester public dans son propre dépôt GitHub.

À la révision verrouillée, le projet principal est sous licence MIT, le composant `src/palsav` sous GPL-3.0 et `src/palworld_xgp_import` sous Unlicense. Ces licences restent celles de PalworldSaveTools et ne remplacent pas la licence MIT du code propre à Gaylémon.

## SteamCMD, Palworld et images Docker

Les binaires de SteamCMD, Palworld et les images Docker ne sont pas redistribués. Le dépôt conserve les scripts d'installation, les fichiers Compose et les versions d'image nécessaires pour les réinstaller.
