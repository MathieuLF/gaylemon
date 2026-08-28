# Journal des changements

Ce fichier suit le format Keep a Changelog. Les versions publiées suivent SemVer et la valeur canonique de `VERSION`.

## [Non publié]

### Modifié

- Le profil Gaylémon suit la révision 2.2.0 du socle commun, avec contrat d’exploitation et reçu de release `suite.release.v1`.
- Les sauvegardes d’exploitation utilisent désormais un vocabulaire Restic hors site indépendant du fournisseur et du déployeur.
- La validation Full rejoue les migrations et scénarios multi-saisons sur PostgreSQL 16 isolé; Quick vérifie systématiquement les invariants de l’agent et l’interdiction de redémarrer Palworld.
- Le Full lie désormais Gitleaks, Trivy FS et deux SBOM source au commit et à l’arbre Git exacts, et refuse une preuve upstream incomplète ou divergente.

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
