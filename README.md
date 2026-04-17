# do-backup

Interaktivna skripta za avtomatski backup oddaljenega strežnika. Ena skripta, en ukaz - vse nastavi sama.

Podpira **Linux** in **Windows**, s tremi načini prenosa: **rsync+SSH**, **SFTP** in **FTP**.

## Primerjava protokolov

| | rsync+SSH (Linux) | SFTP (Linux + Windows) | FTP (Linux + Windows) |
|---|---|---|---|
| Inkrementalni sync | Da | Ne | Da (lftp/mirror) |
| Odkrivanje baz (PostgreSQL, MySQL) | Da | Ne | Ne |
| Docker Compose konfigi | Da | Ne | Ne |
| Brez gesla (SSH ključ) | Da | Da | Ne |
| Custom pot | Da | Da | Da |
| Potrebuje na strežniku | SSH + rsync | SSH/SFTP | FTP |

**Priporočilo:** Če imate SSH dostop, uporabite **rsync+SSH** (Linux) ali **SFTP** (Windows). FTP uporabite samo če SSH ni na voljo (npr. NAS z samo FTP).

## Hitri start

### Linux

```bash
# Opcija A: git clone
git clone https://github.com/Dzo4e2250/do-backup.git
cd do-backup

# Opcija B: samo skripto
curl -O https://raw.githubusercontent.com/Dzo4e2250/do-backup/main/backup-setup.sh

# Poženi
chmod +x backup-setup.sh
./backup-setup.sh
```

### Windows

```powershell
# Opcija A: git clone
git clone https://github.com/Dzo4e2250/do-backup.git
cd do-backup

# Opcija B: samo skripto
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/Dzo4e2250/do-backup/main/backup-setup.ps1" -OutFile "backup-setup.ps1"

# Poženi (kot Administrator za Task Scheduler)
PowerShell -ExecutionPolicy Bypass -File backup-setup.ps1
```

## Kako izgleda?

### Linux (rsync+SSH)

```
============================================================
  AVTOMATSKI BACKUP SETUP
============================================================

Ta skripta nastavi avtomatski dnevni backup z oddaljenega streznika.

[1/7] Nacin prenosa

    1) rsync + SSH (priporoceno) - polna funkcionalnost
    2) SFTP (SSH port) - samo prenos datotek
    3) FTP - samo prenos datotek

  Izbira [1]: 1
  ✓ Protokol: rsync

[2/7] Preverjam odvisnosti...
  ✓ Package manager: apt
  ✓ rsync ze namescen
  ✓ sshpass ze namescen
  ✓ Vse odvisnosti OK

[3/7] Podatki o oddaljenem strezniku

  IP naslov ali hostname streznika: 203.0.113.50
  SSH uporabnisko ime [root]: root
  SSH geslo: ****
  SSH port [22]: 22

  ✓ Povezava uspesna! Streznik: my-server

[4/7] Kaj zelis backupirati?

    1) Obstoječi backupi: /root/backups/supabase (246M)
    2) PostgreSQL baza (container: supabase-db)
    3) Docker Compose konfiguracije
    4) Vpisi svojo pot (custom)

  Izbira: 1,2
  ✓ Izbrano: Obstoječi backupi
  ✓ Izbrano: PostgreSQL baza

[5/7] Kam shraniti backupe?
  ...

[6/7] Nastavljam avtentikacijo...
  ✓ SSH brez gesla deluje!

[7/7] Ustvarjam backup skripto...
  ✓ Skripta ustvarjena
  ✓ Cron nastavljen: vsak dan ob 4:00
```

### Windows (SFTP)

```
============================================================
  AVTOMATSKI BACKUP SETUP (Windows)
============================================================

[1/7] Nacin prenosa

    1) SFTP (priporoceno) - potrebuje OpenSSH
    2) FTP - vgrajen v Windows

  Izbira [1]: 1
  [OK] Protokol: sftp

[2/7] Preverjam odvisnosti...
  [OK] OpenSSH najden
  [OK] Vse odvisnosti OK

[3/7] Podatki o oddaljenem strezniku
  ...

[4/7] Kaj zelis backupirati?
  Pot na strezniku (npr: /volume1/web): /volume1/web
  [OK] Dodano: /volume1/web

[5/7] Kam shraniti backupe?
  ...

[6/7] Nastavljam avtentikacijo...
  [OK] SSH kljuc ustvarjen

[7/7] Ustvarjam backup skripto...
  [OK] Task Scheduler nastavljen: vsak dan ob 4:00
```

