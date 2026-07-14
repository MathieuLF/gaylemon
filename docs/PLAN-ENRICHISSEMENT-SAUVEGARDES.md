# Plan d'action — enrichissement du parse des sauvegardes Palworld

## État d'implémentation au 12 juillet 2026

Ce document conserve le plan initial pour expliquer les décisions et les critères d'acceptation. Les cases non cochées dans les phases historiques ne constituent pas un suivi à jour; le présent état d'implémentation et les contrats versionnés font foi.

Le plan est maintenant livré sous forme d'un contrat public v3 progressif:

- phases 0 et 1 terminées: fixture anonymisée, alias de schéma, valeurs absentes à `null`, garde-fou de confidentialité, verrou anti-chevauchement, écritures atomiques et diagnostics séparés;
- phase 2 terminée pour les données dont le catalogue est fiable: Paldex, captures, boss, exploration, technologies, quêtes en total et reliques;
- phase 3 terminée: condensation, Lucky, favori, éveil/import, PV maximum calculés, SAN, âmes, statistiques calculées, attaques apprises, aptitudes de travail, santé et date d'acquisition validée;
- phases 4 et 5 livrées: bases, travailleurs, structures, travaux, objets dynamiques, coffres, stockage de guilde et recherche sont décodés; la projection publique est agrégée et le détail exact des inventaires reste privé sur Ubuntu;
- phase 6 partielle: les archives horaires compressées existent déjà; les tendances dérivées seront ajoutées seulement après plusieurs jours de données v3 stables.

Adaptations apportées pendant l'implémentation:

- le dénominateur Paldex est produit depuis les espèces affichables du catalogue livré avec la même révision de PalworldSaveTools;
- les variantes techniques sont normalisées vers leur espèce publique sans exposer leur identifiant interne;
- la projection publique ne conserve plus les coordonnées Unreal brutes, seulement les coordonnées nécessaires aux marqueurs de la carte;
- l'index initial garde uniquement les résumés de progression; les listes lourdes sont chargées à l'ouverture d'une fiche;
- les avertissements détaillés restent dans le diagnostic Ubuntu et ne sont pas présentés comme des erreurs aux joueurs.

Les contrats et les opérations sont détaillés dans `docs/SAVE-SNAPSHOT-V3.md` et `docs/SAVE-BASES-V1.md`.

## Objectif

Enrichir progressivement les données issues de `Level.sav` et des fichiers `Players/*.sav` afin d'améliorer les profils joueurs, les collections de Pals, les bases, les inventaires et les KPIs techniques du microsite.

Le plan conserve les principes actuels:

- lecture d'une copie terminée d'un backup Palworld intégré;
- aucune lecture concurrente d'un fichier que Palworld est en train d'écrire;
- aucune modification des sauvegardes;
- priorité CPU basse et priorité disque `idle`;
- projection publique fondée sur une allowlist explicite;
- exclusion permanente des identifiants joueur, Steam, guilde, instance, conteneur et objet dynamique;
- conservation du dernier snapshot public valide si une nouvelle extraction échoue;
- compatibilité avec les variantes de schéma rencontrées entre versions de Palworld.

## État de départ

Le worker actuel active seulement les décodeurs spécialisés nécessaires aux guildes, personnages et inventaires personnels. Il expose déjà:

- niveau, expérience, santé, bouclier, faim et allocations de statistiques;
- guilde, niveau du camp, nombre de bases et dernière position sauvegardée;
- Pals de l'équipe et de la Palbox;
- niveau, sexe, santé, faim, amitié, talents, passifs et attaques équipées des Pals;
- inventaire principal, objets importants, armes, équipement et nourriture;
- points technologiques, nombre de technologies débloquées et nombre de quêtes terminées.

Baseline locale observée le 12 juillet 2026:

