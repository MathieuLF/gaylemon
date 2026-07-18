# Échos publics v6

Le contrat v6 publie les échos par journée sans exposer la base SQLite ni imposer le téléchargement de l'historique complet. Le collecteur produit la projection canonique; la synchronisation Windows la valide et la copie, sans recréer les événements métier.

Les contrats v5 restent publiés pendant la période de transition. `public-events-channel.json` garde v5 actif pendant que v6 est produit et observé en parallèle. Après promotion, le portail tente v6 en premier et revient à v5 seulement si le manifeste v6 est absent ou invalide.

## Fichiers servis

- `public-events-head-v6.json`: pointeur actif compact, revalidé par ETag, vers le manifeste et la tête immuables d'une même génération;
- `public-events-manifest-v6.json`: copie de compatibilité du manifeste courant, avec comptes, curseurs, provenance, hachages et journées disponibles;
- `public-events-v6/{generationId}/manifest.json`: manifeste immuable réellement suivi par le pointeur actif;
- `public-events-v6/{generationId}/head.json`: cinq derniers échos et cinq derniers échos confirmés, avec curseur global et plage de la fenêtre chaude;
- `public-events-v6/{fragmentGenerationId}/{jour}.json`: échos canoniques d'une journée;
- `public-daily/{dailyGenerationId}/{jour}.json`: résumé quotidien précalculé, sans copie du tableau complet des événements;
- `public-events-manifest-v6.previous.json`: dernier manifeste cohérent conservé localement pour le repli d'exploitation.
- `/public-events-channel.json`: canal actif `v5` ou `v6`, revalidé avec ETag et remplacé atomiquement lors d'une promotion ou d'un repli.

Chaque entrée journalière du manifeste porte son propre `fragmentGenerationId` et `dailyGenerationId`. Une correction historique ne réécrit donc que la journée concernée. Les journées inchangées continuent de pointer vers leur fragment immuable existant.

## Cohérence d'une génération

La publication suit cet ordre:

1. lire et valider la projection canonique du collecteur;
2. écrire les nouveaux fragments et résumés dans des répertoires de génération;
3. relire les fichiers et vérifier leurs hachages et leurs comptes;
4. écrire la tête puis le manifeste immuables de la génération et vérifier leurs hachages;
5. mettre à jour la copie de compatibilité du manifeste;
6. remplacer atomiquement le pointeur actif en dernier;
7. nettoyer uniquement les générations qui ne sont plus référencées par le nouveau manifeste ou le précédent.

Quand le canal actif vaut `v6`, le portail sonde d'abord le pointeur. S'il change, il charge le manifeste immuable puis sa tête, et vérifie leurs hachages avant d'utiliser un fragment. Si une lecture échoue, il conserve l'ensemble cohérent déjà affiché. Il ne mélange jamais deux `generationId`. Tant que le canal vaut `v5`, les fichiers v6 continuent d'être publiés et contrôlés sans être adoptés par les parcours publics.

## Identité et déduplication

Les événements bruts restent privés dans SQLite. La projection canonique et ses membres sont matérialisés dans des tables séparées; le journal de mutations permet de ne recalculer qu'une queue temporelle bornée. Leur projection publique emploie une clé métier stable:

- niveau: joueur stable et niveau atteint;
- recherche: guilde stable et recherche ou total atteint;
- structure: structure stable et transition observée;
- événements compilés: clé canonique de la fenêtre et des acteurs représentés.

L'export récent décrit aussi une `projectionWindow` de type `replace-tail`: borne temporelle, révisions couvertes et preuve que la fenêtre reçue est complète. La synchronisation Windows remplace cette queue à l'identique dans les fragments concernés. Elle peut ainsi absorber la transformation d'un écho isolé en écho compilé, ou le retrait d'un doublon de session, sans refaire elle-même le regroupement. Si la révision locale précède la couverture annoncée ou si la fenêtre est tronquée, la génération active reste inchangée et une réconciliation complète est demandée.

Une réparation exige l'observation de la même structure endommagée puis saine. Une disparition ne produit pas de réparation. Les objets transitoires du monde sont exclus des structures. Une attribution de recherche déduite porte `confidence=derived`; elle ne devient pas une confirmation individuelle.

La normalisation peut masquer un événement de la projection publique, mais ne supprime jamais l'observation privée qui permet l'audit ou une reprojection ultérieure. Une mutation déjà matérialisée ou un backfill ancien place la projection en `reprojection-required`: les fichiers publics précédents restent intacts jusqu'à la demande ponctuelle explicite décrite dans [les opérations](OPERATIONS.md#reprojection-publique-contrôlée). Cette demande est consommée uniquement après la reconstruction et l'export complet réussis.

## Cache et rafraîchissement

Le canal actif, le pointeur et la copie de compatibilité du manifeste utilisent `no-cache` avec ETag: une lecture inchangée peut répondre `304` sans retransférer le contenu. Le manifeste immuable, la tête, les fragments et les résumés référencés sont servis un an avec `immutable`. Le monolithe v5 reste un export froid de compatibilité, produit au plus toutes les 15 minutes ou sur demande, et n'est pas chargé par une route normale du portail v6.

Le watcher exécute la synchronisation légère régulièrement et une réconciliation complète espacée. Les verrous existants empêchent le chevauchement des collecteurs et des copies.

## Provenance et confidentialité

Le manifeste, la tête, les fragments et les résumés transportent les champs publics communs disponibles: `observedAt`, `sourceUpdatedAt`, `gameVersion`, `steamBuildId`, `parserCommit`, `catalogCommit`, `schemaVersion`, `freshness` et `sourceStatus`.

La projection ne doit contenir ni adresse IP, ni identifiant brut, ni coordonnée privée, ni URL sensible, ni contenu détaillé de coffre. Le validateur local injecte des sentinelles sensibles dans un export fictif et refuse leur présence dans les fichiers publics.

## Validation et bascule

Avant une mise en observation:

```powershell
.\scripts\test-public-events-v6.ps1
python -m unittest discover -s .\server\tests -p "test_*.py" -v
.\scripts\valider-depot.ps1
```

La mise en observation conserve `activeContract=v5` dans `portal/public-events-channel.json`. Après 24 heures, comparer les comptes, doublons, coupures et délais, puis promouvoir atomiquement la génération déjà validée:

```powershell
.\scripts\set-public-events-channel.ps1 -ActiveContract v6
```

Le même script avec `-ActiveContract v5` effectue le repli sans retirer les fichiers v6. Le contrat v5 reste publié sept jours après la promotion. Une correction P0 ou P1 ne demande pas de redémarrer Palworld.
