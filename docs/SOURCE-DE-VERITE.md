# Source de vérité Ubuntu et GitHub

## Règle

Le dépôt Gaylémon est la source de vérité de tout code et toute configuration non secrète que nous maintenons.

Doivent être versionnés:

- tous les scripts actifs sous `/srv/storage/steam/bin`;
- les collecteurs et analyseurs exécutés depuis le projet Ubuntu;
- toutes les unités et minuteries `systemd` Palworld;
- les règles `sysctl` et modèles `sudoers`;
- les scripts Windows, watchers, synchroniseurs et outils Docker;
- les schémas, tests, fixtures fictives et exemples de variables;
- les manifestes des dépendances externes.

Ne doivent pas être versionnés:

- mots de passe, jetons, clés SSH et URLs Push privées;
- sauvegardes Palworld, bases SQLite, journaux et données joueurs;
- fichiers d'état ou copies `.bak`, `.new`, `.previous`;
- binaires Palworld et SteamCMD;
- ressources du jeu générées;
- volumes Uptime Kuma et configuration cloudflared;
- clones complets de dépendances tierces.

## Emplacements actifs

| Source Git | Emplacement Ubuntu actif |
|---|---|
| `server/bin/*` | `/srv/storage/steam/bin/*` ou `GAYLEMON_REMOTE_PROJECT_ROOT/server/bin/*` |
| `server/systemd/*` | `/etc/systemd/system/*` |
| `server/sysctl/*` | `/etc/sysctl.d/*` |
| `server/sudoers/*` | `/etc/sudoers.d/*` |
| `server/*.env.example` | modèles pour `/etc/palworld/*.env` |

Les fichiers secrets réels sous `/etc/palworld` ne sont jamais rapatriés dans Git.

La correspondance exacte ne doit pas être dupliquée dans les scripts. Elle est déclarée dans `server/deployment-manifest.json`, avec le propriétaire, le groupe, le mode, le validateur et la politique de redémarrage de chaque fichier actif. Tout nouveau fichier actif doit être ajouté à ce manifeste; la validation du dépôt échoue sinon.

## Audit de dérive

```powershell
.\scripts\auditer-source-ubuntu.ps1
```

L'audit:

1. construit le manifeste à partir des fichiers suivis localement;
2. calcule les empreintes SHA-256 distantes lorsque l'utilisateur SSH peut lire le fichier;
3. compare la taille pour les fichiers protégés;
4. compare aussi le propriétaire, le groupe et le mode Unix;
5. vérifie la révision active de PalworldSaveTools;
6. ne lit aucun secret;
7. n'utilise ni `sudo`, ni `systemctl`;
8. ne modifie aucun fichier distant.

Un rapport JSON local et ignoré peut être produit:

```powershell
.\scripts\auditer-source-ubuntu.ps1 `
  -Rapport .\runtime\validation\source-ubuntu.json
```

## PalworldSaveTools

PalworldSaveTools reste un dépôt GitHub séparé parce qu'il conserve son propre historique et plusieurs licences. Gaylémon versionne plutôt un verrou contenant le fork et la révision validée:

```text
dependencies/palworld-save-tools.lock.json
```

Après une mise à jour validée du fork, le verrou doit être actualisé dans la même contribution.

Le script de maintenance distingue les trois révisions:

- `Upstream`: dernière révision amont;
- `Fork`: dernière révision disponible dans le fork GitHub;
- `Locked` et `ActiveAfter`: révision validée sur Ubuntu et enregistrée par Gaylémon.

Il n'actualise le verrou qu'après la réussite des tests du parseur et la bascule atomique de la version Ubuntu.

## Copies de secours sur Ubuntu

Les fichiers `.bak`, `.backup-*`, `.new` et `.previous` peuvent exister temporairement sur Ubuntu pour un retour arrière. Ils ne constituent jamais la source canonique et ne doivent pas être ajoutés au dépôt.

Une ancienne copie dans `/home/.../Gaylemon/server` ne remplace pas une unité active sous `/etc/systemd/system`. L'audit compare toujours l'emplacement réellement utilisé.