| Élément | Taille indicative |
|---|---:|
| `public-save-index.json` | 9 274 octets |
| `public-save-snapshot.json` | 1 876 103 octets, soit 1,79 Mio |
| carte principale `T_WorldMap.webp` | 1 930 246 octets, soit 1,84 Mio |
| ressources locales PalworldSaveTools | 44,81 Mio |
| code source local PalworldSaveTools | 4,03 Mio |
| clone local complet PalworldSaveTools | 82,46 Mio |

Ces tailles sont des points de comparaison, pas des limites contractuelles. L'empreinte du clone Windows n'est pas nécessairement identique à celle de la version déployée sur Ubuntu.

## Décisions structurantes

### Ne pas produire un dump intégral

Le snapshot doit rester un modèle métier stable. Les objets Unreal bruts, octets inconnus et identifiants de liaison ne doivent jamais être recopiés tels quels dans le JSON public.

Chaque nouvelle donnée devra passer par trois couches:

1. décodage technique du save;
2. normalisation vers un modèle métier interne;
3. projection publique allowlistée sur Windows.

### Séparer progression et diagnostic technique

Les mesures de taille et de durée ne doivent pas être ajoutées directement au snapshot détaillé, car la taille du fichier deviendrait autoréférentielle. Prévoir un fichier secondaire:

```text
/home/gaylemon/Gaylemon/runtime/public-save-diagnostics.json
portal/data/public-save-diagnostics.json
```

Le premier contient les mesures internes. Le second est une projection publique limitée aux informations sans risque.

### Versionner les contrats JSON

Faire évoluer le snapshot détaillé vers une nouvelle version de schéma lorsque les premières données sont intégrées:

```json
{
  "version": 3,
  "ok": true,
  "summary": {},
  "world": {},
  "parser": {},
  "guilds": [],
  "bases": [],
  "players": []
}
```

Le navigateur doit accepter la version précédente pendant le déploiement progressif. Les nouveaux panneaux restent masqués ou affichent « En attente de la prochaine analyse » lorsqu'un champ est absent.

## Ordre d'intégration recommandé

1. Instrumentation et KPIs de taille.
2. Paldex, captures, boss, exploration, reliques et progression détaillée.
3. Détails avancés des Pals.
4. Bases et travailleurs.
5. Inventaires dynamiques, coffres et productions.
6. Historique dérivé et optimisation finale des payloads.

Cet ordre commence par les informations à forte valeur qui sont déjà décodées dans les fichiers joueurs. Les décodeurs plus lourds de bases, travaux, objets de carte et objets dynamiques viennent ensuite.

---

## Phase 0 — contrat, fixtures et garde-fous

### Actions

- [ ] Créer une fixture anonymisée représentant un joueur, une guilde, une base, un Pal et chaque type d'inventaire.
- [ ] Établir une liste d'alias pour les propriétés ayant changé de nom ou de casse selon les versions de Palworld.
- [ ] Traiter notamment les familles versionnées comme `PlayerCaptureRecordData`, `PlayerCaptureRecordData2`, `PlayerExploreMapData` et `PlayerExploreMapData2`.
- [ ] Définir les valeurs absentes: utiliser `null` pour « inconnu » et `0` seulement pour une valeur réellement mesurée à zéro.
- [ ] Ajouter un compteur de champs ou structures non reconnus dans les diagnostics, sans publier leur contenu.
- [ ] Définir une allowlist publique par niveau: monde, guilde, base, joueur, Pal, inventaire et diagnostic.
- [ ] Ajouter un test qui échoue si un champ contenant `uid`, `guid`, `instance`, `container`, `account`, `steam`, `password`, `token` ou `dynamic_id` atteint la projection publique sans exception explicite.

### Critères de sortie

- le contrat JSON v3 est documenté;
- une version Palworld avec un champ absent ne fait pas échouer tout le snapshot;
- les données inconnues sont comptées, mais jamais publiées;
- le snapshot v2 reste lisible pendant la transition.

---

## Phase 1 — KPIs de taille et santé du parseur

### Clarifier « taille de la carte »

