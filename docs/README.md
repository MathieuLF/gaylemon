# Documentation Gaylémon

Ce sommaire distingue les guides d'installation, les procédures d'exploitation, les contrats de données et les documents historiques.

## Comprendre et installer

- [Architecture](ARCHITECTURE.md): composants, flux de données et frontières de responsabilité.
- [Configuration locale](CONFIGURATION-LOCALE.md): variables `.env`, secrets et chemins propres à une installation.
- [Développement](DEVELOPPEMENT.md): initialisation d'un clone, tests et contrats JSON.
- [Déploiement prudent](DEPLOIEMENT.md): mise en scène, installation atomique et politiques de redémarrage.
- [Source de vérité](SOURCE-DE-VERITE.md): correspondance entre Git, Windows et les fichiers Ubuntu actifs.

## Exploiter le serveur

- [Opérations](OPERATIONS.md): console, journaux, mises à jour, sauvegardes, statistiques et microsite.
- [Accès LAN](LAN-ACCESS.md): connexion SSH depuis un autre poste de confiance.
- [Uptime Kuma](UPTIME-KUMA.md): intégration avec l'instance externe de surveillance.
- [Personnalisation](CUSTOMIZATION.md): annonces, messages de bienvenue et profil de difficulté.
- [Profil de configuration](CONFIGURATION-AUDIT.md): valeurs PvE fournies et points à évaluer.

## Contrats de données

- [Snapshot public v3](SAVE-SNAPSHOT-V3.md): données joueurs, confidentialité et compatibilité.
- [Bases publiques v1](SAVE-BASES-V1.md): campements, travailleurs, structures et stocks agrégés.
- [Plan d'enrichissement](PLAN-ENRICHISSEMENT-SAUVEGARDES.md): décisions historiques, critères d'acceptation et travaux futurs.

## Publier et attribuer

- [Publication du dépôt](PUBLIC-REPOSITORY.md): fichiers inclus, exclusions et contrôles avant le premier push.
- [Sources](SOURCES.md): documentation officielle et références techniques.
- [Avis sur les composants tiers](../THIRD_PARTY_NOTICES.md): marques, polices et dépendances externes.

## Autorité des documents

Les contrats versionnés et le manifeste de déploiement décrivent le comportement attendu du code. Le plan d'enrichissement conserve le raisonnement historique; son état d'implémentation en tête de document prévaut sur ses anciennes listes d'actions. Les informations propres à une instance réelle doivent rester dans `.env`, `config/local/` ou les données d'exploitation ignorées par Git.
