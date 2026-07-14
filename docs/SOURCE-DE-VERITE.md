# Source de vérité

Git décrit les fichiers non secrets que Gaylémon maintient. Ubuntu exécute des copies installées explicitement.

## À versionner

- scripts actifs sous `server/bin/`;
- unités et minuteries `systemd`;
- règles `sysctl` et modèles `sudoers`;
- collecteurs, analyseurs, tests et fixtures fictives;
- scripts Windows;
- exemples de configuration;
- verrous de dépendances externes.

## À garder hors Git

- mots de passe, jetons, clés SSH et URLs privées;
- sauvegardes Palworld, bases SQLite, journaux et données joueurs;
- fichiers `.bak`, `.new`, `.previous`;
- binaires Palworld et SteamCMD;
- ressources du jeu générées;
- volumes Uptime Kuma et configuration cloudflared;
- clones complets de dépendances tierces.

## Fichiers Ubuntu actifs

| Dans Git | Sur Ubuntu |
|---|---|
| `server/bin/*` | `/srv/storage/steam/bin/*` ou `GAYLEMON_REMOTE_PROJECT_ROOT/server/bin/*` |
| `server/systemd/*` | `/etc/systemd/system/*` |
| `server/sysctl/*` | `/etc/sysctl.d/*` |
| `server/sudoers/*` | `/etc/sudoers.d/*` |
| `server/*.env.example` | modèles pour `/etc/palworld/*.env` |

Les vrais fichiers secrets sous `/etc/palworld` ne sont jamais copiés dans le dépôt.

La table complète vit dans `server/deployment-manifest.json`. Un nouveau fichier actif doit y être ajouté avec sa destination, ses permissions et sa politique de redémarrage.

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
