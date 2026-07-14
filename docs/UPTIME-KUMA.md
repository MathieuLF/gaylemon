# Uptime Kuma pour Palworld

> Uptime Kuma est un service externe partagé. Gaylémon consomme sa page publique et lui envoie un battement depuis Ubuntu, mais ne gère ni son conteneur, ni son volume, ni ses moniteurs dans `compose.yaml`.

## État actuel

La sonde `Palworld - gaylemon` dans Uptime Kuma est configurée en mode `Push`.

Page de statut publique:

```text
https://uptime.mathieu.pro/status/palworld
```

La page publique affiche volontairement un contenu joueur, court et non technique:

- titre: `Palworld - Gaylémon`
- description marketing en français avec accents
- bloc cliquable `À quoi sert cette page?` avec un paragraphe marketing, sans liste à puces
- service Uptime Kuma: `Palworld - Gaylémon`
- footer: vide; aucune mention du domaine de connexion ou du port de jeu
- thème: CSS personnalisé avec ambiance Palworld/tropicale et fond texturé, sans motifs ronds/points
- bloc `Services`: un seul niveau visuel, sans double encadré autour de la sonde
- rafraîchissement: 60 secondes

La page publique ne doit pas expliquer le nom du serveur, Palpagos, l'API, le port, les mots de passe ou la configuration interne.

Référence interne côté Palworld:

- `ServerName`: `Gaylemon Palworld 1.0`
- `ServerDescription`: `Serveur prive - challenge PvE raisonnable pour 8-10 joueurs`
- `ServerPlayerMaxNum`: `12`
- `PublicPort`: `8211`

Principe:

- `gaylemon` vérifie localement la REST API Palworld avec `palworld-api.sh`.
- si Palworld répond, `gaylemon` envoie `status=up` à Uptime Kuma;
- si l'API Palworld ne répond pas, `gaylemon` envoie `status=down`;
- aucune ouverture de `8212/tcp` vers Kuma ou Internet n'est nécessaire.

Le push est géré par:

```text
/srv/storage/steam/bin/palworld-kuma-push.sh
palworld-kuma-push.service
palworld-kuma-push.timer
```

Le jeton Push est stocké sur le serveur dans:

```text
/etc/palworld/kuma.env
```

Ce fichier doit rester lisible seulement par `root` et le groupe `steam`.

Le timer pousse toutes les 30 secondes, même si Kuma vérifie aux 60 secondes. Cette marge évite les barres jaunes ou orange causées par un push qui arrive quelques secondes trop tard.

Le script de mise à jour ne dépend pas uniquement de cet échantillonnage. Lorsqu'une version Steam doit réellement être installée, il pousse explicitement trois battements `down` après l'arrêt de Palworld afin de satisfaire les deux tentatives de tolérance configurées dans Kuma. Il attend ensuite le retour de l'API REST avant de pousser `up`. Une courte coupure de maintenance ne peut donc plus passer entièrement entre deux battements.

## Microsite public

Le microsite `https://gaylemon.mathieu.pro/` intègre aussi l'état Uptime Kuma.

La synchronisation Windows lit l'API locale de la page publique Kuma:

```text
http://127.0.0.1:13001/api/status-page/palworld
http://127.0.0.1:13001/api/status-page/heartbeat/palworld
```

Puis elle écrit seulement un résumé public:

```text
portal/data/public-uptime.json
```

Le navigateur lit ce fichier local au microsite. Il ne dépend donc pas d'un appel direct à `uptime.mathieu.pro` et évite les problèmes CORS.

## Métriques Palworld dans Uptime Kuma

Uptime Kuma n'est pas un tableau de bord métrique complet. Avec une sonde `Push`, il stocke surtout:

- `status`: `up` ou `down`
- `msg`: un message texte associé au battement
- `ping`: une seule valeur numérique, affichée comme latence

Notre intégration garde donc une seule sonde fiable et enrichit le `msg` avec les métriques Palworld utiles venant de `/metrics`:

- joueurs connectés et capacité maximale
- FPS serveur instantané
- FPS serveur moyen
- frame time en millisecondes
- jour de jeu en cours
- nombre de camps
- uptime du serveur Palworld

Exemple de message poussé à Kuma:

```text
Palworld OK - joueurs 0/12 | FPS 59 (avg 59.5) | frame 16.8 ms | jour 17 | camps 0 | uptime 49m
```

La valeur `ping` est volontairement la `serverframetime` Palworld. Ce n'est pas un vrai ping réseau: c'est un indicateur de performance du serveur de jeu. Plus la valeur est basse, mieux c'est.

Pour obtenir de vrais graphiques historiques multimétriques, il faudra ajouter un outil dédié comme Prometheus/Grafana ou un petit point de terminaison JSON public séparé. Pour l'instant, Uptime Kuma reste l'outil d'état public et d'alerte.

Voir les logs:

```powershell
.\scripts\palworld-console.ps1 -Action Logs -LogMode kuma
```

Forcer un push manuel:

```powershell
.\scripts\palworld-console.ps1 -Action PushKuma
```

