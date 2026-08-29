# Développement

## Préparer le projet

```powershell
git clone https://github.com/MathieuLF/gaylemon.git
Set-Location .\gaylemon
Copy-Item .env.example .env
npm ci
```

Les exemples sous `portal/data` sont fictifs. Les données réelles, secrets, domaines, chemins et fichiers d’exploitation restent hors du dépôt.

## Valider

```powershell
.\scripts\upgrade-preflight.ps1 -Mode Inventory
.\scripts\verify-local.ps1 -Mode Quick
.\scripts\verify-local.ps1 -Mode Full
```

Quick exécute les tests Go, le contrat du portail, la frontière publique et le reçu local. Full ajoute PostgreSQL 16 isolé, navigateur/Axe, race, deadcode, vulnérabilités, SBOM et image signée.

## Exécuter le service web

```powershell
go run ./cmd/gaylemon-web
```

Le service lit `GAYLEMON_PORTAL_ROOT`, calcule les noms hachés de CSS et JavaScript, puis sert `/assets-manifest.json`. Une modification de ces fichiers doit changer leur chemin public sans exiger de vider le cache du navigateur.

## Changer un contrat public

Adapter ensemble le modèle Go, la projection, l’exemple JSON, le portail, les tests et la documentation. Une génération partielle ne doit jamais devenir active. Les champs inconnus restent absents ou `null`; aucune relation ne doit être inventée.
