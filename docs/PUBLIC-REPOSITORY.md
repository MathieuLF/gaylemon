# Frontière du dépôt public

## Publiable

- code Go du service, de l’agent et des projections;
- migrations PostgreSQL;
- HTML, CSS, JavaScript et PWA;
- tests et données strictement fictives;
- contrats de données et documentation produit;
- recettes de validation et de release sans destination d’exploitation.

## Privé

- domaines et identifiants d’hôtes réels;
- topologie, chemins, réseaux et ports propres à une instance;
- adaptateurs de déploiement et runbooks;
- sauvegardes, reçus, journaux, PID et bases locales;
- clés, jetons, certificats, mots de passe et fichiers d’environnement;
- exports réels non anonymisés.

`scripts/valider-depot.ps1` inspecte les fichiers suivis et bloque les motifs interdits dans la branche active. Cette validation ne remplace pas une réécriture d’historique lorsqu’une donnée privée a déjà été publiée.
