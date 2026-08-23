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

cloudflared peut exister sur la même machine ou dans la même infra, mais Gaylémon ne le gère pas. La disponibilité Palworld est calculée localement à partir de l'API REST déjà utilisée par la console et le microsite.

Le dépôt ne doit pas:

- ajouter cloudflared au Compose;
- monter un jeton Cloudflare;
- recréer un conteneur partagé;
- exposer l'API REST Palworld sur Internet.

## Routes publiques

Le microsite reste statique, mais sert six routes humaines:

- `/`: tableau de bord avec métriques, specs publiques et fiches joueurs;
- `/terminal`: terminal plein écran du journal des échos;
- `/resume`: résumé quotidien précalculé par génération v6, avec repli v5 temporaire;
- `/classements`: page dédiée aux palmarès des joueurs;
- `/carte`: carte dédiée de Palpagos avec positions et bases publiques;
- `/github`: page technique publique du dépôt.

Les variantes capitalisées `/Terminal`, `/Resume`, `/Classements`, `/Carte` et `/Github` redirigent vers les routes canoniques quand Nginx les reçoit. Les anciens liens de section `/#classements`, `/#carte`, `/#evenements` et `/#terminal` sont repris côté navigateur vers les pages dédiées. Les liens internes doivent pointer vers `/terminal`, `/resume`, `/classements`, `/carte` et `/github`.

Les pages HTML et les contrats v5 dynamiques sont servis en `no-store`. Le pointeur actif et le manifeste v6 de compatibilité sont revalidés avec ETag. Les assets versionnés, manifestes et têtes de génération, fragments journaliers et résumés sont servis en cache long avec `immutable`.

## Données publiques

Les visiteurs lisent seulement des fichiers `public-*` sous `portal/data/`. Ces fichiers sont filtrés avant publication.

Contrats principaux:

- `public-metrics.json`: état live, joueurs connectés, liste affichable, `onlineSinceAt`, FPS, camps et uptime;
- `public-stats.json`: sessions, temps de jeu, agrégats et derniers états publiables;
- `public-save-index.json`: index léger des joueurs, guildes et progression;
- `players/{slug}.json`: profil public détaillé d'un joueur, chargé à l'ouverture de sa fiche;
- `public-save-snapshot.json`: projection complète publique v3;
- `public-save-bases.json`: bases, constructions, travailleurs, stockage agrégé et productions;
- `public-save-diagnostics.json`: état public filtré de la dernière analyse de sauvegarde;
- `/api/public/events/v1`: historique, pagination, recherche et facettes servis depuis PostgreSQL;
- `public-events-recent.json`: petite fenêtre de continuité, conservée sans historique de versions;
- `public-uptime.json`, `public-uptime-history.json`, `public-availability.json`: disponibilité et historique calculés depuis les sondes REST Palworld.

`public-events-sync-state.json` peut exister localement dans `portal/data/`; il est ignoré, refusé par Nginx et sert seulement à retenir la dernière révision distante déjà synchronisée. Le détail du contrat et de sa publication atomique est décrit dans [Échos publics v6](EVENEMENTS-PUBLICS-V6.md).

Les contrats de sauvegarde partagent un `generationId`. La synchronisation
prépare snapshot, bases, diagnostic, fiches et pages joueurs avant de remplacer
l'index actif en dernier. Le portail conserve la génération déjà rendue si un
artefact ne correspond pas à cet index; il ne compose jamais deux captures.

La projection canonique des échos est matérialisée dans SQLite sur Ubuntu. Le collecteur valide le checkpoint complet en flux, évite de remettre en file une révision déjà publiée et l'envoie compressé. PostgreSQL compare cette révision dans une table temporaire, ne réécrit que les échos modifiés et retire transactionnellement ceux qui ne sont plus présents. L'export complet n'est jamais conservé comme document public sur la VPS.

## Travaux d'arrière-plan du service web

Le service Go exécute ses travaux internes dans une file persistante PostgreSQL. Les tables et leur historique de migrations résident dans le schéma opérationnel `gaylemon_ops`; le schéma public n'est pas utilisé pour cette orchestration.

L'entretien quotidien de la base est exécuté par un seul worker, avec trois tentatives au maximum, un délai de cinq minutes et une clé d'unicité par journée. Le calendrier est conservé dans PostgreSQL, un rattrapage est demandé au démarrage et plusieurs instances du service peuvent se coordonner sans lancer le même travail en parallèle. Le service applique puis valide les migrations de la file avant d'accepter le trafic et laisse le travail actif se terminer pendant un arrêt gracieux.

Cette file ne remplace ni la file SQLite de publication sur Ubuntu, qui doit survivre aux coupures réseau, ni les commandes de contrôle signées. Ces chemins gardent leurs frontières de sécurité et leurs garanties propres.

Ne pas publier:

- sauvegardes brutes;
- adresses IP;
- identifiants Steam, Unreal, conteneurs ou chemins internes;
- secrets, jetons, mots de passe;
- détails privés des coffres ou profils non prévus par les contrats.

Les noms affichés publiquement doivent venir d'un nom de joueur prévu pour l'affichage. Un identifiant technique comme `accountName`, `playerId`, `userId`, Steam ID ou Unreal GUID ne doit jamais servir de nom de secours dans un export public.

Le navigateur peut exporter un JSON d'analyse depuis le bouton d'en-tête d'une fiche joueur. Cet export ne crée pas une nouvelle source de données: il regroupe seulement les champs publics chargés pour ce joueur, son activité, sa progression, son inventaire, ses Pals, ses bases, ses constructions et son stockage. Les blocs exportés gardent des clés déterministes et des sommaires pour faciliter l'audit.

## Disponibilité

Si Docker Desktop ou Windows tombe, le microsite et le tunnel API local tombent aussi. Palworld continue de tourner sur Ubuntu.

Au retour du poste, les scripts resynchronisent les données publiques et l'audit permet de comparer Git avec les fichiers actifs.
