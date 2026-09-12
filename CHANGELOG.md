# Journal des changements

Ce fichier suit le format Keep a Changelog. Les versions publiées suivent SemVer et la valeur canonique de `VERSION`.

## [Non publié]

## [1.0.5] - 2026-09-12

### Corrigé

- L'accueil affiche de nouveau les dernières entrées du terminal avec la même source publique que la page complète, sans pagination locale.

## [1.0.4] - 2026-09-07

### Corrigé

- La consultation hors ligne retrouve les données enregistrées et conserve les réponses réseau même si le stockage du navigateur échoue. Le cache est borné et la page de secours respecte la politique de sécurité.
- Les boutons de la carte mobile, les progressions et les onglets des fiches disposent de noms et d'associations accessibles. Le focus reste stable après filtrage et actualisation.
- Les textes colorés gagnent en contraste; les classements restent utilisables à 320 px et les introductions mobiles occupent moins d'espace.
- La création d'une commande et son journal d'audit sont enregistrés dans une même transaction.
- Les indicateurs historiques de disponibilité sont déclarés indisponibles tant qu'aucun historique ne permet de les calculer.

### Modifié

- Les sources du portail sont séparées progressivement par responsabilité et produisent des actifs minifiés vérifiés avant publication.
- Les parcours navigateur utilisent des données fictives complètes et couvrent les filtres au clavier, les fiches, les actualisations et le rechargement hors ligne.
- Le démarrage local prépare une base isolée et des clés de développement; la console d'exploitation possède des libellés explicites et annonce ses résultats.

## [1.0.3] - 2026-09-02

### Corrigé

- Les couleurs propres aux fiches des joueurs sont de nouveau visibles avec la politique de sécurité du navigateur.
- Les fiches de l’accueil conservent la même hauteur et alignent leurs KPIs et leur bouton, même lorsque les équipes affichées diffèrent.

### Modifié

- Les KPIs des fiches mettent maintenant en avant la collection, l’équipe active et les campements dans une présentation plus sobre.
- La section des destinations de l’accueil emploie un libellé plus clair.
- La page Informations adopte un ton plus naturel et rejoint Confidentialité dans les liens secondaires du pied de page.

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

[Non publié]: https://github.com/MathieuLF/gaylemon/compare/v1.0.5...HEAD
[1.0.5]: https://github.com/MathieuLF/gaylemon/compare/v1.0.4...v1.0.5
[1.0.4]: https://github.com/MathieuLF/gaylemon/compare/v1.0.3...v1.0.4
[1.0.3]: https://github.com/MathieuLF/gaylemon/compare/v1.0.2...v1.0.3
[1.0.2]: https://github.com/MathieuLF/gaylemon/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/MathieuLF/gaylemon/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/MathieuLF/gaylemon/releases/tag/v1.0.0
