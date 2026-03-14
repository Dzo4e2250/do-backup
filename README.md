# do-backup

Interaktivna skripta za avtomatski backup oddaljenega Linux strežnika. Ena skripta, en ukaz - vse nastavi sama.

## Kaj naredi?

- Namesti manjkajoče orodje (rsync, sshpass, openssh, cron)
- Odkrije kaj je na strežniku (PostgreSQL, MySQL, Docker Compose, obstoječi backupi)
- Ustvari SSH ključ za avtomatsko povezavo (brez gesel)
- Nastavi dnevni/urni backup s cron jobom
- Požene prvi backup takoj

Podpira: **Ubuntu/Debian, Fedora/RHEL, Arch, openSUSE, Alpine**

## Hitri start

### 1. Prenesi skripto

```bash
# Opcija A: git clone
git clone https://github.com/Dzo4e2250/do-backup.git
cd do-backup

# Opcija B: samo skripto
curl -O https://raw.githubusercontent.com/Dzo4e2250/do-backup/main/backup-setup.sh
```

### 2. Naredi izvršljivo

```bash
chmod +x backup-setup.sh
```

### 3. Poženi

```bash
./backup-setup.sh
```

To je to. Skripta te vodi skozi vse korake.

## Kako izgleda?

```
============================================================
  AVTOMATSKI BACKUP SETUP
============================================================

Ta skripta nastavi avtomatski dnevni backup z oddaljenega strežnika.
Vse kar potrebuješ je IP naslov strežnika in SSH geslo.

[1/6] Preverjam odvisnosti...
  ✓ Package manager: apt
  ✓ rsync ze namescen
  ✓ sshpass ze namescen
  ✓ Vse odvisnosti OK

[2/6] Podatki o oddaljenem strezniku

  IP naslov streznika: 203.0.113.50
  SSH uporabnisko ime [root]: root
  SSH geslo: ****

  Testiram povezavo na root@203.0.113.50...
  ✓ Povezava uspesna! Streznik: my-server

[3/6] Kaj zelis backupirati?

  Iscem kaj je na strezniku...

  Najdeno na strezniku:

    1) Obstoječi backupi: /root/backups/supabase (246M)
    2) PostgreSQL baza (container: supabase-db)
    3) Docker Compose konfiguracije
    4) Vpisi svojo pot (custom)

  Izberi kaj zelis backupirati (vec stevilk loci z vejico, npr: 1,2,3)
  Izbira: 1,2
  ✓ Izbrano: Obstoječi backupi: /root/backups/supabase (246M)
  ✓ Izbrano: PostgreSQL baza (container: supabase-db)

[4/6] Kam shraniti backupe?

  Lokalna pot za backupe [/home/user/backups/my-server]:
  ✓ Mapa ustvarjena: /home/user/backups/my-server

  Kdaj naj se backup izvaja?

    1) Vsak dan ob 4:00
    2) Vsak dan ob 2:00
    3) Vsakih 12 ur
    4) Vsakih 6 ur
    5) Vpisi svoj cron izraz

  Izbira [1]: 1
  ✓ Urnik: vsak dan ob 4:00

  Koliko dni hraniti stare backupe? [14]: 14
  ✓ Rotacija: 14 dni

[5/6] Nastavljam SSH kljuc za avtomatsko povezavo...

  ✓ SSH kljuc ustvarjen: /home/user/.ssh/id_ed25519_backup
  ✓ SSH brez gesla deluje!

[6/6] Ustvarjam backup skripto...

  ✓ Skripta ustvarjena: /home/user/backups/my-server/run_backup.sh
  ✓ Cron nastavljen: vsak dan ob 4:00

  Vse je nastavljeno! Pozenem prvi backup...

  ✓ Prvi backup koncen!

============================================================
  SETUP KONCAN
============================================================

  Streznik:      root@203.0.113.50 (my-server)
  Backupi v:     /home/user/backups/my-server
  Urnik:         vsak dan ob 4:00
  Rotacija:      14 dni
  SSH kljuc:     /home/user/.ssh/id_ed25519_backup
  Skripta:       /home/user/backups/my-server/run_backup.sh
  Log:           /home/user/backups/my-server/backup.log
```

## Po namestitvi

### Uporabni ukazi

```bash
# Rocno pozeni backup
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

### Struktura backupov

```
~/backups/my-server/
├── run_backup.sh              # Backup skripta (avtogenerirana)
├── backup.log                 # Log vseh backupov
├── database/                  # PostgreSQL/MySQL dumpi
│   ├── postgres_20260314_0400.sql.gz
│   ├── postgres_20260313_0400.sql.gz
│   └── ...
├── supabase/                  # Rsync obstojecih backupov
│   ├── supabase_20260314_030001.sql.gz
│   └── ...
└── configs/                   # Docker Compose konfiguracije
    ├── configs_20260314_0400.tar.gz
    └── ...
```

## Kaj backupira?

Skripta avtomatsko odkrije in ponudi:

| Tip | Kako | Rotacija |
|-----|------|----------|
| **PostgreSQL** | `pg_dumpall` preko Docker exec | Po dnevih |
| **MySQL/MariaDB** | `mysqldump` preko Docker exec | Po dnevih |
| **Obstoječe backup mape** | `rsync` (inkrementalno) | Rsync sync |
| **Docker Compose konfigi** | `tar` vseh docker-compose.yml | Po dnevih |
| **Custom pot** | `rsync` (inkrementalno) | Rsync sync |

## Zahteve

- Linux (katerakoli distribucija)
- `sudo` dostop (za namestitev paketov)
- SSH dostop do oddaljenega strežnika (IP + geslo)
- Na oddaljenem strežniku: `rsync` (za sync map)

Skripta sama namesti: `rsync`, `sshpass`, `openssh-client`, `cron`

## Varnost

- SSH ključ se shrani v `~/.ssh/id_ed25519_backup` (samo za backup)
- Geslo strežnika se **ne shrani** nikamor - uporabi se samo za inicalni prenos SSH ključa
- Vsi nadaljnji backupi uporabljajo SSH ključ (brez gesla)
- Backup skripta ne potrebuje root pravic na lokalnem strežniku

## Uporaba z USB

```bash
# Na USB kopiraj:
cp backup-setup.sh /media/usb/

# Na novem strežniku:
cp /media/usb/backup-setup.sh .
chmod +x backup-setup.sh
./backup-setup.sh
```

## Licenca

MIT
