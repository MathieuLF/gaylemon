# Sources officielles Palworld

Références utilisées pour la configuration et l'exploitation:

- Configuration serveur: https://docs.palworldgame.com/settings-and-operation/configuration/
- Commandes admin: https://docs.palworldgame.com/settings-and-operation/commands/
- Introduction à la REST API: https://docs.palworldgame.com/api/rest-api/palwold-rest-api/
- REST API `/players`: https://docs.palworldgame.com/api/rest-api/players/
- REST API `/metrics`: https://docs.palworldgame.com/api/rest-api/metrics/
- REST API `/game-data`: https://docs.palworldgame.com/api/rest-api/game-data/
- Arguments du serveur 1.0: https://docs.palworldgame.com/settings-and-operation/arguments/
- Point de terminaison REST `/announce`: https://docs.palworldgame.com/api/rest-api/announce/
- Point de terminaison REST `/info`: https://docs.palworldgame.com/api/rest-api/info/
- Prise en charge de Palworld par GameDig: https://github.com/gamedig/node-gamedig
- Applications publiées par Cloudflare Tunnel: https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/do-more-with-tunnels/local-management/configuration-file/
- Enregistrements DNS Cloudflare Tunnel: https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/routing-to-tunnel/dns/
- Suivi communautaire de la limitation `/game-data`: https://github.com/jammsen/docker-palworld-dedicated-server
- Fork de l'outil de lecture des sauvegardes: https://github.com/MathieuLF/PalworldSaveTools
- Projet upstream PalworldSaveTools: https://github.com/deafdudecomputers/PalworldSaveTools
- Déclaration SDK 1.0 générée pour la commande Unreal `Exec` cachée `EnableGameDataAPI`: https://github.com/localcc/PalworldModdingKit/blob/62fad4130238cb0aadf024b87496e7387d5f4bf5/Source/Pal/Public/PalCheatManager.h
- Déclaration SDK 1.0 générée pour `SetGameDataAPIEnabled`: https://github.com/localcc/PalworldModdingKit/blob/62fad4130238cb0aadf024b87496e7387d5f4bf5/Source/Pal/Public/PalGameDataBridge.h

Notes importantes:

- Le fichier actif sur Linux SteamCMD est `Pal/Saved/Config/LinuxServer/PalWorldSettings.ini`.
- La REST API doit rester locale ou limitée au réseau de confiance. Ici, Palworld écoute sur `8212/tcp`, mais UFW bloque explicitement ce port en entrée et les scripts passent par SSH ou par des appels locaux.
- Les statistiques historiques locales utilisent `/metrics` et `/players`. Le point de terminaison `/game-data` est tenté pour l'enrichissement, mais le serveur actuel répond `404` avec `PalGameDataBridge GameData API is not enabled`; le collecteur doit donc rester robuste sans ce point de terminaison.
- Le binaire Palworld 1.0 contient des chaînes comme `EnableGameDataAPI`, `SetGameDataAPIEnabled` et `GameDataKey`, mais la documentation officielle de configuration ne liste aucun paramètre public pour activer ce pont.
- Pour un message de bienvenue automatique, Palworld ne fournit pas un simple paramètre de configuration dédié: on utilise donc un watcher local basé sur `/players` et `/announce`.