Trois mesures différentes doivent être distinguées dans l'interface:

1. **Sauvegarde du monde**: taille compressée de `Level.sav`. C'est la meilleure approximation de la quantité d'état persistant de la carte, mais ce n'est pas sa superficie géographique.
2. **Génération de sauvegarde**: taille de `Level.sav` additionnée à celle de tous les fichiers `Players/*.sav` sélectionnés.
3. **Carte visuelle**: dimensions et poids de `T_WorldMap.webp`. Cette image est une ressource statique du microsite et ne provient pas du save.

Ne pas afficher « taille de la carte » pour `Level.sav`; préférer « Sauvegarde du monde » afin d'éviter de laisser croire qu'il s'agit d'une distance ou d'une superficie.

### Mesures serveur à collecter à chaque parse

```json
{
  "save": {
    "levelBytes": 0,
    "playerFiles": 0,
    "playersBytes": 0,
    "generationBytes": 0,
    "backupName": "",
    "backupAgeSeconds": 0
  },
  "parse": {
    "startedAt": "",
    "completedAt": "",
    "durationMs": 0,
    "status": "ok",
    "decoderCount": 0,
    "warnings": 0,
    "playersParsed": 0,
    "palsParsed": 0,
    "basesParsed": 0
  },
  "output": {
    "snapshotBytes": 0,
    "snapshotGzipBytes": 0,
    "historyArchiveBytes": 0
  },
  "parser": {
    "name": "PalworldSaveTools",
    "commit": "",
    "installBytes": null,
    "resourcesBytes": null
  }
}
```

### Mesures Windows/microsite à collecter après la projection

```json
{
  "publicOutput": {
    "indexBytes": 0,
    "snapshotBytes": 0
  },
  "assets": {
    "worldMapBytes": 0,
    "worldMapWidth": 8192,
    "worldMapHeight": 8192,
    "treeMapBytes": 0
  }
}
```

### Règles de collecte

- [ ] Mesurer `Level.sav` et `Players/*.sav` sur la génération de backup réellement sélectionnée.
- [ ] Mesurer la durée avec une horloge monotone.
- [ ] Mesurer le snapshot après écriture atomique.
- [ ] Produire la taille gzip avec le même niveau de compression que les archives ou mesurer la réponse réellement servie par Nginx.
- [ ] Calculer la taille de l'index et du snapshot publics après la projection Windows.
- [ ] Lire les dimensions et tailles des cartes lors de leur synchronisation, pas à chaque rafraîchissement navigateur.
- [ ] Mesurer l'empreinte du parser uniquement lors de son installation ou de sa maintenance hebdomadaire; ne pas parcourir son répertoire à chaque collecte live.
- [ ] Ne jamais exposer le chemin absolu du backup ou de l'installation dans le JSON public.

### Présentation proposée dans le microsite

Ajouter un petit bloc « Données du monde » sous les KPIs principaux:

- **Sauvegarde du monde** — taille de `Level.sav`;
- **Profils joueurs** — nombre de fichiers et taille cumulée;
- **Données analysées** — taille totale de la génération;
- **Snapshot du microsite** — poids du JSON détaillé;
- **Index initial** — poids chargé au démarrage;
- **Durée d'analyse** — durée du dernier parse;
- **Fraîcheur** — âge du backup au moment du parse;
- **Carte visuelle** — `8192 × 8192` et poids du WebP;
- **Parser** — commit court de PalworldSaveTools.

L'empreinte disque complète du parser est utile pour la console d'exploitation, mais peu parlante pour les joueurs. La garder dans un détail repliable ou dans une vue technique plutôt que dans les quatre cartes principales.

### Alertes recommandées

- parse plus long que 50 % de l'intervalle du timer;
- chevauchement de deux exécutions;
- backup sélectionné anormalement ancien;
- snapshot public absent ou plus ancien que deux cycles;
- croissance soudaine de la taille du save ou du JSON;
- changement de commit du parser accompagné de nouveaux avertissements;
- nombre de joueurs, Pals ou bases tombant brutalement à zéro.

