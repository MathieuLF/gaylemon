# Documentation

Les docs sont rangées par usage. Le README racine suffit pour démarrer; cette page sert d'index.

## Comprendre

- [Architecture](ARCHITECTURE.md): rôles de Windows, Ubuntu, Nginx, Kuma et cloudflared.
- [Source de vérité](SOURCE-DE-VERITE.md): quels fichiers Git représentent les fichiers actifs sur Ubuntu.
- [Sources](SOURCES.md): références externes utiles.

## Installer et travailler

- [Configuration locale](CONFIGURATION-LOCALE.md): `.env`, chemins et secrets.
- [Développement](DEVELOPPEMENT.md): clone local, validation et tests.
- [Déploiement](DEPLOIEMENT.md): stage, installation et règles de redémarrage.
- [Accès LAN](LAN-ACCESS.md): connexion depuis un autre poste de confiance.

## Exploiter

- [Opérations](OPERATIONS.md): console, sauvegardes, mises à jour, stats et microsite.
- [Uptime Kuma](UPTIME-KUMA.md): intégration avec l'instance externe.
- [Personnalisation](CUSTOMIZATION.md): annonces, bienvenue et profil de difficulté.
- [Profil de configuration](CONFIGURATION-AUDIT.md): réglages PvE fournis.

## Données publiques

- [Snapshot public v3](SAVE-SNAPSHOT-V3.md): contrat des données joueurs.
- [Bases publiques v1](SAVE-BASES-V1.md): contrat des bases et stocks agrégés.
- [Plan d'enrichissement](PLAN-ENRICHISSEMENT-SAUVEGARDES.md): historique des choix et reste à faire.
- [Publication du dépôt](PUBLIC-REPOSITORY.md): quoi publier, quoi garder local.

Les données propres à l'instance réelle restent dans `.env`, `config/local/`, `runtime/` ou les fichiers ignorés sous `portal/data/`.
