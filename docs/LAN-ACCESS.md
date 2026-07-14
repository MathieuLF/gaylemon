# Accès LAN

Le serveur s'administre par SSH avec une clé. Pas de mot de passe, pas d'API Palworld exposée au LAN.

## Depuis ce poste

```powershell
.\scripts\palworld-console.ps1 -Action CheckAccess
.\scripts\palworld-console.ps1 -Action Status
.\scripts\palworld-console.ps1 -Action Players
.\scripts\palworld-console.ps1 -Action Logs -LogMode service -Follow
```

## Ajouter un autre PC Windows

Créer une clé:

```powershell
ssh-keygen -t ed25519 -f "$env:USERPROFILE\.ssh\gaylemon_palworld_ed25519" -C "palworld-monitor"
```

Ajouter la clé publique sur le serveur depuis un poste déjà autorisé:

```powershell
Get-Content .\gaylemon_palworld_ed25519.pub | ssh gaylemon "umask 077; mkdir -p ~/.ssh; cat >> ~/.ssh/authorized_keys"
```

Configurer `$env:USERPROFILE\.ssh\config`:

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

## Logs sans copier le dépôt

```powershell
ssh gaylemon "journalctl -u palworld.service -f -o short-iso"
ssh gaylemon "journalctl -u palworld-welcome.service -f -o short-iso"
ssh gaylemon "tail -f /srv/storage/steam/servers/palworld/game/Pal/Saved/Logs/Pal.log"
```