### Critères de sortie

- les tailles sont stockées en octets dans le JSON et formatées en Kio/Mio uniquement par le navigateur;
- la taille affichée correspond exactement au fichier nommé;
- aucun scan récursif coûteux n'est exécuté à chaque collecte live;
- les diagnostics survivent à un parse en échec et expliquent le dernier statut;
- l'index léger reste indépendant du snapshot complet.

---

## Phase 2 — meilleurs ajouts encore disponibles

### 2.1 Paldex et captures

#### Sources

- `RecordData.PalCaptureCount`;
- `RecordData.PaldeckUnlockFlag`;
- catalogue `characters.json` pour les noms, icônes et variantes.

#### Données cibles

```json
{
  "paldex": {
    "encounteredSpecies": 0,
    "capturedSpecies": 0,
    "totalCaptures": 0,
    "completionPercent": 0,
    "species": [
      {
        "name": "",
        "icon": "",
        "encountered": true,
        "captured": true,
        "captureCount": 0
      }
    ]
  }
}
```

#### Actions

- [ ] Normaliser les variantes normales, boss, Lucky, raid, prédateur et quête vers l'espèce affichable lorsque c'est pertinent.
- [ ] Conserver séparément le nombre total de captures et le nombre d'espèces capturées.
- [ ] Définir précisément le dénominateur du pourcentage de complétion.
- [ ] Exclure du dénominateur les personnages techniques, PNJ, variantes non capturables et entrées sans icône valide.
- [ ] Afficher les découvertes récentes à partir des archives horaires lorsque l'historique sera activé.

### 2.2 Boss et primes

#### Sources

- `RecordData.NormalBossDefeatFlag`;
- `RecordData.BossDefeatExpBonusTableIndex`;
- `boss_mapping.json`.

#### Données cibles

- nombre de boss vaincus;
- liste normalisée des boss vaincus;
- dernière nouvelle victoire déduite de l'historique;
- progression globale des boss connus;
- points technologiques de boss déjà disponibles.

### 2.3 Exploration de la carte

#### Sources

- `RecordData.FastTravelPointUnlockFlag`;
- `RecordData.FindAreaFlagMap`;
- `RecordData.UnlockedWorldMapFlags`;
- `WorldMapUISaveDataMap` pour le masque d'exploration, si une mesure plus fidèle est nécessaire;
- `fast_travel_points.json` et `world_map_areas.json`.

#### Données cibles

- points de voyage rapide débloqués et total disponible;
- zones découvertes et total disponible;
- cartes principales débloquées;
- pourcentage d'exploration;
- liste publique des points découverts, sans publier les marqueurs personnels.

Les pings et marqueurs placés manuellement par les joueurs doivent rester privés par défaut.

### 2.4 Technologies et quêtes détaillées

#### Sources

- `UnlockedRecipeTechnologyNames`;
- variantes `PlayerTechnologyData`, `PlayerTechnologyData2` et champs associés;
- `CompletedQuestArray_FullRelease`;
- autres structures contenant `CompletedQuestArray`;
- catalogue `world.json` pour les technologies.

#### Données cibles

- technologies normales et anciennes séparées;
- nom, niveau requis, icône et catégorie;
- technologies récemment débloquées;
- quêtes terminées par famille;
- identifiants de quête conservés seulement dans le modèle interne si aucun catalogue de libellés fiable n'est disponible.

Ne pas présenter une liste d'identifiants techniques bruts comme une fonctionnalité terminée. Si les quêtes ne peuvent pas être nommées correctement, conserver temporairement seulement les totaux par famille.

### 2.5 Reliques et bonus permanents

#### Sources

- `RecordData.RelicPossessNumMap`;
- `RecordData.RelicPossessNum`;
- `relic_data.json`;
- allocations de statistiques déjà décodées.

#### Données cibles

