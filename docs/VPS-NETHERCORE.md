# Publication sur la VPS Nethercore

Le microsite, son API et PostgreSQL 16 vivent sur la VPS. PostgreSQL est une base distincte gérée par DockPanel, pas un service du Compose applicatif. Le serveur Ubuntu du jeu ne reçoit aucune connexion entrante depuis la VPS : l'agent Gaylémon pousse uniquement des données publiques filtrées par HTTPS signé.

## Dépôt et livraison

Le dépôt public `MathieuLF/gaylemon` reste le dépôt unique. Le code du microsite, le service Go, les migrations et l'agent évoluent ensemble sur `main`. Une branche permanente de déploiement ou un second dépôt créerait deux sources de vérité sans apporter d'isolation utile.

Dans DockPanel, le déploiement Git doit suivre :

- dépôt : `https://github.com/MathieuLF/gaylemon.git`;
- branche : `main`;
- fichier Compose : `compose.production.yaml`;
- mise à jour : uniquement après la validation de `main`.

Les fonctionnalités passent par des branches courtes et une pull request. La VPS ne contient aucun changement de code non publié dans Git.

## Secrets de la VPS

Le Vault DockPanel **Gaylémon production**, rattaché au site `gaylemon.nethercore.dev`, est la source de vérité. Il contient exactement quatre entrées avec l'injection automatique activée :

- `GAYLEMON_DATABASE_URL`;
- `GAYLEMON_AGENT_PUBLIC_KEYS`;
- `GAYLEMON_GITHUB_CLIENT_ID`;
- `GAYLEMON_GITHUB_CLIENT_SECRET`.

`/etc/gaylemon/production.env` est une matérialisation temporaire nécessaire à Docker Compose. Il est généré depuis l'API locale de DockPanel, appartient à `root:root` et reste en mode `0600`. Il ne doit jamais être modifié directement.

Installer les commandes d'exploitation sur la VPS :

```bash
sudo install -o root -g root -m 0755 vps/gaylemon-vault-sync.py /usr/local/sbin/gaylemon-vault-sync
sudo install -o root -g root -m 0755 vps/gaylemon-deploy-production /usr/local/sbin/gaylemon-deploy-production
```

Lors d'une première adoption seulement, importer les quatre valeurs de l'ancien fichier puis les relire immédiatement depuis le coffre :

```bash
sudo gaylemon-vault-sync bootstrap --source /etc/gaylemon/production.env
sudo gaylemon-vault-sync sync
sudo gaylemon-vault-sync check
```

Après une rotation dans DockPanel, ou pour livrer une nouvelle version, utiliser la commande unique :

```bash
sudo gaylemon-deploy-production
```

Elle synchronise d'abord le Vault, valide le Compose sans afficher les valeurs, redéploie uniquement le service web et vérifie le port local `18081`. Elle ne touche ni à PostgreSQL, ni à l'agent Ubuntu, ni à Palworld.

Le déploiement lit la version produit dans `VERSION` et injecte aussi le commit Git complet dans le binaire. Après livraison, la route publique suivante permet de vérifier exactement ce qui répond:

```bash
curl --fail --silent https://gaylemon.nethercore.dev/version
```

Depuis le poste Windows, la comparaison complète se fait avec:

```powershell
.\scripts\comparer-version.ps1 -Strict
```

La commande réussit seulement si la version et le commit du dépôt local propre, de `origin/main` et de la VPS sont identiques. La route `/version` ne contient aucun secret et répond avec `Cache-Control: no-store`.

Dans DockPanel, rattacher une base `gaylemon` au site `gaylemon.nethercore.dev` avec PostgreSQL 16. Son conteneur `dockpanel-db-gaylemon` reste sur le réseau privé `dockpanel-db`, est publié seulement sur `127.0.0.1:5435` et rejoint aussi le réseau Docker `gaylemon_private`. DockPanel génère le mot de passe du rôle propriétaire `gaylemon`; l'application le reçoit uniquement dans son URL de connexion :

```text
postgresql://gaylemon:MOT_DE_PASSE_APPLICATION@dockpanel-db-gaylemon:5432/gaylemon?sslmode=disable
```

La limite par défaut de 256 Mio du conteneur PostgreSQL ne suffit pas à restaurer la table de contenus. Conserver une limite de 1 Gio et 2 Gio avec l'espace d'échange :

```bash
sudo docker update --memory 1g --memory-swap 2g dockpanel-db-gaylemon
sudo docker network connect gaylemon_private dockpanel-db-gaylemon
```

La seconde commande est idempotente seulement si le réseau n'est pas déjà raccordé : vérifier les réseaux du conteneur avant de la relancer. Le site `gaylemon.nethercore.dev` doit aussi apparaître dans la section **Sites** de DockPanel comme proxy HTTPS vers le port local `18081`.

Le nom `www.gaylemon.nethercore.dev` doit pointer vers la même VPS, présenter son propre certificat TLS valide, puis répondre en `301` vers `https://gaylemon.nethercore.dev` en conservant le chemin et les paramètres. Le certificat doit être en place avant la redirection, puisque le domaine `.dev` impose HTTPS.

L'application OAuth utilise ce rappel exact :

