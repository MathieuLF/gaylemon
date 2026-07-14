# Personnalisation Palworld

Le serveur actuel est configuré pour un PvE privé avec un niveau de difficulté raisonnable.

## Déjà actif

- `ServerName="Gaylemon Palworld 1.0"`
- `ServerDescription="Serveur privé - challenge PvE raisonnable pour 8-10 joueurs"`
- `ServerPlayerMaxNum=12`
- PvP désactivé
- mods client désactivés
- liste des joueurs activée
- messages join/leave Palworld actifs
- REST API locale activée pour les annonces et la surveillance via SSH

## Messages et annonces

Palworld supporte les messages admin en jeu avec `/Broadcast`, et la REST API 1.0 supporte `/announce`.

Depuis le jeu, après authentification admin:

```text
/AdminPassword MOT_DE_PASSE_ADMIN
/Broadcast Message_du_serveur
```

Depuis ce poste:

```powershell
.\scripts\palworld-console.ps1 -Action Announce -Message "Événement: chasse aux boss ce soir à 20h30."
```

Limite importante: Palworld n'a pas de paramètre officiel simple pour un message de bienvenue automatique par joueur à chaque connexion. Pour ce comportement, une automatisation surveille `/players` et annonce l'arrivée d'un nouveau joueur.

Cette automatisation est fournie avec `palworld-welcome.service`.

Voir son état:

```powershell
.\scripts\palworld-console.ps1 -Action Status
```

Voir ses logs:

```powershell
.\scripts\palworld-console.ps1 -Action Logs -LogMode welcome -Follow
```

Les messages sont dans:

```text
server/bin/palworld-welcome-watch.sh
```

La rotation contient plusieurs dizaines de messages humoristiques, parfois sarcastiques, choisis aléatoirement. Le watcher évite de servir deux fois de suite le même message à un joueur et conserve l'anti-spam de 30 minutes entre deux annonces pour ce joueur.

## Idées amusantes et dynamiques

- Message d'annonce avant les événements: soirée de boss, exploration, défi de capture ou construction de base.
- Annonce manuelle après une mise à jour ou un redémarrage.
- Description du serveur adaptée selon la saison ou l'événement.
- Rotation aléatoire de messages de bienvenue dans `palworld-welcome-watch.sh`.
- Événements maison annoncés avec `.\scripts\palworld-console.ps1 -Action Announce`.
- `SupplyDropSpan` ajustable pour rendre les météorites et ravitaillements plus ou moins fréquents.
- `RandomizerType=Region` ou `RandomizerType=All` pour un monde plus chaotique, à réserver à une nouvelle saison.
- `bEnableVoiceChat=True` pour tester le clavardage vocal en jeu.
- `DeathPenalty=ItemAndEquipment` pour une saison plus sévère, mais ce n'est pas recommandé pour un groupe occasionnel.

## Paramètres de difficulté actuels

- `ExpRate=1.000000`
- `PalCaptureRate=0.950000`
- `CollectionDropRate=1.100000`
- `EnemyDropItemRate=1.000000`
- `DeathPenalty=Item`
- `PalEggDefaultHatchingTime=0.750000`
- `PlayerStomachDecreaceRate=1.100000`
- `PlayerStaminaDecreaceRate=1.050000`
- `EquipmentDurabilityDamageRate=1.050000`
- `BaseCampWorkerMaxNum=18`

## Changer le profil

Le profil est géré par:

```text
server/bin/palworld-configure-balanced.sh
```

Sur le serveur, le fichier actif est:

```text
/srv/storage/steam/servers/palworld/game/Pal/Saved/Config/LinuxServer/PalWorldSettings.ini
```

Après un changement de configuration, redémarrer le service:

```powershell
.\scripts\palworld-console.ps1 -Action Restart
```

Avant les changements importants, lancer une sauvegarde:

```powershell
.\scripts\palworld-console.ps1 -Action Backup
```