- reliques possédées par catégorie;
- rang actuel et rang maximal;
- bonus permanents lisibles;
- progression totale des reliques.

### 2.6 Guilde et activité sauvegardée

Ajouter sans nouveau décodeur lourd:

- chef de guilde;
- dernière présence enregistrée dans le save;
- nombre de membres actifs selon une fenêtre documentée;
- ancienneté de la dernière sauvegarde utilisée.

La dernière présence est une donnée plus sensible que le niveau ou le Paldex. Décider explicitement si elle est publique, arrondie par jour ou réservée à l'administration.

### Critères de sortie de la phase 2

- les compteurs Paldex concordent avec les entrées par espèce;
- aucune variante non capturable ne fausse le pourcentage;
- technologies, boss et reliques sont résolus avec un catalogue versionné;
- les quêtes gèrent plusieurs noms de propriétés sans double comptage;
- l'absence d'une famille de données n'annule pas le reste du profil.

---

## Phase 3 — beaucoup plus de détails sur les Pals

### Données à ajouter sans nouveau décodeur de monde

Les personnages sont déjà décodés. Ajouter au modèle de Pal:

```json
{
  "rank": 0,
  "lucky": false,
  "boss": false,
  "awakening": false,
  "favorite": false,
  "imported": false,
  "maxHp": 0,
  "sanity": 0,
  "souls": {
    "hp": 0,
    "attack": 0,
    "defense": 0,
    "workSpeed": 0
  },
  "computedStats": {
    "attack": null,
    "defense": null,
    "workSpeed": null
  },
  "learnedSkills": [],
  "workSuitabilityBonuses": [],
  "healthStatus": null,
  "ownedAt": null
}
```

### Correspondance des propriétés

| Information | Propriété principale |
|---|---|
| Condensation | `Rank` |
| Âmes HP | `Rank_HP` |
| Âmes attaque | `Rank_Attack` |
| Âmes défense | `Rank_Defence` |
| Âmes travail | `Rank_CraftSpeed` |
| Lucky | `IsRarePal` |
| Éveil | `bIsAwakening` |
| Favori | `FavoriteIndex` |
| Importé | `bImportedCharacter` |
| Attaques apprises | `MasteredWaza` |
| Bonus d'aptitudes | `GotWorkSuitabilityAddRankList` |
| SAN | `SanityValue` |
| Maladie/blessure | `WorkerSick`, `PhysicalHealth` |
| Date d'acquisition | `OwnedTime` |

### Actions

- [ ] Résoudre toutes les attaques apprises avec `skills.json`.
- [ ] Distinguer les attaques apprises des trois attaques équipées.
- [ ] Calculer attaque, défense et vitesse de travail avec les mêmes fonctions et catalogues que PalworldSaveTools.
- [ ] Conserver les valeurs brutes nécessaires au diagnostic uniquement dans le modèle interne.
- [ ] Exposer un résumé de santé plutôt que les enums techniques bruts.
- [ ] Valider le sens exact de `Rank` selon la version du jeu avant d'afficher un nombre d'étoiles.
- [ ] Vérifier les valeurs absentes sur les anciens Pals et les Pals importés.
- [ ] Ne pas présenter `OwnedTime` comme une date de capture certaine sans validation; utiliser « acquis le » si la donnée est cohérente.
- [ ] Ne pas publier `OldOwnerPlayerUIds`.

### Présentation proposée

- badges Lucky, boss, éveillé et favori;
- rang de condensation;
- jauges IV et améliorations par âmes séparées;
- statistiques calculées;
- toutes les attaques apprises dans un détail repliable;
- aptitudes de travail et bonus;
- état de santé uniquement pour les Pals affectés à une base, si cette visibilité est souhaitée.

### Critères de sortie

- les statistiques calculées correspondent à l'affichage de PalworldSaveTools sur la fixture et sur un vrai save en lecture seule;
- les rangs, âmes et talents ne sont pas mélangés;
- aucune date ou condition de santé invalide n'est affichée;
- le poids du profil reste maîtrisé grâce au chargement différé déjà utilisé.

