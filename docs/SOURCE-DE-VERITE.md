# Source de vérité

Git décrit les fichiers non secrets que Gaylémon maintient. Ubuntu exécute des copies installées explicitement.

## À versionner

- scripts actifs sous `server/bin/`;
- unités et minuteries `systemd`;
- wrappers privilégiés sous `server/sbin/`;
- règles `sysctl` et modèles `sudoers`;
- collecteurs, analyseurs, tests et fixtures fictives;
- scripts Windows;
- exemples de configuration;
- exemples JSON fictifs sous `portal/data/*.example.json`;
- verrous de dépendances externes.

## À garder hors Git

- mots de passe, jetons, clés SSH et URLs privées;
- sauvegardes Palworld, bases SQLite, journaux et données joueurs;
- fichiers `.bak`, `.new`, `.previous`;
- binaires Palworld et SteamCMD;
- ressources du jeu générées;
- exports publics réels sous `portal/data/public-*.json`;
- profils publics réels sous `portal/data/players/`;
- pages joueurs générées sous `portal/joueur/`;
- volumes Uptime Kuma et configuration cloudflared;
- clones complets de dépendances tierces.

## Fichiers Ubuntu actifs

| Dans Git | Sur Ubuntu |
|---|---|
| `server/bin/*` | `/srv/storage/steam/bin/*` ou `GAYLEMON_REMOTE_PROJECT_ROOT/server/bin/*` |
| `server/sbin/*` | `/usr/local/sbin/*` |
| `server/systemd/*` | `/etc/systemd/system/*` |
| `server/sysctl/*` | `/etc/sysctl.d/*` |
| `server/sudoers/*` | `/etc/sudoers.d/*` |
| `server/*.env.example` | modèles pour `/etc/palworld/*.env` |

Les vrais fichiers secrets sous `/etc/palworld` ne sont jamais copiés dans le dépôt.

La table complète vit dans `server/deployment-manifest.json`. Un nouveau fichier actif doit y être ajouté avec sa destination, ses permissions et sa politique de redémarrage.

## Fichiers publics générés

Les exports publics réels ne sont pas la source Git, même s'ils sont servis aux visiteurs. Ils sont produits depuis Ubuntu et synchronisés vers `portal/data/`.

Principaux contrats:

- métriques live et présences: `public-metrics.json`;
- sessions et statistiques: `public-stats.json`;
- snapshots joueurs: `public-save-index.json`, `public-save-snapshot.json`, `players/{slug}.json`;
- bases et constructions: `public-save-bases.json`;
- échos v6: `public-events-manifest-v6.json`, `public-events-head-v6.json`, `public-events-v6/`, `public-daily/`;
- compatibilité v5: `public-events.json`, `public-events-recent.json`, `public-events-index.json`, `public-events-page-*.json`;
- disponibilité: `public-uptime.json`, `public-uptime-history.json`, `public-availability.json`.

Git versionne seulement les exemples `*.example.json`. Quand un contrat change, mettre à jour le producteur, la synchronisation Windows, le microsite, les tests et l'exemple correspondant.

## Routes du microsite

Les routes canoniques publiques sont `/`, `/terminal`, `/resume`, `/classements`, `/carte` et `/github`.

`docker/microsite/default.conf` garde les pages et les JSON v5 dynamiques en `no-store`, revalide le pointeur actif et le manifeste de compatibilité v6 avec ETag et sert les manifestes, têtes et fragments versionnés en `immutable`. Toute modification à cette règle doit conserver le blocage de `/data/` hors fichiers publics explicitement autorisés.

## Audit

```powershell
.\scripts\auditer-source-ubuntu.ps1
```

L'audit compare les fichiers suivis avec les fichiers actifs sur Ubuntu. Il vérifie les empreintes, tailles, propriétaires, groupes, modes et la révision PalworldSaveTools quand c'est possible.

Il ne lit pas les secrets, n'utilise pas `sudo`, n'appelle pas `systemctl` et ne modifie rien.

Pour garder un rapport local:

```powershell
.\scripts\auditer-source-ubuntu.ps1 `
  -Rapport .\runtime\validation\source-ubuntu.json
```

`runtime/` est ignoré par Git.

## PalworldSaveTools

PalworldSaveTools reste dans son propre dépôt. Gaylémon versionne seulement le fork et la révision validée dans:

```text
dependencies/palworld-save-tools.lock.json
```

Après une mise à jour validée, mettre ce verrou à jour dans la même contribution.
