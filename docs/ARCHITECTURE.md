# Architecture

Gaylémon sépare trois choses: le jeu, les outils d'exploitation et le site public.

```text
Ubuntu
  Palworld, systemd, sauvegardes, collecteurs
        |
        | SSH et JSON filtrés
        v
Windows
  console, synchronisation, Docker Desktop
        |
        +--> Nginx local
        |     microsite statique sur 127.0.0.1
        |
        +--> Tunnel SSH local
              API REST Palworld sur 127.0.0.1
        |
        v
Tunnel externe / visiteurs
```

## Ce que Gaylémon possède

Sur Ubuntu:

- scripts sous `server/bin/`;
- unités et minuteries sous `server/systemd/`;
- collecteurs de métriques et d'événements;
- lecture des sauvegardes en mode projection, jamais comme source publique brute.

Sur Windows:

- console PowerShell;
- synchronisation des JSON publics;
- validation et audit;
- conteneur Nginx du microsite;
- conteneur SSH du tunnel API Palworld local.

## Ce qui reste externe

Uptime Kuma et cloudflared peuvent exister sur la même machine ou dans la même infra, mais Gaylémon ne les gère pas.

Le dépôt ne doit pas:

- ajouter cloudflared au Compose;
- monter un jeton Cloudflare ou une base Kuma;
- recréer un conteneur partagé;
- exposer l'API REST Palworld sur Internet.

## Données publiques

Les visiteurs lisent seulement des fichiers `public-*` sous `portal/data/`. Ces fichiers sont filtrés avant publication.

Ne pas publier:

- sauvegardes brutes;
- adresses IP;
- identifiants Steam, Unreal, conteneurs ou chemins internes;
- secrets, jetons, mots de passe;
- détails privés des coffres ou profils non prévus par les contrats.

## Disponibilité

Si Docker Desktop ou Windows tombe, le microsite et le tunnel API local tombent aussi. Palworld continue de tourner sur Ubuntu.

Au retour du poste, les scripts resynchronisent les données publiques et l'audit permet de comparer Git avec les fichiers actifs.