---

## Phase 4 — le plus gros manque: les bases

### Décodeurs à activer progressivement

1. `BaseCampSaveData.Value.RawData`;
2. `BaseCampSaveData.Value.WorkerDirector.RawData`;
3. `CharacterContainerSaveData.Value.Slots.Slots.RawData`;
4. `BaseCampSaveData.Value.WorkCollection.RawData`;
5. `WorkSaveData`;
6. `MapObjectSaveData`;
7. `GuildExtraSaveDataMap.Value.GuildItemStorage.RawData`;
8. `GuildExtraSaveDataMap.Value.Lab.RawData`.

Activer et mesurer un groupe à la fois. Ne pas passer immédiatement au décodage complet des objets de carte.

### Étape 4A — identité et position des bases

Ajouter:

- nom de la base;
- guilde associée;
- position transformée pour la carte principale ou la Tree Map;
- rayon de la base;
- état de la base;
- nombre de travailleurs affectés;
- niveau de camp déjà disponible.

Proposition de modèle public:

```json
{
  "name": "",
  "guild": "",
  "campLevel": 0,
  "position": {},
  "areaRange": 0,
  "workers": {
    "assigned": 0,
    "healthy": 0,
    "unwell": 0
  }
}
```

La publication de la position exacte des bases doit être une décision explicite. Une position arrondie ou seulement un marqueur sur la carte peut suffire.

### Étape 4B — travailleurs

- [ ] Relier le conteneur du `WorkerDirector` aux slots de `CharacterContainerSaveData`.
- [ ] Relier chaque `instance_id` à son entrée de `CharacterSaveParameterMap` dans le modèle interne.
- [ ] Ne jamais publier cet `instance_id`.
- [ ] Réutiliser les détails avancés de la phase 3.
- [ ] Exposer les aptitudes, SAN, faim, santé et tâche actuelle.
- [ ] Distinguer Palbox, équipe, base, cage d'exposition, marchand et conteneurs inconnus.
- [ ] Corriger le total global des Pals afin de documenter clairement s'il compte ou non les travailleurs de base.

### Étape 4C — structures et production

Après validation des performances de `MapObjectSaveData` et `WorkSaveData`, ajouter:

- nombre de structures par catégorie;
- bâtiments importants construits;
- structures endommagées;
- constructions inachevées;
- productions et travaux en cours;
- progression, quantité de travail requise et Pals affectés;
- postes sans travailleur compatible;
- laboratoires et recherche de guilde en cours.

La première projection publique doit rester agrégée. Les détails complets des coffres, postes et productions conviennent mieux à une vue privée ou administrative.

### Étape 4D — recherches de guilde

Ajouter:

- recherche actuelle;
- recherches terminées;
- progression si elle est disponible et comprise;
- catalogue de noms et descriptions lorsque les ressources permettent une résolution stable.

### Performance et mémoire

- [ ] Mesurer séparément chaque nouveau décodeur.
- [ ] Journaliser nombre d'entrées et durée, pas le contenu des entrées.
- [ ] Construire des index en mémoire par GUID une seule fois, puis supprimer les GUID de la projection.
- [ ] Éviter les boucles joueur × tous les Pals × toutes les bases.
- [ ] Refuser le chevauchement de deux workers avec un verrou explicite.
- [ ] Garder la durée totale sous 50 % de l'intervalle live; viser moins de 15 secondes avec la sauvegarde réelle.
- [ ] Prévoir la possibilité de produire les détails lourds moins souvent que le profil joueur.

### Critères de sortie

- chaque base est rattachée à la bonne guilde;
- chaque travailleur est compté une seule fois;
- les coordonnées fonctionnent sur la carte principale et la Tree Map;
- l'échec du décodage d'un objet de carte ne supprime pas les bases déjà extraites;
- le coût du parse reste compatible avec le timer;
- aucun identifiant de liaison n'apparaît dans le JSON public.

