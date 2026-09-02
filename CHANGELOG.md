# Journal des changements

Ce fichier suit le format Keep a Changelog. Les versions publiées suivent SemVer et la valeur canonique de `VERSION`.

## [Non publié]

## [1.0.2] - 2026-09-02

### Modifié

- La mesure d’audience publique utilise désormais GoatCounter auto-hébergé, avec des chemins préfixés par domaine et sans requêtes, fragments, référents, titres ni identifiants bruts.
- Les anciens marqueurs Umami, Google Analytics, Matomo et équivalents sont explicitement exclus du site publié.

## [1.0.1] - 2026-08-29

### Modifié

- Le profil Gaylémon suit la révision 2.3.0 du socle commun.
- CSS et JavaScript sont servis sous des noms liés à leur contenu, avec manifeste public et conservation de la release précédente.
- Le dépôt public ne contient plus de domaine, topologie, chemin, adaptateur ou runbook propre à une instance.
- La validation bloque désormais toute réintroduction de ces détails dans la branche active.
- Le prédicat de release utilise un URN produit indépendant de la destination d’exécution.

## [1.0.0] - 2026-08-28

### Modifié

- La version du produit est désormais une valeur SemVer commune à toute la suite, sans préfixe `v` dans les interfaces ni les reçus.
- Le reçu de validation locale suit le contrat vérifiable `suite.local-validation.v2` révision `2.1.0`.
- L’image web publie maintenant ses métadonnées OCI et un contrôle de santé natif.

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

[Non publié]: https://github.com/MathieuLF/gaylemon/compare/v1.0.2...HEAD
[1.0.2]: https://github.com/MathieuLF/gaylemon/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/MathieuLF/gaylemon/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/MathieuLF/gaylemon/releases/tag/v1.0.0
