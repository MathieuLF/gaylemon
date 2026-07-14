# Bases, travailleurs et stockage v1

## Objectif

Le worker `server/bin/palworld-save-snapshot.py` décode en lecture seule les bases du monde depuis la dernière sauvegarde intégrée terminée. Il ne lit jamais le processus Palworld en mémoire et n'écrit jamais dans `Level.sav` ou `Players/*.sav`.

Le timer vérifie la sauvegarde toutes les 15 secondes et traite chaque nouvelle génération Palworld produite aux 30 secondes, avec une priorité CPU et disque faible. Les générations déjà publiées sont ignorées immédiatement. Aucun redémarrage de `palworld.service` n'est nécessaire.

## Données décodées

Le worker active 13 décodeurs PalworldSaveTools:

- guildes, personnages et inventaires;
- identité, position et état des bases;
- conteneurs de Pals et WorkerDirector;
- travaux, affectations et progression;
- objets de carte, structures et modules;
- objets dynamiques: équipement, armes et oeufs;
- stockage et laboratoire de guilde.

La projection publique expose:

- bases, membres visibles de la guilde, niveau du camp et position cartographique;
- Pals travailleurs, santé, faim, SAN, aptitudes et tâche observée;
- structures agrégées par catégorie, état et bâtiment;
- coffres, tampons de production et stockage de guilde comme trois sources distinctes;
- occupation et totalité des ressources agrégées pour chacune de ces sources;
- affectations de travail conservées dans le contrat pour diagnostic.

Le microsite retire les compteurs techniques `Travaux actifs`, `Travaux suivis` et `Recherche actuelle`. Le KPI fiable `Pals au travail` affiche un ratio global, tandis que chaque campement conserve son propre ratio. La recherche de guilde sera réintroduite plus tard dans une section dédiée, lorsque les noms pourront être traduits et la progression validée avec certitude.

## Explorateur des stocks

Chaque fiche joueur contient un explorateur paginé à 24 ressources par page. Il offre:

- une recherche par nom, catégorie, source ou campement;
- un filtre par catégorie traduite;
- quatre vues: toutes les sources, coffres, production et stockage de guilde;
- la quantité agrégée, le nombre de types et le contexte de campement;
- la totalité des ressources décodées, et non un palmarès limité aux 12 premières.

Une ressource présente dans plusieurs coffres d'une même base est fusionnée. Le microsite indique la base concernée, jamais le coffre précis ni sa position.

## Séparation public et privé

### Public

`runtime/public-save-bases.json` est synchronisé vers `portal/data/public-save-bases.json`. Il est chargé à l'ouverture de la carte ou de l'onglet `Bases et campements` d'une fiche joueur. Avec le monde actuel, il pèse environ 537 Kio brut et 46 Kio compressé.

Le fichier ne contient aucun GUID, identifiant de conteneur, identifiant Steam, mot de passe de coffre ou position exacte d'une structure. Les ressources sont fusionnées par type pour chaque base; il est impossible de retrouver le coffre précis qui contient un objet.

### Privé

`runtime/private-save-bases.json` reste sur Ubuntu avec le mode `0600`. Il contient le détail opérationnel des inventaires rattachés aux bases, notamment les emplacements, objets dynamiques et tampons de production.

Ce fichier:

- n'est pas synchronisé vers Windows;
- n'est pas monté dans Docker;
- n'est pas servi par Nginx;
- ne doit jamais être ajouté au dépôt public.

## Mesures réelles du 12 juillet 2026

Sauvegarde mesurée:

| Élément | Valeur |
|---|---:|
| `Level.sav` | 1 369 316 octets |
| Bases | 11 |
| Pals travailleurs | 113 |
| Objets de carte | 3 410 |
| Structures rattachées aux bases | 1 166 |
| Travaux décodés | 197 |
| Objets dynamiques | 611 |
| Espaces de stockage réels | 92 |

Coût des décodeurs seulement:

| Profil | Durée | Mémoire de pointe |
|---|---:|---:|
| Décodeurs historiques | 838 ms | environ 217 Mio |
| Tous les décodeurs | 951 ms | environ 232 Mio |
| Surcoût | 113 ms | environ 15 Mio |

Collecte complète incluant les profils joueurs et les projections:

| Étape | Durée observée |
|---|---:|
| Décodage | 1 052 ms |
| Projection | 296 ms |
| Total du service | 1 549 ms |

Avec une collecte complète observée entre 1,5 et 2,3 secondes, le service utilise environ `5 à 8 %` de sa fenêtre de 30 secondes, soit bien moins d'un coeur en moyenne. Sa mémoire de pointe observée demeure sous la limite systemd de 768 Mio. Le coût reste faible par rapport aux 30 Gio de mémoire du serveur; les priorités CPU et disque protègent le processus Palworld.

## Vérification

```powershell
# Afficher les diagnostics publics synchronisés
Get-Content .\portal\data\public-save-diagnostics.json | ConvertFrom-Json

# Rejouer les tests du contrat
python -m unittest server.tests.test_palworld_save_snapshot -v

# Mesurer un groupe de décodeurs sur Ubuntu, sans produire de snapshot
ssh gaylemon "/home/gaylemon/Gaylemon/vendor/PalworldSaveTools-current/.venv/bin/python /home/gaylemon/Gaylemon/server/bin/palworld-save-profile.py --stage full"

# Confirmer que le jeu n'a pas été affecté
ssh gaylemon "systemctl is-active palworld.service"
```

Le profileur n'affiche que des compteurs, histogrammes techniques, temps et mémoire. Il ne publie aucun contenu de coffre ni identifiant de sauvegarde.
