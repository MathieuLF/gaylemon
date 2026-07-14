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

## Points sensibles

- SSH et scripts distants;
- règles `sudoers`;
- API REST Palworld;
- projections publiques des sauvegardes;
- déploiement et mise à jour;
- configuration Nginx.

Uptime Kuma, Cloudflare, Palworld et PalworldSaveTools restent des projets ou services externes. Les failles qui les concernent doivent aussi être signalées chez eux.

## Secret publié par erreur

Révoquer le secret tout de suite, en créer un nouveau, puis nettoyer l'historique Git si le dépôt n'a pas encore été publié. Supprimer la valeur du dernier commit ne suffit pas.
