# Développement

## Préparer le projet

```powershell
git clone https://github.com/MathieuLF/gaylemon.git
Set-Location .\gaylemon
npm ci
```

Les exemples sous `portal/data` sont fictifs. Ils suffisent pour explorer le portail sans disposer d’un serveur Palworld.

## Valider

```powershell
.\scripts\upgrade-preflight.ps1 -Mode Inventory
.\scripts\verify-local.ps1 -Mode Quick
.\scripts\verify-local.ps1 -Mode Full
```

Quick exécute les tests Go, les contrats du portail et le reçu local; les migrations réelles appartiennent à l'intégration PostgreSQL. Full ajoute PostgreSQL 16 isolé, navigateur/Axe, race, deadcode, vulnérabilités, SBOM et image de release signée. Son matériel de signature n'est pas nécessaire au développement courant.

## Installation Ubuntu et contrôles quotidiens

Le setup non interactif cible Ubuntu 24.04 amd64 avec droits administratifs pour les paquets système :

```bash
bash scripts/setup-cloud.sh
python3 -B scripts/project.py check-dev
```

Les versions Go et Node sont définies dans `config/development-tools.json`. Les téléchargements vérifient leur SHA-256 avec TLS actif. Les outils du projet restent dans `runtime/.tools`, répertoire exclu de la découverte des packages Go, et les sorties Go dans `runtime/development-build`, tous ignorés. Python 3.12 minimum utilise seulement sa bibliothèque standard. PostgreSQL 16 est fourni par Ubuntu; Chromium et ses bibliothèques sont préparés une fois par le setup. Les dépendances Go et npm conservent leurs lockfiles, sans mise à jour automatique.

Le contrôle quotidien réutilise cet environnement : unités Go, vet, gofmt en lecture seule, unités Python, contrats JavaScript, comparaison des bundles et compilation des deux programmes. Il compare les empreintes de tous les fichiers suivis et l'état Git avant/après, y compris un arbre déjà modifié. Il ne reconstruit pas les bundles suivis; lancer `npm run build` explicitement après une modification frontend. Un contrôle échoué retourne un code non nul.

```bash
python3 -B scripts/project.py check-integration
python3 -B scripts/project.py check-browser
python3 -B scripts/project.py portal
python3 -B scripts/project.py start --check
python3 -B scripts/project.py start
```

Chaque intégration et démarrage prépare une base neuve, uniquement locale, puis retire sa propre instance. Sous Ubuntu, PostgreSQL fonctionne nativement, même lorsque le setup est exécuté comme root : seul le processus de base utilise le compte système postgres. Sous Windows, utiliser `python` et `--postgres docker`; l'image de test est `postgres:16.15-alpine`. Aucune URL de base réelle n'est acceptée par ce parcours. Ctrl+C arrête le backend et sa base. `/health/ready` vérifie la disponibilité; le contrôle de démarrage vérifie aussi la page hors ligne et ses actifs.

Le backend est vide de projections publiques après les migrations. Les huit joueurs fictifs sont servis par `npm run dev` sur 4179, sans serveur Palworld. Les fixtures remplacent les icônes du jeu par le favicon : elles ne prouvent pas la présence des ressources graphiques réelles.

Après le setup, utiliser le profil de développement pour les vérifications quotidiennes. Compléter avec l'intégration PostgreSQL pour les changements métier, permissions, ingestion, saisons ou migrations, et avec le navigateur pour les changements UI. Un profil léger réussi ne constitue pas une validation complète ni une certification de release.

## Validation de publication

Les commandes Quick/Full restent disponibles. Full conserve race, deadcode, govulncheck, PostgreSQL, navigateur, Gitleaks 8.30.1, Trivy 0.74.0, Syft 1.51.0, images, SBOM, Cosign et reçus. Il exige Go, Node, Python, PowerShell 7, Docker, Bash, tar et les scanners installés, ainsi que le matériel de signature correspondant à `security/cosign.pub`. Sur Linux, fournir les chemins `-CosignKey` et `-CosignPublicKey` et `COSIGN_PASSWORD`; le mot de passe DPAPI est réservé au poste Windows. Le setup quotidien n'installe pas ces scanners et n'accède pas aux clés de publication. Full canonique exige un commit propre, synchronisé avec son upstream; `-AllowDirty` ne certifie pas une release.