---

## Phase 5 — inventaires plus précis

### Étape 5A — compléter les inventaires personnels

Ajouter le conteneur temporaire `DropSlotContainerId` et documenter sa sémantique. Ne pas l'afficher comme un inventaire permanent si son contenu est transitoire.

### Étape 5B — objets dynamiques

Activer `DynamicItemSaveData.DynamicItemSaveData.RawData` afin d'enrichir les objets qui ont un identifiant dynamique.

Données disponibles selon le type:

- durabilité des armes et armures;
- munitions encore chargées;
- passifs propres à certaines armes;
- espèce et propriétés contenues dans les œufs;
- données inconnues conservées seulement pour le diagnostic local.

Proposition de modèle:

```json
{
  "name": "",
  "count": 1,
  "rarity": 0,
  "condition": {
    "durability": null,
    "durabilityPercent": null,
    "remainingBullets": null
  },
  "passives": [],
  "egg": {
    "species": null,
    "icon": null
  }
}
```

Le pourcentage de durabilité ne doit être calculé que si une durabilité maximale fiable est disponible dans les catalogues.

### Étape 5C — coffres de base et stockage de guilde

- [ ] Relier les modules `ItemContainer` des objets de carte aux `ItemContainerSaveData`.
- [ ] Relier le stockage de guilde à son conteneur.
- [ ] Grouper les ressources par base, catégorie et objet.
- [ ] Calculer capacité, emplacements utilisés et emplacements libres.
- [ ] Prévoir une projection publique agrégée et une projection privée détaillée.
- [ ] Ne jamais publier les identifiants des coffres ou objets dynamiques.

Projection publique recommandée:

- nombre de coffres;
- capacité totale et utilisation;
- totaux par grandes catégories;
- ressources les plus abondantes seulement si ce niveau de visibilité est accepté.

Projection privée/admin possible:

- contenu exact de chaque coffre;
- emplacement du coffre;
- durabilité et propriétés exactes des équipements;
- recherche d'un objet dans toutes les bases.

### Étape 5D — œufs et production

Lorsque les objets dynamiques et travaux sont tous deux disponibles:

- œufs présents dans les inventaires;
- espèce contenue lorsque le save l'expose;
- incubateurs et productions en cours;
- travaux terminés en attente de collecte;
- aucune promesse de filiation génétique tant que les parents ne sont pas explicitement et fiablement présents dans le save.

### Critères de sortie

- chaque objet dynamique est relié au bon slot sans publier son ID;
- les quantités agrégées restent identiques à l'inventaire actuel;
- les objets sans donnée dynamique continuent de s'afficher;
- un type dynamique inconnu est ignoré proprement et compté dans les diagnostics;
- les coffres privés ne deviennent pas publics par simple ajout d'un champ interne.

---

## Phase 6 — historique et informations dérivées

Les archives horaires existantes peuvent fournir davantage de valeur que certains champs bruts.

### Données dérivables

- niveaux gagnés sur 24 heures, 7 jours et 30 jours;
- nouveaux Pals et nouvelles espèces;
- nouvelles entrées du Paldex;
- boss nouvellement vaincus;
- technologies et quêtes nouvellement terminées;
- évolution du nombre de bases et travailleurs;
- croissance de `Level.sav` et de la génération complète;
- croissance du snapshot et temps de parse;
- records hebdomadaires sans exposer d'identifiants techniques.

### Actions

- [ ] Calculer les deltas côté serveur à partir d'archives validées.
- [ ] Ne pas synchroniser toutes les archives vers le navigateur.
- [ ] Publier seulement un résumé de tendances.
- [ ] Gérer les diminutions dues à une restauration de backup, une suppression ou un changement de schéma.
- [ ] Marquer une rupture de série lors d'un changement de version incompatible du parser.

---

## Stratégie d'affichage et de chargement

### Index initial