Voir le timer:

```powershell
.\scripts\palworld-console.ps1 -Action Status
```

## Diagnostic réseau

Le port public de jeu est bien `8211/udp`.

Ce port sert aux joueurs Palworld. Ce n'est pas un port HTTP/TCP et ce n'est pas le port utilisé par GameDig pour Palworld.

Constats vérifiés:

- DNS: `palworld.mathieu.pro` pointe vers l'IP WAN actuelle.
- Palworld écoute le jeu sur `0.0.0.0:8211/udp`.
- Palworld ouvre aussi `0.0.0.0:27015/udp`.
- Palworld écoute la REST API sur `0.0.0.0:8212/tcp`.
- UFW autorise `8211/udp`.
- UFW ne publie pas `27015/udp`.
- UFW bloque explicitement `8212/tcp`.
- GameDig `type=palworld` utilise `8212/tcp` et la REST API Palworld, pas `8211/udp`.
- La sonde Steam/Valve classique n'est pas fiable ici: un test local `protocol-valve` sur `27015/udp`, même temporairement autorisé depuis ce PC, n'a pas retourné de réponse exploitable.

L'échec Uptime Kuma n'indique donc pas que le port de jeu est faux. Il indique surtout que la sonde choisie n'interroge pas le bon protocole ou que l'API `8212/tcp` est bloquée, comme prévu.

## Option recommandée si Uptime Kuma est dans le LAN

Autoriser seulement l'IP de la machine Uptime Kuma vers l'API Palworld:

```powershell
.\scripts\palworld-kuma-firewall.ps1 -Action allow -KumaIp 192.168.86.X
```

Vérifier les règles:

```powershell
.\scripts\palworld-kuma-firewall.ps1 -Action status
```

Révoquer l'accès plus tard:

```powershell
.\scripts\palworld-kuma-firewall.ps1 -Action remove -KumaIp 192.168.86.X
```

Le `deny 8212/tcp Anywhere` doit rester en place après la règle spécifique à Kuma.

### Variante A: HTTP ou JSON Query

C'est l'option la plus fiable si ta version Uptime Kuma ne permet pas de passer `username` et `password` à GameDig.

Configurer une sonde:

- Type: `HTTP(s)` ou `JSON Query`
- URL: `http://ADRESSE_LAN:8212/v1/api/metrics`
- Method: `GET`
- Auth method: `Basic`
- Username: `admin`
- Password: le `AdminPassword` Palworld
- Accepted status code: `200`

Si tu utilises `Keyword`, cherche `serverfps`.

### Variante B: GameDig

Configurer une sonde GameDig:

- Type: `GameDig`
- Game: `Palworld`
- Hostname: l'adresse LAN du serveur, par exemple `192.168.1.50`
- Port: `8212`
- Username: `admin`
- Password: le `AdminPassword` Palworld, pas le mot de passe serveur joueur

Ne pas utiliser `8211` ici.

Si ton interface Uptime Kuma ne propose pas `Username` et `Password` pour GameDig, utilise la variante HTTP/JSON Query.

## Récupérer le mot de passe admin Palworld

Depuis ce poste:

```powershell
ssh gaylemon "perl -ne 'if (/AdminPassword=\"([^\"]*)\"/) { print `$1, qq(\n); exit }' /srv/storage/steam/servers/palworld/game/Pal/Saved/Config/LinuxServer/PalWorldSettings.ini"
```

Ne pas utiliser ce mot de passe comme mot de passe joueur. Il donne accès aux commandes admin et à l'API.

## Tester GameDig depuis un poste autorisé

```powershell
npx --yes gamedig --type palworld 192.168.1.50 --port 8212 --username admin --password MOT_DE_PASSE_ADMIN --pretty
```

Résultat attendu:

- `name`: `Gaylemon Palworld 1.0`
- `version`: version Palworld actuelle
- `maxplayers`: `12`
- `numplayers`: nombre de joueurs connectés
- `queryPort`: `8212`

## Si Uptime Kuma est à l'extérieur du LAN

Ne pas transférer `8212/tcp` vers Internet par défaut.

Raison: `8212/tcp` est l'API admin Palworld en HTTP Basic Auth. L'exposer directement sur Internet augmente inutilement la surface d'attaque.

Options plus propres:

- utiliser un moniteur `Push` Uptime Kuma depuis `gaylemon` vers Kuma;
- ajouter un petit point de terminaison public de santé qui retourne seulement `200 OK` quand Palworld fonctionne;
- exposer l'API via Cloudflare Tunnel + Access, si on veut vraiment une authentification externe forte.

## Pourquoi pas Steam?

La sonde Steam d'Uptime Kuma n'est pas un simple test de port `8211`.

Elle dépend de la visibilité et des requêtes Steam/Valve. Notre serveur actuel est configuré comme serveur privé joignable directement, et le test `protocol-valve` sur `27015/udp` n'a pas donné de résultat exploitable. Pour surveiller ce serveur, la REST API Palworld sur `8212/tcp` est plus fiable.
