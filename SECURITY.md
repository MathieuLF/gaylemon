# Politique de sécurité

## Versions prises en charge

Tant qu'aucune version stable n'est publiée, seule la dernière révision de la branche par défaut reçoit des correctifs de sécurité. Une vulnérabilité observée sur une ancienne révision doit être reproduite sur cette branche avant son signalement.

## Signaler une vulnérabilité

Ne pas publier de vulnérabilité, de secret ou de donnée joueur dans une issue publique.

Utiliser de préférence l'option **Security advisories > Report a vulnerability** du dépôt GitHub. Si elle n'est pas disponible, contacter le propriétaire du dépôt par un canal privé avant de divulguer le problème.

Inclure:

- la version ou révision concernée;
- le composant touché;
- les étapes minimales de reproduction;
- l'impact attendu;
- une proposition de correction, si disponible.

## Périmètre

Sont particulièrement sensibles:

- l'exécution de commandes SSH;
- les droits `sudoers`;
- l'API REST Palworld;
- les projections publiques de sauvegardes;
- les scripts de déploiement et de mise à jour;
- les en-têtes et chemins exposés par Nginx.

Uptime Kuma, Cloudflare et PalworldSaveTools sont des dépendances ou infrastructures externes. Leurs vulnérabilités doivent aussi être signalées au projet concerné.

## Secrets compromis

Un secret accidentellement publié doit être révoqué et remplacé immédiatement. Le retirer de la dernière révision ne suffit pas, car il demeure dans l'historique Git.