## Po namestitvi

### Linux - uporabni ukazi

```bash
# Ročno poženi backup
~/backups/my-server/run_backup.sh

# Poglej log
cat ~/backups/my-server/backup.log

# Poglej backupe
ls -lh ~/backups/my-server/

# Poglej cron
crontab -l

# Odstrani avtomatski backup
crontab -l | grep -v run_backup | crontab -
```

### Windows - uporabni ukazi

```powershell
# Ročno poženi backup
& "$env:USERPROFILE\backups\my-server\run_backup.ps1"

# Poglej log
Get-Content "$env:USERPROFILE\backups\my-server\backup.log"

# Poglej backupe
Get-ChildItem "$env:USERPROFILE\backups\my-server"

# Odpri Task Scheduler
taskschd.msc

# Odstrani task
Unregister-ScheduledTask -TaskName "Backup-my-server"
```

## Struktura backupov

```
~/backups/my-server/              (Linux)
%USERPROFILE%\backups\my-server\  (Windows)
├── run_backup.sh / .ps1          # Backup skripta (avtogenerirana)
├── backup.log                    # Log vseh backupov
├── database/                     # PostgreSQL/MySQL dumpi (samo rsync)
│   ├── postgres_20260314_0400.sql.gz
│   └── ...
├── web/                          # Rsync/SFTP/FTP prenosi
│   └── ...
└── configs/                      # Docker Compose konfigi (samo rsync)
    └── ...
```

## Kaj backupira?

### rsync+SSH (Linux) - polna funkcionalnost

| Tip | Kako | Rotacija |
|-----|------|----------|
| **PostgreSQL** | `pg_dumpall` preko Docker exec | Po dnevih |
| **MySQL/MariaDB** | `mysqldump` preko Docker exec | Po dnevih |
| **Obstoječe backup mape** | `rsync` (inkrementalno) | Rsync sync |
| **Docker Compose konfigi** | `tar` vseh docker-compose.yml | Po dnevih |
| **Custom pot** | `rsync` (inkrementalno) | Rsync sync |

### SFTP (Linux + Windows)

| Tip | Kako | Rotacija |
|-----|------|----------|
| **Custom pot** | `sftp get -r` (Linux) / `sftp.exe` batch (Windows) | Po dnevih |

### FTP (Linux + Windows)

| Tip | Kako | Rotacija |
|-----|------|----------|
| **Custom pot** | `lftp mirror` (Linux) / PowerShell .NET (Windows) | Po dnevih |

## Zahteve

### Linux

- Katerakoli distribucija (apt, dnf, yum, pacman, zypper, apk)
- `sudo` dostop (za namestitev paketov)
- SSH ali FTP dostop do oddaljenega strežnika

Skripta sama namesti potrebne pakete glede na izbrani protokol.

### Windows

- Windows 10+ (za OpenSSH in curl.exe)
- **SFTP:** OpenSSH Client (Settings → Apps → Optional Features → OpenSSH Client)
- **FTP:** Vgrajen v PowerShell (ni dodatnih zahtev)
- Administrator pravice (za Task Scheduler)

## Varnost

- **rsync/SFTP:** SSH ključ se shrani v `~/.ssh/id_ed25519_backup` — geslo se ne shrani
- **FTP:** Uporabniško ime in geslo sta shranjena v backup skripti — skripta ima pravice 600
- Vsi nadaljnji backupi (rsync/SFTP) uporabljajo SSH ključ brez gesla
- Backup skripta ne potrebuje root pravic na lokalnem računalniku

**Priporočilo:** Izogibajte se FTP če je mogoče. SFTP je varnejši (šifrirano) in ne shranjuje gesel.

## Uporaba z USB

```bash
# Linux
cp backup-setup.sh /media/usb/
# Na novem računalniku:
chmod +x /media/usb/backup-setup.sh && /media/usb/backup-setup.sh

# Windows
copy backup-setup.ps1 E:\
# Na novem računalniku (PowerShell):
PowerShell -ExecutionPolicy Bypass -File E:\backup-setup.ps1
```

## Licenca

MIT
