# Développement

## Préparer le projet

```powershell
git clone https://github.com/MathieuLF/gaylemon.git
Set-Location .\gaylemon
npm ci
```

Les exemples sous `portal/data` sont fictifs. Les données réelles, secrets, domaines, chemins et fichiers d’exploitation restent hors du dépôt.

## Valider

```powershell
.\scripts\upgrade-preflight.ps1 -Mode Inventory
.\scripts\verify-local.ps1 -Mode Quick
.\scripts\verify-local.ps1 -Mode Full
```

Quick exécute les tests Go, le contrat du portail, la frontière publique et le reçu local. Full ajoute PostgreSQL 16 isolé, navigateur/Axe, race, deadcode, vulnérabilités, SBOM et image signée.

## Explorer le portail

```powershell
npm run dev
```

Ouvrir `http://127.0.0.1:4179`, puis une fiche, sa collection, la carte, les classements et `/resume?jour=2026-09-05`. Les huit joueurs et leurs données sont fictifs. Le terminal fournit de vraies pages de résultats via une simulation de l’API publique. Une autre date, comme le 4 septembre, permet de vérifier l’état vide. Ce serveur lié à la boucle locale sert uniquement au développement et aux tests; il ne remplace pas Go en production.

## Exécuter Go avec PostgreSQL

Prérequis : Go 1.27, PowerShell 7 et Docker. Depuis le dépôt :

```powershell
.\scripts\start-local.ps1
# Contrôle automatique du démarrage puis arrêt :
.\scripts\start-local.ps1 -Port 8081 -Check
```

Le script génère deux paires Ed25519 dédiées à la session, démarre PostgreSQL 16 sur un port de boucle locale aléatoire, exporte explicitement les variables nécessaires et lance Go sur le port demandé. Les migrations du produit sont appliquées au démarrage. OAuth et l’analytique sont désactivés. Aucune commande n’est envoyée à un agent réel.

La base est vide : le portail Go montre donc ses états en attente jusqu’à l’ingestion de projections signées. Pour travailler sur les écrans remplis, utiliser le parcours fictif ci-dessus. Ctrl+C arrête le processus créé et supprime uniquement le conteneur dont le script a vérifié l’identité. Les clés et journaux de cette session restent sous `runtime/local`, ignoré par Git. Ne pas réutiliser ces clés dans une instance réelle.

Le programme lit l’environnement du processus, **pas** un fichier `.env`. Pour une base persistante gérée séparément, fournir au minimum `GAYLEMON_DATABASE_URL`, `GAYLEMON_AGENT_PUBLIC_KEYS` au format `identifiant:cle-publique-base64`, `GAYLEMON_WEB_LISTEN` et `GAYLEMON_PUBLIC_BASE_URL`, puis lancer `go run ./cmd/gaylemon-web`. Une URL HTTPS exige aussi `GAYLEMON_RESPONSE_PRIVATE_KEY`. `go run ./cmd/gaylemon keygen --private chemin.key` génère une paire; les mécanismes privés de l’instance restent hors du dépôt.

## Modifier le frontend

Les sources se trouvent sous `portal/src`. `shared` porte les formats, couleurs, requêtes et restaurations de focus; `map` possède les interactions de la carte; `leaderboards` les définitions et le rendu; `players`, `terminal` et `daily` accueillent les premières extractions de leurs responsabilités. `app.js` conserve l’orchestration et les parties encore couplées. L’extraction reste progressive.

Les styles sont répartis entre base, navigation, fiches, carte, résumé, classements et terminal. L’ordre des imports dans `portal/src/styles.css` fait partie de la cascade. Modifier les règles de leur composant plutôt qu’ajouter une nouvelle correction en fin de feuille.

```powershell
npm run build
npm run build:check
npm test
npm run test:browser
```

Le build regroupe et compresse les modules vers `portal/assets/app.js` et `portal/assets/styles.css`. Ces deux fichiers sont suivis pour permettre un démarrage Go sans Node. Toute modification des sources doit inclure les actifs régénérés; la CI refuse les divergences. Les tests de contrats inspectent les sources lisibles, tandis que les scénarios navigateur exécutent les actifs livrés. Go calcule toujours leurs noms hachés et les publie dans `/assets-manifest.json`; relancer Go après une reconstruction des actifs.

Les scénarios couvrent trois formats, les données remplies, le focus après sondage, les onglets, les progressions, les filtres au clavier, 320 px et le rechargement hors ligne. Les tests du service worker simulent aussi les erreurs de stockage, les budgets, les saisons et les changements de release. Une lecture manuelle avec lecteur d’écran reste complémentaire aux contrôles automatiques.

## Changer un contrat public

Adapter ensemble le modèle Go, la projection, l’exemple JSON, le portail, les tests et la documentation. Une génération partielle ne doit jamais devenir active. Les champs inconnus restent absents ou `null`; aucune relation ne doit être inventée.

## Contrat de disponibilité

`public-uptime.json` décrit le dernier contrôle direct de l’API Palworld. `status`, `statusCode`, `lastProbeAt`, `beats` et la durée depuis le démarrage restent des observations immédiates. `monitors[].uptime24h`, `summary.uptime24hAverage`, `summary.uptimeLast24h` et `summary.unavailableSecondsLast24h` restent présents mais valent `null` : cette projection ne calcule pas une fenêtre historique complète. Les consommateurs doivent afficher une valeur indisponible, sans convertir `null` en zéro. Un futur calcul historique devra documenter sa fenêtre, sa fréquence d’échantillonnage et le traitement des périodes sans observation.
