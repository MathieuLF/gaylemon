# Avis sur les composants tiers

## Palworld

Palworld, ses noms, images, icônes, cartes et autres ressources appartiennent à Pocketpair ou à leurs ayants droit. Gaylémon est un projet communautaire indépendant, sans affiliation ni approbation officielle.

Les ressources extraites localement sont placées sous `portal/assets/game/` et exclues du dépôt public.

Le favicon, la carte sociale et les illustrations d'interface versionnés sous `portal/assets/` sont des créations propres à Gaylémon. Ils n'incorporent aucune image, icône ou carte extraite de Palworld.

## PalworldSaveTools

PalworldSaveTools est installé comme dépendance séparée sous `vendor/PalworldSaveTools/`, exclue de Git. À la révision verrouillée, son projet principal est sous licence MIT, `src/palsav` sous GPL-3.0 et `src/palworld_xgp_import` sous Unlicense. Ces composants ne sont pas redistribués par Gaylémon; consulter leurs fichiers de licence avant toute redistribution séparée.

- amont: `deafdudecomputers/PalworldSaveTools`;
- fork configurable par `GAYLEMON_SAVE_TOOLS_FORK`.
- révision validée: `dependencies/palworld-save-tools.lock.json`.

## Polices

Les polices Nunito et Baloo 2 distribuées sous `portal/assets/fonts/` utilisent la SIL Open Font License 1.1. Le texte de licence est fourni dans [portal/assets/fonts/OFL.txt](portal/assets/fonts/OFL.txt).

## Nginx et images Docker

Le fichier Compose référence l'image officielle Nginx. L'image elle-même n'est pas redistribuée dans ce dépôt et conserve ses propres licences.
