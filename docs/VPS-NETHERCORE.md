# Publication sur la VPS Nethercore

Le microsite, son API et PostgreSQL 16 vivent sur la VPS. Le serveur Ubuntu du jeu ne reçoit aucune connexion entrante depuis la VPS : l'agent Gaylémon pousse uniquement des données publiques filtrées par HTTPS signé.

## Dépôt et livraison

Le dépôt public `MathieuLF/gaylemon` reste le dépôt unique. Le code du microsite, le service Go, les migrations et l'agent évoluent ensemble sur `main`. Une branche permanente de déploiement ou un second dépôt créerait deux sources de vérité sans apporter d'isolation utile.

Dans DockPanel, le déploiement Git doit suivre :

- dépôt : `https://github.com/MathieuLF/gaylemon.git`;
- branche : `main`;
- fichier Compose : `compose.production.yaml`;
- mise à jour : uniquement après la validation de `main`.

Les fonctionnalités passent par des branches courtes et une pull request. La VPS ne contient aucun changement de code non publié dans Git.

## Secrets de la VPS

Copier `.env.production.example` vers un fichier privé géré par DockPanel, puis renseigner :

- un mot de passe PostgreSQL aléatoire;
- la ou les clés publiques Ed25519 des agents;
- l'identifiant et le secret de l'application OAuth GitHub.

L'application OAuth utilise ce rappel exact :

```text
https://gaylemon.nethercore.dev/ops/auth/github/callback
```

Le tableau `/ops` n'accepte que l'identifiant GitHub numérique `753560`. Changer le nom du compte GitHub ne change donc pas l'autorisation.

## Clé de l'agent Ubuntu

La clé privée reste sur Ubuntu dans `/etc/gaylemon/agent.key` et n'entre jamais dans Git.

```bash
gaylemon keygen --private /tmp/gaylemon-agent.key
sudo install -o root -g root -m 0750 -d /etc/gaylemon
sudo install -o gaylemon -g gaylemon -m 0750 -d /var/lib/gaylemon-agent
sudo install -o root -g root -m 0600 /tmp/gaylemon-agent.key /etc/gaylemon/agent.key
sudo install -o root -g root -m 0640 server/agent.env.example /etc/gaylemon/agent.env
```

La commande affiche uniquement la clé publique à placer dans `GAYLEMON_AGENT_PUBLIC_KEYS` sur la VPS. Le fichier temporaire privé doit ensuite être retiré.

## Démarrage progressif

1. Déployer PostgreSQL et le service web sans modifier le DNS.
2. Importer les JSON publics actuels avec une clé d'amorçage distincte.
3. Publier l'agent Ubuntu en mode `--shadow` et comparer `/ops` avec les fichiers actuels.
4. Activer les lots de l'agent quand les volumes, durées et documents correspondent.
5. Pointer `gaylemon.nethercore.dev` vers la VPS et vérifier toutes les routes.
6. Pointer ensuite `gaylemon.mathieu.pro` vers la même application. Le service répond en `301` vers la nouvelle URL en conservant chemin et query.
7. Désactiver les anciennes tâches Windows seulement après plusieurs cycles stables.

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

Le tableau n'envoie jamais de shell arbitraire. L'agent accepte seulement les opérations prévues par `gaylemon-admin` : statut, journaux, pause/reprise, lancement d'un flux, horaire prédéfini, annonce, sauvegarde, mise à jour et redémarrage d'une unité autorisée.

Un redémarrage de `palworld.service` exige à la fois une connexion OAuth de moins de cinq minutes, la confirmation `GAYLÉMON` et le drapeau explicite propre au jeu. Le déploiement du microsite ou de l'agent ne redémarre jamais Palworld.

## Retour arrière

Tant que la migration reste en observation, l'ancien microsite continue de fonctionner. Après la bascule :

1. remettre le DNS du nouveau domaine sur la cible précédente si le service public est indisponible;
2. arrêter les timers `gaylemon-publish-*` et l'agent sans toucher aux collecteurs Palworld;
3. restaurer le volume PostgreSQL depuis sa sauvegarde si les données sont en cause;
4. redéployer le dernier commit validé dans DockPanel.

Le volume PostgreSQL et `/var/lib/gaylemon-agent/spool.db` ne doivent pas être supprimés pendant un retour arrière ordinaire.
