# Bases et stockage v1

Le snapshot des bases complète le profil des joueurs avec les campements, travailleurs, structures et ressources agrégées.

## Ce qui est public

`runtime/public-save-bases.json` est synchronisé vers:

```text
portal/data/public-save-bases.json
```

Il contient:

- bases visibles, guilde, membres et niveau de camp;
- Pals travailleurs, état, faim, SAN, aptitudes et tâche observée;
- structures regroupées par catégorie et bâtiment;
- ressources agrégées par base;
- vue séparée des coffres, productions et stockage de guilde.

Le microsite fusionne les ressources par type. Il affiche la base, jamais le coffre exact.

Les noms techniques ou trop génériques produits par la sauvegarde peuvent être gardés dans le snapshot des bases quand ils décrivent la base globale. Dans les échos, le collecteur préfère un libellé relatif au joueur quand il peut le relier avec certitude: `Base 1`, `Base 2`, `Base 3`, selon les bases de ce joueur plutôt que selon le total mondial des bases.

## Historique horaire

`runtime/save-bases-history/` conserve une archive horaire du snapshot public des bases. Cet historique permet au journal des échos de rejouer les hausses de structures endommagées et de publier les raids sans recréer les événements déjà connus.

Le backfill `baseLabelBackfill` peut aussi normaliser les anciens événements de bases quand le snapshot courant permet d'établir la correspondance entre la base globale et le joueur concerné.

## Ce qui reste privé

`runtime/private-save-bases.json` reste sur Ubuntu en mode `0600`.

Il peut contenir le détail opérationnel des inventaires et emplacements. Il n'est pas synchronisé vers Windows, pas monté dans Docker et pas servi par Nginx.

## Explorateur des stocks

Chaque fiche joueur charge les stocks à la demande. L'interface permet:

- recherche par nom, catégorie, source ou campement;
- filtre par catégorie;
- vues toutes sources, coffres, production et stockage de guilde;
- pagination des ressources.

Le bouton `Exporter JSON` d'une fiche joueur reprend ces données publiques pour produire un fichier d'analyse contenant bases, constructions, travailleurs, stockage agrégé et stockage de guilde relié au joueur. Le fichier exporté ne contient pas le détail exact des coffres privés.

## Coût observé

Sur les mesures du 12 juillet 2026, le traitement complet restait autour de 1,5 à 2,3 secondes avec une mémoire sous la limite systemd de 768 Mio. Les priorités CPU et disque gardent Palworld prioritaire.

## Vérification

```powershell
Get-Content .\portal\data\public-save-diagnostics.json | ConvertFrom-Json
python -m unittest server.tests.test_palworld_save_snapshot -v
ssh gaylemon "systemctl is-active palworld.service"
```
