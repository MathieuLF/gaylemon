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
        |     /, /terminal, /resume, /classements, /carte, /github, /data/public-*.json
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
- lecture des sauvegardes en mode projection, jamais comme source publique brute;
- exports runtime filtrés sous le projet Gaylémon Ubuntu.

Sur Windows:

- console PowerShell;
- synchronisation des JSON publics;
- validation et audit;
- conteneur Nginx du microsite;
- conteneur SSH du tunnel API Palworld local;
- watcher des métriques rapides, des stats, des échos et des exports publics. Les échos ont une voie prioritaire distincte, cadencée aux 20 secondes par défaut.

## Ce qui reste externe

Uptime Kuma et cloudflared peuvent exister sur la même machine ou dans la même infra, mais Gaylémon ne les gère pas.

Le dépôt ne doit pas:

- ajouter cloudflared au Compose;
- monter un jeton Cloudflare ou une base Kuma;
- recréer un conteneur partagé;
- exposer l'API REST Palworld sur Internet.

## Routes publiques

Le microsite reste statique, mais sert quatre routes humaines:

- `/`: tableau de bord public;
- `/`: tableau de bord avec métriques, specs publiques et fiches joueurs;
- `/terminal`: terminal plein écran du journal des échos;
- `/resume`: résumé quotidien calculé depuis les échos paginés et l'index public des joueurs;
- `/classements`: page dédiée aux palmarès des joueurs;
- `/carte`: carte dédiée de Palpagos avec positions et bases publiques;
- `/github`: page technique publique du dépôt.

Les variantes capitalisées `/Terminal`, `/Resume`, `/Classements`, `/Carte` et `/Github` redirigent vers les routes canoniques quand Nginx les reçoit. Les anciens liens de section `/#classements`, `/#carte`, `/#evenements` et `/#terminal` sont repris côté navigateur vers les pages dédiées. Les liens internes doivent pointer vers `/terminal`, `/resume`, `/classements`, `/carte` et `/github`.

Les fichiers HTML et JSON dynamiques sont servis en `no-store`. Les assets versionnés sous `assets/` et les polices sont servis en cache long avec `immutable`.

## Données publiques

Les visiteurs lisent seulement des fichiers `public-*` sous `portal/data/`. Ces fichiers sont filtrés avant publication.

Contrats principaux:

- `public-metrics.json`: état live, joueurs connectés, liste affichable, `onlineSinceAt`, FPS, camps et uptime;
- `public-stats.json`: sessions, temps de jeu, agrégats et derniers états publiables;
- `public-save-index.json`: index léger des joueurs, guildes et progression;
- `players/{slug}.json`: profil public détaillé d'un joueur, chargé à l'ouverture de sa fiche;
- `public-save-snapshot.json`: projection complète publique v3;
- `public-save-bases.json`: bases, constructions, travailleurs, stockage agrégé et productions;
- `public-events.json`: historique complet des échos;
- `public-events-recent.json`: fenêtre chaude de 2 000 échos relue par le tableau de bord et fusionnée avec l'historique complet au besoin;
- `public-events-index.json` et `public-events-page-*.json`: pagination du terminal et compilation du résumé quotidien;
- `public-uptime.json`, `public-uptime-history.json`, `public-availability.json`: état Uptime Kuma filtré.

`public-events-sync-state.json` peut exister localement dans `portal/data/`; il est ignoré et sert seulement à retenir la dernière révision distante déjà synchronisée.

Ne pas publier:

- sauvegardes brutes;
- adresses IP;
- identifiants Steam, Unreal, conteneurs ou chemins internes;
- secrets, jetons, mots de passe;
- détails privés des coffres ou profils non prévus par les contrats.

Les noms affichés publiquement doivent venir d'un nom de joueur prévu pour l'affichage. Un identifiant technique comme `accountName`, `playerId`, `userId`, Steam ID ou Unreal GUID ne doit jamais servir de nom de secours dans un export public.

Le navigateur peut exporter un JSON d'analyse depuis une fiche joueur. Cet export ne crée pas une nouvelle source de données: il regroupe seulement les champs publics déjà chargés pour ce joueur, ses Pals, ses bases, ses constructions et son stockage.

## Disponibilité

Si Docker Desktop ou Windows tombe, le microsite et le tunnel API local tombent aussi. Palworld continue de tourner sur Ubuntu.

Au retour du poste, les scripts resynchronisent les données publiques et l'audit permet de comparer Git avec les fichiers actifs.
