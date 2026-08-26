# Journal des changements

Ce fichier suit le format Keep a Changelog. Les versions publiées utilisent la date et la révision canonique de `VERSION`.

## [Non publié]

### Ajouté

- Cycle de vie multi-saisons avec archives publiques figées et manifeste SHA-256 déterministe.
- État public de saison, commandes d’exploitation bornées et refus d’ingestion après clôture.
- Palette de navigation `Ctrl/Cmd+K`, continuité hors ligne et page d’informations.

### Modifié

- Validation Go en mode `-mod=readonly`; les dépendances externes ne sont plus chargées depuis un répertoire `vendor` local.
