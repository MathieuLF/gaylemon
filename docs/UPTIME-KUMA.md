# Uptime Kuma

Uptime Kuma est externe à Gaylémon. Le dépôt lui envoie un battement et lit sa page publique, mais ne gère ni son conteneur, ni ses volumes, ni ses moniteurs.

## État public

Page:

```text
https://uptime.mathieu.pro/status/palworld
```

Sonde:

```text
Palworld - Gaylémon
```

La page reste volontairement courte et lisible pour les joueurs. Elle ne doit pas afficher le mot de passe, le port REST, les détails du tunnel ou la configuration interne.

## Push depuis Ubuntu

Le serveur pousse l'état avec:

```text
/srv/storage/steam/bin/palworld-kuma-push.sh
palworld-kuma-push.service
palworld-kuma-push.timer
```

Le jeton reste sur Ubuntu:

```text
/etc/palworld/kuma.env
```

Principe:

- Palworld répond localement: push `up`.
- L'API locale ne répond pas: push `down`.
- Aucune ouverture publique de `8212/tcp` n'est nécessaire.

Voir les logs:

```powershell
.\scripts\palworld-console.ps1 -Action Logs -LogMode kuma
```

Forcer un push:

```powershell
.\scripts\palworld-console.ps1 -Action PushKuma
```

## Microsite et historique

Le microsite ne contacte pas directement `uptime.mathieu.pro`. La synchronisation Windows lit l'API locale Kuma, puis publie des versions filtrées:

```text
portal/data/public-uptime.json
portal/data/public-uptime-history.json
portal/data/public-availability.json
```

Le navigateur lit seulement ce JSON local.

`public-uptime.json` vient de la page publique Kuma. `public-uptime-history.json` lit la base SQLite Kuma en lecture seule dans le conteneur local et reconstruit:

- les heartbeats `down`;
- les heartbeats `pending` et `No heartbeat in the time window`;
- les grands trous entre deux heartbeats, typiques d'une panne electrique, Internet ou d'un redemarrage du PC qui heberge Kuma.

`public-availability.json` sert de ledger local de reprise: etat Kuma, fraicheur des exports publics, fenetres d'indisponibilite et uptime calcule.

Rafraichir manuellement:

```powershell
.\scripts\export-public-uptime.ps1
.\scripts\export-uptime-kuma-history.ps1
```

Inscrire dans Uptime Kuma une coupure que Kuma n'a pas pu observer lui-meme:

```powershell
.\scripts\register-kuma-downtime.ps1
.\scripts\register-kuma-downtime.ps1 -Apply
```

Le premier appel est un dry-run. Avec `-Apply`, le script sauvegarde d'abord la base sous `/app/data/gaylemon-kuma-backup-*.db`, puis ajoute une correction idempotente pour les trous detectes. Ne pas utiliser ce mode pour une maintenance volontaire deja marquee dans Kuma.

## Métriques

Kuma n'est pas Grafana. Avec une sonde `Push`, on garde une seule valeur numérique et un message.

Gaylémon met donc le `serverframetime` Palworld dans `ping`, puis ajoute dans le message:

- joueurs connectés;
- FPS instantané et moyen;
- frame time;
- jour de jeu;
- nombre de camps;
- uptime Palworld.

Pour des graphiques historiques complets, il faudra un outil dédié.

## Si Kuma est dans le LAN

Autoriser uniquement l'IP de Kuma vers l'API Palworld:

```powershell
.\scripts\palworld-kuma-firewall.ps1 -Action allow -KumaIp 192.168.86.X
.\scripts\palworld-kuma-firewall.ps1 -Action status
.\scripts\palworld-kuma-firewall.ps1 -Action remove -KumaIp 192.168.86.X
```

Le refus global de `8212/tcp` doit rester en place.

Sonde recommandée:

- type `HTTP(s)` ou `JSON Query`;
- URL `http://ADRESSE_LAN:8212/v1/api/metrics`;
- Basic Auth avec l'admin Palworld;
- code accepté `200`.

Ne pas utiliser `8211`: c'est le port UDP du jeu, pas l'API.

## Si Kuma est hors LAN

Ne pas publier `8212/tcp` sur Internet. Préférer:

- le mode `Push`;
- un petit endpoint public de santé sans secret;
- Cloudflare Tunnel + Access si une authentification externe est vraiment nécessaire.
