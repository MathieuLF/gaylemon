# Publication du dépôt Gaylémon

## Contenu publiable

Le dépôt public contient:

- le code PowerShell, Python, Bash, HTML, CSS et JavaScript;
- les unités `systemd` et exemples de configuration;
- les contrats et fixtures fictives;
- la documentation;
- les polices et leur licence;
- les illustrations propres à Gaylémon, dont le favicon et la carte sociale;
- les manifestes et verrous des dépendances externes;
- la configuration Nginx et Compose du microsite.

La structure complète du microsite est donc versionnable: `portal/index.html`, `portal/assets/`, sa logique JavaScript, ses styles, Nginx et `compose.yaml`. Les fichiers JSON réels synchronisés depuis Ubuntu et les ressources extraites du jeu restent locaux; leurs contrats fictifs `*.example.json` permettent de développer le site depuis un clone public.

## Contenu local exclu

- `.env` et variantes locales;
- `config/local/`;
- `portal/data/*.json`, sauf `*.example.json`;
- `portal/data/players/`;
- journaux et PID;
- `portal/joueur/`, généré dynamiquement;
- `portal/assets/game/`, issu des ressources du jeu;
- `runtime/`, incluant audits, historiques, archives et préproductions;
- `vendor/PalworldSaveTools/` et environnements virtuels;
- caches Python, sorties Playwright et dépendances Node;
- clés, certificats et archives.

## Avant le premier envoi

Le répertoire local n’est pas automatiquement publié. Tant qu’aucun dépôt distant n’est configuré et qu’aucun commit n’est poussé, GitHub ne contient pas les changements locaux, même si tous les fichiers sources sont prêts à être versionnés.

```powershell
.\scripts\valider-depot.ps1
.\scripts\auditer-source-ubuntu.ps1
git status --short
git status --ignored --short
git ls-files --cached --others --exclude-standard
```

Inspecter la dernière commande. Elle représente ce qui peut entrer dans Git, même avant le premier commit.

Vérifier notamment l'absence de:

- mot de passe Palworld;
- URL Push Uptime Kuma contenant un jeton;
- jeton Cloudflare;
- clé SSH;
- sauvegarde ou profil réel;
- adresse IP publique;
- export brut de l'API REST.

La carte sociale versionnée doit rester autonome et ne jamais incorporer de carte, icône ou image extraite de Palworld. Le validateur bloque toute référence de cette carte vers `portal/assets/game/`.

## Créer le dépôt GitHub

Une fois les validations réussies et le nom public confirmé:

```powershell
git branch -M main
git add --all
git commit -m "Publication initiale de Gaylémon"
gh repo create MathieuLF/Gaylemon --public --source . --remote origin --push
```

La création du dépôt est une action publique irréversible au sens où les fichiers poussés deviennent immédiatement consultables. Relire la liste publiable et le premier commit avant d'exécuter `gh repo create`.

Après le premier push:

1. vérifier le succès du workflow `Validation`;
2. activer **Private vulnerability reporting** dans les paramètres de sécurité du dépôt;
3. vérifier les formulaires d'issue et le lien de signalement privé;
4. définir la description, le site `https://gaylemon.mathieu.pro/` et les sujets du dépôt;
5. vérifier que le badge de validation du README est vert;
6. créer une première version seulement lorsqu'un point de restauration stable est identifié.

## Données du microsite

Les fichiers `public-*` produits en exploitation sont conçus pour être servis publiquement, mais ils ne sont pas versionnés. Le dépôt fournit des variantes fictives `*.example.json` pour le développement.

Une copie fraîche peut créer les noms canoniques sans écraser de données:

```powershell
.\scripts\initialiser-projet.ps1
```

## Ressources Palworld

Les icônes, cartes et autres ressources du jeu sont générées localement:

```powershell
.\scripts\sync-palworld-game-assets.ps1
```

Elles restent sous `portal/assets/game/` et hors du dépôt public.

## Historique Git

Une valeur secrète ajoutée puis supprimée demeure dans l'historique. Si cela arrive:

1. révoquer la valeur;
2. créer un nouveau secret;
3. nettoyer l'historique avant publication;
4. vérifier tous les clones et archives concernés.

## Infrastructure externe

Le dépôt documente les points d'intégration Uptime Kuma et cloudflared. Il ne doit contenir ni leurs volumes, ni leurs bases, ni leurs jetons, ni leur Compose partagé.

## Dépendances externes

Le fork PalworldSaveTools demeure dans son propre dépôt GitHub. Gaylémon publie son URL et la révision validée sous `dependencies/`, mais exclut le clone `vendor/PalworldSaveTools/`.

Les binaires SteamCMD et Palworld ne sont pas ajoutés à Git. Leurs scripts d'installation, de lancement, de mise à jour et de sauvegarde le sont.
