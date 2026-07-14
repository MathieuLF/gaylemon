# Architecture de Gaylémon

## Principes

Gaylémon sépare l'exécution du jeu, l'administration, la projection publique et les services d'infrastructure partagés.

Cette séparation poursuit quatre objectifs:

- ne pas exposer l'administration sur Internet;
- ne pas faire dépendre Palworld de Docker Desktop;
- ne publier que des projections filtrées;
- ne jamais prendre possession d'un service externe partagé.

## Composants possédés par le projet

### Ubuntu

- serveur dédié Palworld installé par SteamCMD;
- unités et minuteries `systemd` sous `server/systemd/`;
- scripts d'exploitation sous `server/bin/`;
- collecte REST locale;
- analyse en lecture seule des sauvegardes;
- sauvegardes et historiques locaux.

### Windows

- console PowerShell;
- tunnel SSH vers l'API REST;
- synchronisation des JSON publics;
- audit de reprise après une interruption;
- conteneur Nginx du microsite;
- tâches planifiées propres à Gaylémon.

## Intégrations externes

### Uptime Kuma

Uptime Kuma peut surveiller plusieurs projets. Gaylémon:

- pousse l'état Palworld vers une URL configurée sur Ubuntu;
- lit les API publiques d'une page de statut pour construire `public-uptime.json`;
- n'accède pas à la base Kuma;
- ne crée, ne modifie et ne supprime aucun moniteur depuis le Compose.

### cloudflared

Le tunnel Cloudflare peut publier plusieurs origines. Gaylémon fournit seulement une origine Nginx liée à `127.0.0.1`.

Le projet ne doit pas:

- ajouter cloudflared à son Compose;
- monter la configuration ou le jeton du tunnel;
- arrêter ou recréer le conteneur partagé;
- modifier les routes d'autres sites.

## Flux de données

1. Palworld écrit ses sauvegardes et expose une API REST locale.
2. Les collecteurs Ubuntu produisent des données privées et des projections publiques.
3. Windows récupère les projections par SSH.
4. Les scripts Windows appliquent une seconde filtration avant d'écrire sous `portal/data/`.
5. Nginx sert le microsite et ses JSON publics.
6. Le tunnel externe relaie l'origine locale vers le domaine public.

## Frontières de sécurité

- `8211/UDP`: trafic du jeu pouvant être exposé au routeur;
- `8212/TCP`: API REST non exposée, consommée localement ou par tunnel SSH;
- SSH: administration LAN par clé;
- `portal/data/public-*`: données conçues pour être publiques;
- `runtime/`, sauvegardes et fichiers privés: jamais servis ni versionnés;
- secrets Cloudflare/Kuma: gérés par leur infrastructure, pas par le microsite.

## Disponibilité

La chute de Docker Desktop ou du poste Windows rend le microsite indisponible, mais n'arrête pas Palworld. Au retour du poste, l'audit de reprise compare l'état distant et l'état local, puis resynchronise les données manquantes.

Une page de maintenance Cloudflare peut masquer une panne d'origine, mais elle appartient à l'infrastructure Cloudflare externe.