## Préparer un environnement distant

Installation : `bash scripts/setup-cloud.sh`. Instructions de démarrage : portail fictif avec `python3 -B scripts/project.py portal` sur 4179, ou backend avec `python3 -B scripts/project.py start`; contrôler `/health/ready` sur 8080. Le lanceur résout les outils locaux sans dépendre d'un export PATH conservé entre sessions. Pour les commandes Go/npm directes et la reconstruction volontaire des bundles, exporter `PATH="$PWD/runtime/.tools/go/bin:$PWD/runtime/.tools/node/bin:$PATH"`. Relancer le setup après modification des lockfiles ou versions. Accès réseau nécessaire aux paquets Ubuntu, Node, Go et Chromium pendant l'installation; aucun accès à une instance réelle requis. OAuth, analytique et helpers privilégiés sont désactivés dans le démarrage synthétique. Aucun secret de production ou de release n'est nécessaire.

## Dépannage

- Version Go/Node différente ou dépendances absentes : relancer le setup, puis utiliser `scripts/project.py`, qui résout les outils locaux.
- Actifs périmés : `npm run build`, examiner le diff puis relancer le contrôle; ne jamais restaurer silencieusement les sorties.
- Navigateur absent : `npx --no-install playwright install --with-deps chromium`.
- PostgreSQL natif absent : relancer le setup Ubuntu ou choisir explicitement `--postgres docker`.
- Port 8080 occupé : utiliser `start --port 8081`.
- `.env` copié mais service non configuré : Go lit l'environnement du processus; utiliser le démarrage synthétique ou exporter les variables.

## Variables et surfaces sensibles

`.env.example` inventorie les variables web, agent, collecte et intégration. Le web exige `GAYLEMON_DATABASE_URL` et `GAYLEMON_AGENT_PUBLIC_KEYS`; une URL publique HTTPS exige aussi la clé privée de réponse. L'agent exige une URL API et un fichier de clé privée; une API HTTPS exige la clé publique de réponse. Les sources sont requises selon la collecte choisie. OAuth et analytique restent facultatifs. `GAYLEMON_TEST_DATABASE_URL` appartient uniquement à une base de test isolée. Ne publier aucune valeur sensible.

Ajouter de nouvelles migrations plutôt que réécrire celles appliquées. Le démarrage applique les SQL embarqués et les migrations River. Rétention, archivage, suppression de données, clés de confiance, publication, réseau, services et sauvegardes d'une installation nécessitent une instruction explicite. Les lockfiles et bundles se changent avec leurs sources et les validations correspondantes.

`compose.production.yaml` est un manifeste d'exploitation versionné, distinct du développement synthétique. Le contrôle quotidien vérifie statiquement que ses paramètres sensibles restent externes et que ses protections sont présentes; il ne démarre pas ce manifeste. `GAYLEMON_IMAGE_REFERENCE` et `GAYLEMON_WEB_PORT` appartiennent seulement à ce parcours. Ne pas les utiliser pour tester une instance réelle sans instruction explicite.

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

La base est vide : le portail Go montre donc ses états en attente jusqu’à l’ingestion de projections signées. Pour travailler sur les écrans remplis, utiliser le parcours fictif ci-dessus. Ctrl+C arrête le processus créé et supprime uniquement le conteneur dont le script a vérifié l’identité. Les clés et journaux de cette session restent sous `runtime/local`, ignoré par Git, et ne servent qu’au développement local.

Le programme lit l’environnement du processus, **pas** un fichier `.env`. Pour une base persistante gérée séparément, fournir au minimum `GAYLEMON_DATABASE_URL`, `GAYLEMON_AGENT_PUBLIC_KEYS` au format `identifiant:cle-publique-base64`, `GAYLEMON_WEB_LISTEN` et `GAYLEMON_PUBLIC_BASE_URL`, puis lancer `go run ./cmd/gaylemon-web`. Une URL HTTPS exige aussi `GAYLEMON_RESPONSE_PRIVATE_KEY`. `go run ./cmd/gaylemon keygen --private chemin.key` génère une paire de clés.

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
