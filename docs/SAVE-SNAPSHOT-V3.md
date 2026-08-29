# Snapshot public v3

Le snapshot public est une projection filtrée d’une copie cohérente des données du jeu. Le dépôt ne contient ni le collecteur propre à une instance, ni les sauvegardes sources, ni leurs chemins.

## Contrats

- `public-save-index.json` : index léger et génération active;
- `public-save-snapshot.json` : projection publique complète;
- `public-save-bases.json` : bases et ressources agrégées;
- `public-save-diagnostics.json` : fraîcheur et état de la projection;
- `players/{slug}.json` : fiche publique chargée à la demande.

Tous les documents portent le même `generationId`. L’index devient actif en dernier. Le portail refuse un document dont la génération diffère et conserve la dernière génération complète.

## Confidentialité

La projection exclut identifiants techniques, coordonnées brutes, chemins, secrets et détails de stockage privés. Les valeurs inconnues restent `null`; zéro demeure une vraie mesure à zéro.

## Validation

```powershell
go test ./internal/collector ./internal/projection
node --test .\portal\tests\portal-v6-static.test.mjs
```
