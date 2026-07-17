# Sécurité

Gaylémon touche à un serveur Palworld réel. Merci de signaler les problèmes en privé.

## Versions suivies

Tant qu'il n'y a pas de version stable, seule la branche par défaut reçoit les correctifs.

## Signaler un problème

Ne pas ouvrir d'issue publique avec un secret, une vulnérabilité exploitable ou une donnée joueur.

Utiliser **Security advisories > Report a vulnerability** sur GitHub. Si l'option n'est pas disponible, contacter le propriétaire du dépôt par un canal privé.

Inclure si possible:

- la révision concernée;
- le composant touché;
- les étapes minimales de reproduction;
- l'impact;
- une piste de correction.

## Modèle de sécurité

Le dépôt décrit seulement les fichiers non secrets. Les sauvegardes réelles, secrets, bases SQLite, journaux et fichiers locaux restent hors Git.

Les installations Ubuntu passent par `server/deployment-manifest.json`. Le script d'installation refuse les destinations hors allowlist, valide les fichiers avant copie, sauvegarde les fichiers remplacés et ne redémarre aucun service par défaut.

L'accès `sudo` non interactif autorisé pour l'exploitation est volontairement limité à:

```text
/usr/local/sbin/gaylemon-deploy-install
```

Ce wrapper accepte seulement une zone de stage sous `/tmp/gaylemon-staging/AAAAMMJJ-HHMMSS`, puis délègue au script de déploiement versionné dans ce stage. Il ne donne pas un accès `sudo` général.

## Vecteurs sensibles

- SSH et scripts distants;
- règles `sudoers`;
- wrapper `/usr/local/sbin/gaylemon-deploy-install`;
- API REST Palworld;
- projections publiques des sauvegardes;
- déploiement et mise à jour;
- configuration Nginx.

Les changements touchant ces zones doivent être revus avec les risques d'exploitation en tête: redémarrage implicite, élargissement d'une permission, publication d'un identifiant privé, exposition d'un endpoint ou relâchement d'un filtre public.

Uptime Kuma, Cloudflare, Palworld et PalworldSaveTools restent des projets ou services externes. Les failles qui les concernent doivent aussi être signalées chez eux.

## Secret publié par erreur

Révoquer le secret tout de suite, en créer un nouveau, puis nettoyer l'historique Git si le dépôt n'a pas encore été publié. Supprimer la valeur du dernier commit ne suffit pas.

## Documentation utile

- [Sécurité d'exploitation](docs/SECURITE-EXPLOITATION.md)
- [Déploiement](docs/DEPLOIEMENT.md)
- [Source de vérité](docs/SOURCE-DE-VERITE.md)
