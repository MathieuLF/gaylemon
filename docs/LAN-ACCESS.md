# Accès depuis un autre ordinateur du LAN

Le serveur est administré par SSH avec une clé, pas par mot de passe. C'est volontaire.

## Option simple

Depuis cet ordinateur-ci, les scripts du dossier fonctionnent déjà:

```powershell
.\scripts\palworld-console.ps1
.\scripts\palworld-console.ps1 -Action CheckAccess
.\scripts\palworld-console.ps1 -Action Status
.\scripts\palworld-console.ps1 -Action Logs -LogMode service -Follow
.\scripts\palworld-console.ps1 -Action Logs -LogMode game -Follow
.\scripts\palworld-console.ps1 -Action Logs -LogMode welcome -Follow
.\scripts\palworld-console.ps1 -Action Players
```

## Ajouter un autre ordinateur Windows

Sur l'autre ordinateur, installer ou activer le client OpenSSH, puis générer une clé:

```powershell
ssh-keygen -t ed25519 -f "$env:USERPROFILE\.ssh\gaylemon_palworld_ed25519" -C "palworld-monitor"
```

Récupérer le contenu du fichier public:

```powershell
Get-Content "$env:USERPROFILE\.ssh\gaylemon_palworld_ed25519.pub"
```

Depuis un ordinateur qui a déjà accès à `gaylemon`, ajouter cette clé publique au serveur:

```powershell
Get-Content .\gaylemon_palworld_ed25519.pub | ssh gaylemon "umask 077; mkdir -p ~/.ssh; cat >> ~/.ssh/authorized_keys"
```

Sur le nouvel ordinateur, créer ou modifier `$env:USERPROFILE\.ssh\config`:

```sshconfig
Host gaylemon
  HostName 192.168.1.50
  User gaylemon
  IdentityFile ~/.ssh/gaylemon_palworld_ed25519
  IdentitiesOnly yes
  StrictHostKeyChecking accept-new
```

Tester:

```powershell
ssh gaylemon "hostname && systemctl is-active palworld.service"
```

## Suivre les logs depuis cet autre ordinateur

Sans copier tout le dossier, les commandes directes suffisent:

```powershell
ssh gaylemon "journalctl -u palworld.service -f -o short-iso"
ssh gaylemon "journalctl -u palworld-welcome.service -f -o short-iso"
ssh gaylemon "tail -f /srv/storage/steam/servers/palworld/game/Pal/Saved/Logs/Pal.log"
ssh gaylemon "systemctl status palworld.service --no-pager -l"
```

Si tu copies ce dossier sur l'autre ordinateur, tu peux aussi utiliser les scripts PowerShell:

```powershell
.\scripts\palworld-console.ps1 -Action CheckAccess
.\scripts\palworld-console.ps1 -Action Logs -LogMode service -Follow
.\scripts\palworld-console.ps1 -Action Status
.\scripts\palworld-console.ps1 -Action Metrics
```
