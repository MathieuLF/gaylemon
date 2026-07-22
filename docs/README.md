# Documentation

Les docs sont rangées par usage. Le README racine suffit pour démarrer; cette page sert d'index.

## Comprendre

- [Architecture](ARCHITECTURE.md): rôles de Windows, Ubuntu, Nginx, routes publiques et contrats JSON.
- [Source de vérité](SOURCE-DE-VERITE.md): quels fichiers Git représentent les fichiers actifs sur Ubuntu.
- [Sécurité d'exploitation](SECURITE-EXPLOITATION.md): sudo borné, wrapper de déploiement et garde-fous.
- [Sources](SOURCES.md): références externes utiles.

## Installer et travailler

- [Configuration locale](CONFIGURATION-LOCALE.md): `.env`, chemins et secrets.
- [Développement](DEVELOPPEMENT.md): clone local, validation et tests.
- [Déploiement](DEPLOIEMENT.md): stage, installation et règles de redémarrage.
- [Accès LAN](LAN-ACCESS.md): connexion depuis un autre poste de confiance.

## Exploiter

- [Opérations](OPERATIONS.md): console, sauvegardes, mises à jour, stats, échos, terminal et microsite.
- [Bot Discord](BOT-DISCORD.md): JSON publics, annonces REST optionnelles et garde-fous.
- [Disponibilité REST](OPERATIONS.md#donnees-publiques): uptime public calculé depuis l'API REST Palworld.
- [Personnalisation](CUSTOMIZATION.md): annonces, bienvenue et profil de difficulté.
- [Profil de configuration](CONFIGURATION-AUDIT.md): réglages PvE fournis.

## Données publiques

- [Snapshot public v3](SAVE-SNAPSHOT-V3.md): contrat des données joueurs, fiches, Pals et export JSON.
- [Bases publiques v1](SAVE-BASES-V1.md): contrat des bases, constructions, stockages et libellés publics.
- [Échos publics v6](EVENEMENTS-PUBLICS-V6.md): projection canonique, fragments journaliers, publication atomique et bascule progressive.
- [Plan d'enrichissement](PLAN-ENRICHISSEMENT-SAUVEGARDES.md): état du journal enrichi, terminal et limites volontaires.
- [Publication du dépôt](PUBLIC-REPOSITORY.md): quoi publier, quoi garder local.

Les données propres à l'instance réelle restent dans `.env`, `config/local/`, `runtime/` ou les fichiers ignorés sous `portal/data/`.