```text
https://gaylemon.nethercore.dev/ops/auth/github/callback
```

Le tableau `/ops` n'accepte que l'identifiant GitHub numérique `753560`. Changer le nom du compte GitHub ne change donc pas l'autorisation.

## Clé de l'agent Ubuntu

La clé privée reste sur Ubuntu dans `/home/gaylemon/.config/gaylemon/agent.key` et n'entre jamais dans Git.

```bash
gaylemon keygen --private /tmp/gaylemon-agent.key
sudo install -o root -g root -m 0750 -d /etc/gaylemon
sudo install -o gaylemon -g gaylemon -m 0750 -d /var/lib/gaylemon-agent
install -d -m 0700 /home/gaylemon/.config/gaylemon
install -m 0600 /tmp/gaylemon-agent.key /home/gaylemon/.config/gaylemon/agent.key
install -m 0600 server/agent.env.example /home/gaylemon/.config/gaylemon/agent.env
```

La commande affiche uniquement la clé publique à placer dans `GAYLEMON_AGENT_PUBLIC_KEYS` sur la VPS. Le fichier temporaire privé doit ensuite être retiré.

## Démarrage progressif

1. Créer PostgreSQL 16 dans DockPanel, le relier au réseau `gaylemon_private`, puis déployer le service web sans modifier le DNS.
2. Importer les JSON publics actuels avec une clé d'amorçage distincte.
3. Publier l'agent Ubuntu en mode `--shadow` et comparer `/ops` avec les fichiers actuels.
4. Activer les lots de l'agent quand les volumes, durées et documents correspondent.
5. Pointer `gaylemon.nethercore.dev` vers la VPS et vérifier toutes les routes.
6. Pointer `www.gaylemon.nethercore.dev` vers la VPS, installer son certificat TLS et vérifier son `301` vers le domaine sans `www`, chemin et paramètres compris.
7. Pointer ensuite `gaylemon.mathieu.pro` vers la même application. Le service répond en `301` vers la nouvelle URL en conservant chemin et query.
8. Désactiver les anciennes tâches Windows seulement après plusieurs cycles stables.

L'amorçage depuis le poste actuel peut utiliser un agent temporaire nommé `bootstrap-windows`. Le répertoire `portal/data` est découpé automatiquement en lots inférieurs à 64 Mio et les fichiers `*.example.json` sont ignorés.

```powershell
$env:GAYLEMON_AGENT_ID = "bootstrap-windows"
$env:GAYLEMON_API_BASE_URL = "https://gaylemon.nethercore.dev"
$env:GAYLEMON_AGENT_PRIVATE_KEY_FILE = "C:\chemin\prive\bootstrap.key"
$env:GAYLEMON_AGENT_SPOOL = "C:\chemin\prive\bootstrap-spool.db"
go run -mod=mod .\cmd\gaylemon publish --source .\portal\data --prefix data --stream bootstrap
go run -mod=mod .\cmd\gaylemon publish --source .\portal\public-events-channel.json --prefix public-events-channel.json --stream bootstrap
```

Retirer la clé publique `bootstrap-windows` de la VPS après l'import.

## Ressources et rétention

Chaque lot conserve sa durée, sa mémoire maximale, ses lectures, ses écritures et son volume transmis. `/ops` expose les agents, la profondeur des files, les exécutions et les commandes récentes.

La base conserve :

- 365 jours de mesures et d'exécutions;
- les événements sans date d'expiration automatique;
- la version active et six versions détaillées de chaque document de sauvegarde;
- un checkpoint quotidien des sauvegardes pendant 365 jours;
- 365 jours de commandes et d'audit.

La file SQLite locale utilise WAL et `synchronous=FULL`. Une coupure de la VPS ou d'Internet ne bloque donc pas les collecteurs du jeu : les lots restent sur Ubuntu et repartent dans l'ordre.

## Commandes distantes

Le tableau n'envoie jamais de shell arbitraire. L'agent accepte seulement les opérations prévues par `gaylemon-admin` : statut, journaux, pause/reprise, lancement d'un flux, horaire prédéfini, annonce, sauvegarde et redémarrage d'une unité auxiliaire autorisée.

La mise à jour du jeu et le redémarrage de `palworld.service` ne sont pas exposés dans Ops ni acceptés par l'agent. Ils restent accessibles depuis la console Windows, avec une élévation `sudo` interactive et une confirmation locale distincte. Le déploiement du microsite ou de l'agent ne redémarre jamais Palworld.

## Retour arrière

Tant que la migration reste en observation, l'ancien microsite continue de fonctionner. Après la bascule :

1. remettre le DNS du nouveau domaine sur la cible précédente si le service public est indisponible;
2. arrêter les timers `gaylemon-publish-*` et l'agent sans toucher aux collecteurs Palworld;
3. restaurer la sauvegarde PostgreSQL depuis DockPanel si les données sont en cause;
4. redéployer le dernier commit validé dans DockPanel.

Les sauvegardes PostgreSQL DockPanel et `/var/lib/gaylemon-agent/spool.db` ne doivent pas être supprimés pendant un retour arrière ordinaire. Après une migration de base, conserver l'ancien conteneur arrêté et son volume jusqu'à la validation du nouveau service et de sa première sauvegarde DockPanel.
