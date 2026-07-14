# Profil Palworld fourni

Ce document résume le profil PvE généré par `server/bin/palworld-configure-balanced.sh`. Il ne contient aucun secret et ne remplace pas une lecture de la configuration active sur une autre installation.

Référence officielle:

```text
https://docs.palworldgame.com/settings-and-operation/configuration/
```

## Résumé

Le profil fourni est adapté à un serveur privé de 8 à 12 joueurs:

- mot de passe joueur et mot de passe admin définis hors documentation;
- PvP désactivé;
- mods client refusés;
- RCON désactivé;
- REST API active, mais gardée locale;
- backups Palworld internes activés;
- liste des joueurs visible;
- difficulté légèrement plus exigeante que le défaut, sans devenir punitive.

Aucun changement urgent n'est requis.

## Principaux écarts au défaut

| Paramètre | Défaut | Profil | Intention |
|---|---:|---:|---|
| `ServerPlayerMaxNum` | `32` | `12` | groupe privé |
| `bAllowClientMod` | `True` | `False` | éviter les clients moddés |
| `RESTAPIEnabled` | `False` | `True` | annonces et monitoring |
| `bShowPlayerList` | `False` | `True` | confort joueurs |
| `BaseCampWorkerMaxNum` | `15` | `18` | bases plus vivantes |
| `BaseCampMaxNumInGuild` | `4` | `5` | marge pour le groupe |
| `PalCaptureRate` | `1.0` | `0.95` | captures un peu plus exigeantes |
| `CollectionDropRate` | `1.0` | `1.1` | collecte moins lente |
| `DeathPenalty` | variable | `Item` | compromis challenge/plaisir |
| `PalEggDefaultHatchingTime` | `1.0` | `0.75` | incubation moins longue |
| `BuildObjectDeteriorationDamageRate` | `1.0` | `0.4` | bases moins pénibles à maintenir |
| `ChatPostLimitPerMinute` | `30` | `20` | anti-spam léger |

## À discuter avant changement

Ces choix dépendent du groupe:

- `CrossplayPlatforms`: limiter à Steam seulement si tout le monde joue sur Steam.
- `BaseCampMaxNum`: réduire si les bases deviennent trop nombreuses.
- `MaxBuildingLimitNum`: garder illimité tant que les performances tiennent.
- `bEnableBuildingPlayerUIdDisplay`: utile pour modérer, moins immersif.
- `bEnableVoiceChat`: inutile si le groupe reste sur Discord.

## À garder

- `RCONEnabled=False`: l'API locale suffit.
- `RESTAPIEnabled=True`: utile, tant que le pare-feu bloque l'accès entrant.
- `PublicIP=""`: pas nécessaire avec DNS et port forward.
- `bAutoResetGuildNoOnlinePlayers=False`: évite de supprimer des bases pendant les absences.

## Modifier proprement

1. Faire un backup.
2. Modifier `server/bin/palworld-configure-balanced.sh`.
3. Déployer sur Ubuntu.
4. Régénérer `PalWorldSettings.ini`.
5. Redémarrer `palworld.service` seulement si nécessaire.
6. Vérifier avec `.\scripts\palworld-console.ps1 -Action Status` et `.\scripts\palworld-api.ps1 settings`.