Conserver dans `public-save-index.json` uniquement:

- résumé global;
- cartes joueurs;
- quelques compteurs Paldex;
- positions nécessaires à la carte;
- KPIs de taille strictement nécessaires à la vue d'ensemble.

Ne jamais y ajouter les collections détaillées, attaques apprises, inventaires, travailleurs ou structures.

### Snapshot détaillé

Charger à l'ouverture d'un profil ou d'une base:

- progression détaillée;
- Paldex par espèce;
- détails avancés des Pals;
- inventaires personnels.

### Données de base lourdes

Si le snapshot devient trop gros, produire un fichier séparé:

```text
public-save-bases.json
```

Il serait chargé seulement à l'ouverture de la carte ou de la section des bases. La projection doit être atomique et porter la même révision que l'index afin d'éviter de mélanger deux générations.

## Budgets et seuils à valider

| Élément | Cible initiale |
|---|---:|
| Durée du parse complet | moins de 50 % de l'intervalle du timer |
| Objectif de durée si réaliste | moins de 15 secondes |
| Chevauchements | 0 |
| Index initial | rester inférieur à 100 Kio |
| Identifiants techniques publics | 0 |
| Échecs supprimant le dernier snapshot valide | 0 |
| Données lourdes chargées au démarrage | 0 |

La taille maximale du snapshot détaillé devra être fixée après mesure des phases 3 à 5. Il vaut mieux séparer les bases dans un second fichier que compresser artificiellement un modèle devenu trop volumineux.

## Validation requise à chaque tranche

### Parseur

- [ ] tests unitaires sur fixtures anonymisées;
- [ ] test des champs absents et variantes de casse;
- [ ] test de non-régression du schéma public;
- [ ] test de confidentialité de l'allowlist;
- [ ] lecture réelle d'un backup copié, sans écriture dans le save;
- [ ] comparaison des totaux avec PalworldSaveTools;
- [ ] mesure CPU, mémoire, I/O, durée et taille des sorties.

### Projection Windows

- [ ] rejet des champs inattendus provenant du worker Ubuntu;
- [ ] conservation de `null` pour les valeurs inconnues;
- [ ] écriture atomique de tous les JSON publics;
- [ ] contrôle qu'aucun ID technique n'est présent;
- [ ] contrôle du poids de l'index et du snapshot.

### Microsite

- [ ] affichage correct avec le schéma v2 et le schéma v3;
- [ ] états chargement, absent, partiel et erreur;
- [ ] formatage accessible des tailles et durées;
- [ ] navigation clavier et libellés lisibles;
- [ ] chargement différé vérifié dans le navigateur;
- [ ] aucune régression de la carte, des profils ouverts ou du rafraîchissement en arrière-plan.

## Déploiement progressif

Pour chaque phase:

1. intégrer le décodage derrière un champ de schéma nouveau;
2. exécuter les tests sur fixtures;
3. analyser un vrai backup en lecture seule vers un fichier candidat distinct;
4. comparer nombres, tailles, durée et avertissements;
5. vérifier manuellement la projection publique;
6. déployer le worker sans activer immédiatement le panneau public;
7. observer plusieurs cycles de 30 secondes;
8. activer l'interface seulement après stabilité;
9. conserver un retour simple au snapshot précédent.

## Définition globale de « terminé »

Le chantier est terminé lorsque:

- les ajouts de progression, Pals, bases et inventaires sont normalisés et documentés;
- les tailles de `Level.sav`, des fichiers joueurs, du snapshot, de l'index et des cartes sont mesurées sans ambiguïté;
- la durée et la santé du parse sont visibles;
- les payloads lourds restent chargés à la demande;
- les résultats concordent avec PalworldSaveTools sur un vrai save;
- aucune donnée technique ou secrète n'atteint le microsite;
- un changement ou une anomalie de schéma dégrade seulement la section concernée;
- le worker reste strictement en lecture seule vis-à-vis des sauvegardes Palworld.
