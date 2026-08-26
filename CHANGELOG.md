# Journal des changements

Ce fichier suit le format Keep a Changelog. Les versions publiées utilisent la date et la révision canonique de `VERSION`.

## [Non publié]

## [2026.08.26.2] - 2026-08-26

### Modifié

- Gitleaks, Syft, Trivy et Cosign s’exécutent avec des images conteneur épinglées afin de rendre les validations et releases reproductibles.
- Le scan Gitleaks porte sur l’instantané Git suivi du commit validé et exclut les données locales non versionnées.

## [2026.08.26.1] - 2026-08-26

### Ajouté

- Cycle de vie multi-saisons avec archives publiques figées et manifeste SHA-256 déterministe.
- État public de saison, commandes d’exploitation bornées et refus d’ingestion après clôture.
- Palette de navigation `Ctrl/Cmd+K`, continuité hors ligne et page d’informations.

### Modifié

- Validation Go en mode `-mod=readonly`; les dépendances externes ne sont plus chargées depuis un répertoire `vendor` local.
