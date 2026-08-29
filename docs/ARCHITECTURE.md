# Architecture publique

Gaylémon sépare quatre responsabilités :

1. une source privée produit des observations;
2. une projection retire les données techniques et privées;
3. un agent signé transmet seulement les documents publics avec une file durable;
4. le service Go stocke les générations cohérentes et sert le portail.

```text
source privée → projection filtrée → agent signé → PostgreSQL → portail public
```

Le dépôt ne fixe aucun domaine, hôte, chemin d’installation ni moteur de déploiement d’une instance réelle.

## Service web

Le service Go expose les pages publiques, les événements paginés, l’état des saisons et les archives. Les lots agent sont signés, horodatés, protégés contre le rejeu et activés transactionnellement. PostgreSQL 16 conserve les événements, documents et séquences de chaque saison.

## Portail

Le portail sert `/`, `/terminal`, `/resume`, `/classements`, `/carte`, `/github`, `/informations` et `/confidentialite`. Les pages ne lisent que les contrats publics. Une génération incomplète n’est jamais mélangée à la génération active.

Les actifs CSS et JavaScript sont nommés selon leur SHA-256 à l’exécution. Seuls ces noms reçoivent un cache immuable. HTML, service worker, version et manifestes sont revalidés; la release d’actifs précédente est retenue.

## Saisons

Une saison suit `draft → active → finalizing → archived`, avec `failed` pour une transition incomplète. Une archive est en lecture seule, garde son manifeste déterministe et cesse tout sondage périodique côté navigateur. Voir [Saisons et archives](SAISONS.md).

## Données et certitude

Les projections publiques excluent les sauvegardes brutes, adresses, coordonnées sensibles, identifiants techniques et secrets. Une observation dérivée doit rester formulée comme telle. Les exemples JSON du dépôt sont fictifs.

## Exploitation privée

Les fichiers d’installation, unités de service, tâches planifiées, chemins, sauvegardes, adaptateurs de déploiement et procédures d’urgence ne font pas partie du dépôt public. Leur validation reste une responsabilité distincte de l’exploitation de l’instance.
