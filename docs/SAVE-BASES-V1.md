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

## Ce qui reste privé

`runtime/private-save-bases.json` reste sur Ubuntu en mode `0600`.

Il peut contenir le détail opérationnel des inventaires et emplacements. Il n'est pas synchronisé vers Windows, pas monté dans Docker et pas servi par Nginx.

## Explorateur des stocks

Chaque fiche joueur charge les stocks à la demande. L'interface permet:

- recherche par nom, catégorie, source ou campement;
- filtre par catégorie;
- vues toutes sources, coffres, production et stockage de guilde;
- pagination des ressources.

## Coût observé

Sur les mesures du 12 juillet 2026, le traitement complet restait autour de 1,5 à 2,3 secondes avec une mémoire sous la limite systemd de 768 Mio. Les priorités CPU et disque gardent Palworld prioritaire.

## Vérification

```powershell
Get-Content .\portal\data\public-save-diagnostics.json | ConvertFrom-Json
python -m unittest server.tests.test_palworld_save_snapshot -v
ssh gaylemon "systemctl is-active palworld.service"
```
