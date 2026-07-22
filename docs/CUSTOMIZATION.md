# Personnalisation Palworld

Le profil actuel vise un serveur privé PvE, assez calme pour jouer entre amis, mais avec un défi plus présent.

## État actuel

- 12 joueurs maximum.
- PvP désactivé.
- Mods client refusés.
- Liste des joueurs activée.
- REST API locale activée pour les annonces et les sondes locales.
- Messages d'arrivée/départ Palworld actifs.
- Watcher de bienvenue via `palworld-welcome.service`.

## Annonces

Depuis la console locale:

```powershell
.\scripts\palworld-console.ps1 -Action Announce -Message "Événement: chasse aux boss ce soir à 20h30."
```

Depuis le jeu, après authentification admin:

```text
/AdminPassword MOT_DE_PASSE_ADMIN
/Broadcast Message_du_serveur
```

Les messages automatiques de bienvenue sont dans:

```text
server/bin/palworld-welcome-watch.sh
```

Le watcher évite le spam et ne renvoie pas deux fois de suite le même message à un joueur.

## Difficulté

Quelques valeurs du profil généré:

| Paramètre | Valeur |
|---|---:|
| `NightTimeSpeedRate` | `0.700000` |
| `ExpRate` | `1.000000` |
| `PalCaptureRate` | `0.800000` |
| `CollectionDropRate` | `1.000000` |
| `DeathPenalty` | `Item` |
| `PalEggDefaultHatchingTime` | `2.000000` |
| `MonsterFarmActionSpeedRate` | `0.700000` |
| `BaseCampWorkerMaxNum` | `18` |

Le profil est généré par:

```text
server/bin/palworld-configure-balanced.sh
```

Le fichier actif sur Ubuntu est:

```text
/srv/storage/steam/servers/palworld/game/Pal/Saved/Config/LinuxServer/PalWorldSettings.ini
```

Avant un changement important:

```powershell
.\scripts\palworld-console.ps1 -Action Backup
```

Puis appliquer et redémarrer seulement si le changement de configuration l'exige:

```powershell
.\scripts\palworld-console.ps1 -Action Restart
```

## Idées simples

- Annonces d'événement: boss, exploration, capture, construction.
- Description du serveur adaptée à une saison.
- Rotation de messages de bienvenue.
- Saison plus chaotique avec `RandomizerType`, uniquement sur une nouvelle partie.
