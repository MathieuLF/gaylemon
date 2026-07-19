# Journal enrichi depuis les sauvegardes

Ce document garde le cap du chantier d'enrichissement. Les contrats actifs sont dans [SAVE-SNAPSHOT-V3.md](SAVE-SNAPSHOT-V3.md), [SAVE-BASES-V1.md](SAVE-BASES-V1.md) et [EVENEMENTS-PUBLICS-V6.md](EVENEMENTS-PUBLICS-V6.md).

## État actuel

Le parse des sauvegardes publie maintenant un contrat public v3:

- profils joueurs, Paldex, boss, quêtes, technologies, reliques et exploration;
- Pals détaillés, inventaires personnels et progression fiable;
- bases, travailleurs, structures, stockages et productions;
- diagnostics publics légers;
- journal d'événements enrichi, matérialisé dans SQLite et publié en fragments immuables derrière le terminal.

Le microsite charge un index léger au départ, puis les fichiers plus lourds seulement quand un joueur ouvre une fiche, une base ou le terminal. Les fiches joueurs peuvent exporter un JSON d'analyse à partir des données publiques déjà chargées.

## Événements publiés

Types utiles:

- `craft`
- `build`
- `production`
- `hatch`
- `fishing`
- `research`
- `base`
- `repair`
- types historiques conservés quand ils restent fiables
- `join`, `leave` et `reconnect` pour les mouvements de joueurs

Les événements publiés gardent une clé publique stable, un titre narratif, une icône, un corps court, des puces et des détails publics filtrés.

Exemples de rendu visé:

```text
Mathieu agrandit la base principale
+20 murs
+4 fondations
+2 portes
```

```text
Brian présente une variation de stock à Atelier du nord
40 ressources supplémentaires sont observées. Stock observé: 180.
+40 Lingot
```

Le ton doit rester vivant, mais jamais inventé.

## Règles de confiance

Publier seulement ce qui est relié avec certitude.

Autorisé:

- crafts personnels avec objet, quantité, icône et total cumulé;
- constructions groupées par sauvegarde, joueur confirmé et base;
- productions confirmées avec poste, recette, quantité, début et fin lorsque disponibles;
- éclosions seulement si incubateur, Pal et propriétaire sont reliés;
- pêche, recherches, nouvelles bases, niveaux de camp et réparations fiables.

Exclu:

- destructions;
- transferts;
- récoltes;
- coffres ouverts;
- butins aléatoires non attribuables;
- propriétaires supposés;
- détails de coffre ou d'objet dynamique;
- identifiants techniques publics.

Les empreintes privées restent dans SQLite. Le public reçoit seulement une clé stable non réversible.

## Backfill

Le collecteur peut rejouer les sauvegardes disponibles depuis le 9 juillet 2026.

Contraintes:

- une sauvegarde à la fois;
- checkpoint de reprise;
- pas de doublons;
- priorité basse;
- aucun redémarrage de `palworld.service`.

Avant chaque sauvegarde, le worker doit suspendre le backfill si:

- FPS < 50;
- frame time > 22 ms;
- charge > 4,5.

Il reprendra au prochain passage.

## Données publiques

Exports actifs:

```text
public-events-head-v6.json
public-events-manifest-v6.json
public-events-v6/{generationId}/{jour}.json
public-daily/{generationId}/{jour}.json
public-events.json
public-events-recent.json
public-events-index.json
public-events-page-0001.json
```

Le navigateur sonde le petit pointeur v6, valide le manifeste et la tête d'une même génération, puis charge seulement la journée consultée. Il ne charge plus l'historique complet sur une route normale. Les contrats paginés v5 restent disponibles uniquement comme repli temporaire.

La page ne doit pas perdre:

- recherche;
- filtres;
- navigation par date et curseur;
- position de défilement;
- consultation d'une page historique.

Sur `/terminal`, les filtres restent masqués par défaut et la taille de page s'adapte à la hauteur disponible pour éviter un scroll de terminal en plus du scroll de page.

Les événements de bases doivent utiliser un libellé relatif au joueur quand possible. Exemple: si le joueur concerné possède trois bases, l'écho doit dire `Base 1`, `Base 2` ou `Base 3` selon ses bases à lui, même si la sauvegarde globale les nomme `Base 6` ou `Base 11`. Le backfill `baseLabelBackfill` est responsable de normaliser l'historique quand la correspondance est retrouvable.

## Validation

Tests à garder:

- crafts exacts;
- constructions groupées;
- productions confirmées;
- éclosions strictes;
- reprise checkpoint sans doublons;
- projection PowerShell sans fuite d'identifiants;
- journal compact du tableau de bord;
- terminal desktop, tablette et mobile;
- rafraîchissement sans rechargement complet.

Commandes locales:

```powershell
.\scripts\valider-depot.ps1
python -m unittest discover -s .\server\tests -v
node --check .\portal\assets\app.js
docker compose config
```

En exploitation, comparer PID, heure de démarrage et FPS de Palworld avant, pendant et après le backfill.
