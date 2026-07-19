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
- `public-events-manifest-v6.json`: génération active, curseurs, comptes, provenance et hachages;
- `public-events-head-v6.json`: petit pointeur actif revalidé par ETag vers le manifeste et la tête immuables;
- `public-events-v6/{génération}/{jour}.json`: fragments journaliers immuables du journal public;
- `public-daily/{génération}/{jour}.json`: résumés quotidiens précalculés;
- `public-events.json`, `public-events-recent.json`, `public-events-index.json` et `public-events-page-*.json`: contrats v5 conservés durant la transition;
- `public-uptime.json`, `public-uptime-history.json`, `public-availability.json`: état Uptime Kuma filtré.

`public-events-sync-state.json` peut exister localement dans `portal/data/`; il est ignoré, refusé par Nginx et sert seulement à retenir la dernière révision distante déjà synchronisée. Le détail du contrat et de sa publication atomique est décrit dans [Échos publics v6](EVENEMENTS-PUBLICS-V6.md).

Les contrats de sauvegarde partagent un `generationId`. La synchronisation
prépare snapshot, bases, diagnostic, fiches et pages joueurs avant de remplacer
l'index actif en dernier. Le portail conserve la génération déjà rendue si un
artefact ne correspond pas à cet index; il ne compose jamais deux captures.

La projection canonique des échos est matérialisée dans SQLite. Le collecteur met à jour sa queue récente sans réconcilier tout l'historique brut et publie la borne ainsi que les révisions couvertes par cette queue. Le poste Windows la remplace comme un bloc canonique, ce qui prend en charge les ajouts, retraits et regroupements récents sans reproduire les règles métier. L'export complet v5 est un checkpoint froid produit au plus toutes les 15 minutes ou sur demande. Une correction ancienne exige une reprojection explicite et conserve jusque-là la génération publique précédente.

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
