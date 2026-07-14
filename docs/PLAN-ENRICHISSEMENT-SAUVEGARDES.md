# Journal enrichi depuis les sauvegardes

Ce document garde le cap du chantier d'enrichissement. Les contrats actifs sont dans [SAVE-SNAPSHOT-V3.md](SAVE-SNAPSHOT-V3.md) et [SAVE-BASES-V1.md](SAVE-BASES-V1.md).

## État actuel

Le parse des sauvegardes publie maintenant un contrat public v3:

- profils joueurs, Paldex, boss, quêtes, technologies, reliques et exploration;
- Pals détaillés, inventaires personnels et progression fiable;
- bases, travailleurs, structures, stockages et productions;
- diagnostics publics légers;
- journal d'événements enrichi.

Le microsite charge un index léger au départ, puis les fichiers plus lourds seulement quand un joueur ouvre une fiche, une base ou le terminal.

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

Les événements v3 gardent une clé publique stable, un titre narratif, une icône, un corps court, des puces et des détails publics filtrés.

Exemples de rendu visé:

```text
Mathieu agrandit la base principale
+20 murs
+4 fondations
+2 portes
```

```text
Brian termine une nouvelle chaîne de production
3 fours
2 lignes électriques
1 convoyeur
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

Exports attendus:

```text
public-events.json
public-events-recent.json
```

Le navigateur charge l'historique complet une seule fois, puis interroge le fichier récent toutes les 75 secondes et fusionne par `key`.

La page ne doit pas perdre:

- recherche;
- filtres;
- pagination;
- position de défilement;
- consultation d'une page historique.

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
