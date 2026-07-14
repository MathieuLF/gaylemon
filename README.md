# Gaylémon

[![Validation](https://github.com/MathieuLF/Gaylemon/actions/workflows/validation.yml/badge.svg)](https://github.com/MathieuLF/Gaylemon/actions/workflows/validation.yml)
[![Licence MIT](https://img.shields.io/badge/licence-MIT-2f855a.svg)](LICENSE)

> Projet communautaire francophone exploité sur une instance Palworld réelle. Les garde-fous de production priment sur la commodité.

Gaylémon regroupe les outils d'exploitation d'un serveur dédié Palworld, un collecteur de statistiques et un microsite public consacré à la progression des joueurs.

Le projet vise une installation simple à maintenir:

- Palworld tourne nativement sur Ubuntu avec SteamCMD et `systemd`;
- la console PowerShell administre le serveur par SSH depuis Windows;
- les sauvegardes sont analysées en lecture seule;
- le microsite statique est servi par un seul conteneur Nginx;
- les données d'exploitation et les secrets restent hors Git;
- Uptime Kuma et cloudflared sont des intégrations externes, jamais des services possédés par ce dépôt.

## Architecture

```text
Ubuntu / Palworld
  systemd + SteamCMD + sauvegardes
             |
             | SSH, REST locale et JSON publics filtrés
             v
Poste Windows / ce répertoire
  Console Ops + synchronisation + Docker Desktop
             |
             v
  Nginx : microsite statique sur 127.0.0.1
             |
             | origine consommée par un tunnel externe
             v
  Cloudflare / visiteurs

Uptime Kuma externe ---- API de page publique ----> export JSON du microsite
cloudflared externe ---- tunnel uniquement --------> origine Nginx locale
```

Le fichier [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) détaille les responsabilités et les frontières de sécurité.

## Source de vérité Ubuntu

Tous les scripts, collecteurs, watchers, unités `systemd`, règles `sysctl` et modèles `sudoers` maintenus sur Ubuntu sont représentés sous `server/`.

Le fichier `server/deployment-manifest.json` associe chaque source à son emplacement actif, son propriétaire, son mode et sa politique de redémarrage. L'audit et le déploiement utilisent donc exactement la même définition.

Vérifier une instance active sans la modifier:

```powershell
.\scripts\auditer-source-ubuntu.ps1
```

PalworldSaveTools conserve son propre dépôt GitHub et ses licences. Gaylémon verrouille la révision validée dans `dependencies/palworld-save-tools.lock.json`; le clone lui-même reste sous `vendor/` et hors de ce dépôt.

## Prérequis

Pour l'exploitation complète depuis Windows:

- Windows PowerShell 5.1 ou PowerShell 7;
- OpenSSH avec une clé configurée pour le serveur Ubuntu;
- Docker Desktop avec Docker Compose;
- Python 3 pour les tests des collecteurs;
- Node.js pour la validation syntaxique du microsite;
- Git.

Le serveur Ubuntu doit disposer de SteamCMD, des unités `systemd` et des scripts présents sous `server/`. Leur installation est volontairement distincte de l'amorçage local.

## Démarrage rapide

Depuis la racine du projet:

```powershell
.\scripts\initialiser-projet.ps1
.\scripts\valider-depot.ps1
.\scripts\diagnostiquer-integrations.ps1
```

L'initialisation:

- crée `.env` depuis `.env.example` seulement s'il n'existe pas;
- crée les répertoires locaux ignorés;
- installe des JSON de démonstration uniquement lorsque les données réelles sont absentes;
- ne contacte pas Ubuntu, Docker, Uptime Kuma ou Cloudflare.

Configurer ensuite `.env`, puis lancer la console:

```powershell
.\Gaylemon Ops Console.ps1
```

Le lanceur double-clic reste:

```text
Gaylemon Ops Console.cmd
```

Le fichier `.cmd` ne contient aucune logique métier. Il ouvre le vrai script PowerShell avec un encodage et une politique d'exécution compatibles avec Windows.

## Microsite

Le Compose du projet ne contient qu'un service:

```powershell
docker compose up -d microsite
```

Ou utiliser le lanceur qui démarre aussi la synchronisation locale:

```powershell
.\scripts\open-microsite.ps1
```

Le port local vient de `GAYLEMON_MICROSITE_PORT`. Par défaut, l'origine est liée uniquement à `127.0.0.1`.

Uptime Kuma et cloudflared ne figurent pas dans [compose.yaml](compose.yaml). Le projet peut lire la page publique Kuma et constater la présence d'un conteneur cloudflared, mais il ne contrôle jamais leur cycle de vie.

## Configuration locale

Les valeurs propres à une installation se trouvent dans `.env`, ignoré par Git. Le modèle public [.env.example](.env.example) documente toutes les variables prises en charge.

Les fichiers locaux additionnels peuvent rester sous `config/local/`, lui aussi ignoré. Les clés SSH privées demeurent dans `~/.ssh`; elles ne doivent jamais être copiées dans le projet.

Consulter [docs/CONFIGURATION-LOCALE.md](docs/CONFIGURATION-LOCALE.md) pour les variables et les emplacements de secrets.

## Commandes principales

```powershell
# Console interactive
.\Gaylemon Ops Console.ps1

# Validation locale, sans modifier les services
.\scripts\valider-depot.ps1

# Diagnostic en lecture seule
.\scripts\diagnostiquer-integrations.ps1

# Démarrage des auxiliaires Windows
.\scripts\start-local-services.ps1

# Arrêt des seuls services possédés par Gaylémon
.\scripts\stop-local-services.ps1

# Aperçu d'une livraison Ubuntu, sans téléversement
.\scripts\deployer-ubuntu.ps1

# Comparer les sources Git aux fichiers Ubuntu actifs
.\scripts\auditer-source-ubuntu.ps1

# Bilan général en lecture seule: dépôt, Ubuntu, Docker et intégrations
.\scripts\auditer-maintenance.ps1

# Valider puis mettre la livraison en scène sous /tmp sur Ubuntu
.\scripts\deployer-ubuntu.ps1 -Stage

# Installer avec backup, sans redémarrer de service par défaut
.\scripts\deployer-ubuntu.ps1 -Install
```

L'ancien paramètre `-Apply` reste un alias de `-Stage`: il ne touche jamais aux fichiers actifs. `-Install` demande une confirmation, effectue une seule élévation `sudo`, valide de nouveau les sources, sauvegarde chaque fichier remplacé et ne redémarre aucun service implicitement. `palworld.service` possède un garde-fou supplémentaire et ne peut jamais être redémarré par défaut.

## Arborescence

```text
.github/             modèles GitHub et validation continue
config/exemples/     exemples de configuration publiables
config/local/        notes de l'instance locale, ignorées
docker/              configuration Nginx du microsite
docs/                exploitation, contrats et architecture
portal/              microsite statique
scripts/             console et outils Windows
server/              scripts, unités systemd et tests Ubuntu
runtime/             rapports, archives et état local ignorés
vendor/              dépendances locales ignorées
```

## Données et confidentialité

Les fichiers réels sous `portal/data/`, les pages joueurs générées, les ressources du jeu, les historiques et les sauvegardes ne sont pas versionnés. Seuls des exemples fictifs `*.example.json` sont publiés.

Les projections publiques retirent notamment:

- les adresses IP;
- les identifiants Steam, comptes, conteneurs et acteurs Unreal;
- les chemins internes et erreurs techniques détaillées;
- les mots de passe et jetons;
- le contenu privé des coffres individuels lorsque sa publication n'est pas prévue par le contrat.

Lire [docs/PUBLIC-REPOSITORY.md](docs/PUBLIC-REPOSITORY.md) avant toute première publication.

## Développement et validation

La commande de référence est:

```powershell
.\scripts\valider-depot.ps1
```

Elle vérifie les scripts PowerShell et Bash, les JSON d'exemple, le JavaScript, les tests Python, les exclusions Git et le fichier Compose. Elle ne démarre ni n'arrête aucun service.

Les contributions doivent conserver les garde-fous de production et les contrats de confidentialité. Voir [CONTRIBUTING.md](CONTRIBUTING.md).

## Documentation

- [Sommaire complet](docs/README.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Configuration locale](docs/CONFIGURATION-LOCALE.md)
- [Développement](docs/DEVELOPPEMENT.md)
- [Déploiement prudent](docs/DEPLOIEMENT.md)
- [Source de vérité Ubuntu et GitHub](docs/SOURCE-DE-VERITE.md)
- [Exploitation Palworld](docs/OPERATIONS.md)
- [Accès LAN](docs/LAN-ACCESS.md)
- [Uptime Kuma externe](docs/UPTIME-KUMA.md)
- [Personnalisation](docs/CUSTOMIZATION.md)
- [Contrat des sauvegardes v3](docs/SAVE-SNAPSHOT-V3.md)
- [Contrat des bases v1](docs/SAVE-BASES-V1.md)
- [Profil de configuration fourni](docs/CONFIGURATION-AUDIT.md)
- [Sources et références](docs/SOURCES.md)
- [Publication du dépôt](docs/PUBLIC-REPOSITORY.md)

## Licence et marques

Le code propre à Gaylémon est publié sous licence MIT. Les polices intégrées utilisent la SIL Open Font License 1.1. PalworldSaveTools reste une dépendance séparée avec ses propres licences.

Palworld et ses ressources appartiennent à leurs ayants droit. Ce projet communautaire n'est ni affilié ni approuvé par Pocketpair. Voir [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
