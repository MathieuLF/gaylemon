# Profil de configuration Palworld fourni

Ce document décrit le profil PvE codé dans `server/bin/palworld-configure-balanced.sh` et vérifié sur l'instance Gaylémon. Il ne contient aucun secret et ne prétend pas remplacer un audit de la configuration active d'une autre installation. Les valeurs réellement appliquées peuvent évoluer séparément.

Référence officielle Palworld 1.0:

```text
https://docs.palworldgame.com/settings-and-operation/configuration/
```

## Verdict

Le profil fourni n'est pas une configuration par défaut brute. Les éléments importants sont fixés pour un serveur privé PvE:

- accès joueur protégé par mot de passe;
- mot de passe admin défini, non documenté en clair;
- PvP désactivé;
- mods client refusés;
- liste des joueurs activée;
- backups Palworld internes activés;
- REST API activée localement pour annonces et monitoring;
- RCON désactivé;
- capacité réduite à `12` joueurs au lieu du défaut `32`;
- profil de challenge léger déjà appliqué.

Aucun changement urgent du profil fourni n'est requis.

## Paramètres modifiés par rapport au défaut

| Paramètre | Défaut | Profil fourni | Intention |
| --- | --- | --- | --- |
| `ServerPlayerMaxNum` | `32` | `12` | adapté au groupe de 8 à 10 joueurs |
| `ServerPassword` | vide | défini | serveur privé |
| `AdminPassword` | vide | défini | administration et API |
| `ServerName` | `Default Palworld Server` | `Gaylemon Palworld 1.0` | nom lisible |
| `ServerDescription` | vide | défini | description serveur |
| `bAllowClientMod` | `True` | `False` | éviter les clients moddés |
| `RESTAPIEnabled` | `False` | `True` | monitoring, annonces, scripts |
| `bShowPlayerList` | `False` | `True` | confort joueurs |
| `bIsStartLocationSelectByMap` | `False` | `True` | départ plus convivial |
| `bBuildAreaLimit` | `False` | `True` | limiter les constructions problématiques |
| `bEnableNonLoginPenalty` | `True` | `False` | éviter de punir les absences |
| `BaseCampWorkerMaxNum` | `15` | `18` | bases un peu plus vivantes |
| `BaseCampMaxNumInGuild` | `4` | `5` | marge pour le groupe |
| `GuildPlayerMaxNum` | `20` | `12` | cohérent avec le serveur |
| `PalCaptureRate` | `1.0` | `0.95` | capture légèrement plus exigeante |
| `CollectionDropRate` | `1.0` | `1.1` | collecte un peu moins punitive |
| `PlayerStomachDecreaceRate` | `1.0` | `1.1` | survie légèrement plus présente |
| `PlayerStaminaDecreaceRate` | `1.0` | `1.05` | effort légèrement plus coûteux |
| `PalStomachDecreaceRate` | `1.0` | `1.05` | gestion des Pals un peu plus active |
| `PalEggDefaultHatchingTime` | `1.0` | `0.75` | incubation plus agréable |
| `EquipmentDurabilityDamageRate` | `1.0` | `1.05` | usure légèrement plus présente |
| `BuildObjectDeteriorationDamageRate` | `1.0` | `0.4` | bases moins pénibles à maintenir |
| `ChatPostLimitPerMinute` | `30` | `20` | anti-spam léger |

## À évaluer avant de changer

Ces paramètres ne sont pas urgents. Ils doivent être choisis selon le groupe de joueurs.

### Restreindre les plateformes

Actuel:

```ini
CrossplayPlatforms=(Steam,Xbox,PS5,Mac)
```

Si tous les joueurs sont sur Steam, on peut envisager:

```ini
CrossplayPlatforms=(Steam)
```

Impact: surface d'accès plus limitée. À éviter si des amis jouent sur console ou Mac.

### Limiter le nombre total de bases

Actuel:

```ini
BaseCampMaxNum=128
```

Pour un serveur de 8 à 10 joueurs, une limite plus réaliste pourrait être `32`, `48` ou `64`.

Impact: réduit le risque de surcharge si chacun construit partout. À choisir seulement après discussion du style de jeu.

### Limiter les constructions par joueur

Actuel:

```ini
MaxBuildingLimitNum=0
```

`0` signifie illimité. On peut laisser comme ça au début, puis limiter si les performances chutent ou si le monde devient trop chargé.

### Afficher l'identité du constructeur

Actuel:

```ini
bEnableBuildingPlayerUIdDisplay=False
```

Passer à `True` peut aider à modérer les constructions problématiques. À éviter si l'on préfère garder l'expérience plus immersive.

### Voice chat

Actuel:

```ini
bEnableVoiceChat=False
```

À garder désactivé si le groupe utilise Discord. À activer seulement si les joueurs veulent tester le vocal intégré.

## À garder tel quel pour l'instant

- `RCONEnabled=False`: bon choix, l'API REST locale suffit.
- `RESTAPIEnabled=True`: utile pour scripts et monitoring, avec UFW qui bloque l'accès réseau.
- `PublicIP=""`: pas nécessaire pour une connexion directe via DNS et port forward.
- `DeathPenalty=Item`: bon compromis challenge/plaisir.
- `bAutoResetGuildNoOnlinePlayers=False`: évite de supprimer des bases pendant les absences.
- `ServerReplicatePawnCullDistance=15000`: à ne réduire que si les performances deviennent un problème.

## Processus recommandé pour un futur changement

1. Faire un backup.
2. Modifier `server/bin/palworld-configure-balanced.sh`.
3. Déployer le fichier sur le serveur.
4. Regénérer `PalWorldSettings.ini`.
5. Redémarrer `palworld.service`.
6. Valider avec `.\scripts\palworld-console.ps1 -Action Status` et `.\scripts\palworld-api.ps1 settings`.
