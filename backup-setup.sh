#!/bin/bash
# ============================================================================
# AVTOMATSKI BACKUP SETUP
# ============================================================================
# Univerzalna skripta za nastavitev avtomatskega backupa z oddaljenega strežnika.
# Poženi na kateremkoli Linux računalniku - vse naredi sama.
#
# Podpira tri načine prenosa:
#   - rsync + SSH (priporočeno) - polna funkcionalnost
#   - SFTP - samo prenos datotek
#   - FTP - samo prenos datotek
#
# Uporaba:
#   chmod +x backup-setup.sh
#   ./backup-setup.sh
# ============================================================================

set -e

# Barve za lepši izpis
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

print_header() {
    echo ""
    echo -e "${BLUE}============================================================${NC}"
    echo -e "${BOLD}  $1${NC}"
    echo -e "${BLUE}============================================================${NC}"
    echo ""
}

print_step() {
    echo -e "${CYAN}[$1/${TOTAL_STEPS}]${NC} ${BOLD}$2${NC}"
}

print_ok() {
    echo -e "  ${GREEN}✓${NC} $1"
}

print_warn() {
    echo -e "  ${YELLOW}!${NC} $1"
}

print_err() {
    echo -e "  ${RED}✗${NC} $1"
}

ask() {
    local prompt="$1"
    local default="$2"
    local result
    if [ -n "$default" ]; then
        read -rp "  $prompt [$default]: " result
        echo "${result:-$default}"
    else
        read -rp "  $prompt: " result
        echo "$result"
    fi
}

ask_secret() {
    local prompt="$1"
    local result
    read -rsp "  $prompt: " result
    echo ""
    echo "$result"
}

ask_yesno() {
    local prompt="$1"
    local default="${2:-d}"
    local result
    read -rp "  $prompt [d/n]: " result
    result="${result:-$default}"
    [[ "$result" =~ ^[dDyY] ]]
}

TOTAL_STEPS=7

# ============================================================================
# KORAK 1: Izbira protokola
# ============================================================================
print_header "AVTOMATSKI BACKUP SETUP"
echo -e "Ta skripta nastavi avtomatski dnevni backup z oddaljenega strežnika."
echo ""

print_step 1 "Nacin prenosa"
echo ""
echo -e "    ${CYAN}1)${NC} rsync + SSH ${GREEN}(priporoceno)${NC} - polna funkcionalnost"
echo -e "    ${CYAN}2)${NC} SFTP (SSH port) - samo prenos datotek"
echo -e "    ${CYAN}3)${NC} FTP - samo prenos datotek"
echo ""
PROTO_SEL=$(ask "Izbira" "1")

case "$PROTO_SEL" in
    1) TRANSFER_PROTOCOL="rsync" ;;
    2) TRANSFER_PROTOCOL="sftp" ;;
    3) TRANSFER_PROTOCOL="ftp" ;;
    *) TRANSFER_PROTOCOL="rsync" ;;
esac
print_ok "Protokol: $TRANSFER_PROTOCOL"

if [ "$TRANSFER_PROTOCOL" != "rsync" ]; then
    echo ""
    print_warn "SFTP/FTP podpira samo prenos datotek (mape)."
    print_warn "Odkrivanje podatkovnih baz in Docker konfiguracij ni mogoce."
fi

# ============================================================================
# KORAK 2: Preveri in namesti odvisnosti
# ============================================================================
echo ""
print_step 2 "Preverjam odvisnosti..."

# Detect package manager
PKG_MANAGER=""
if command -v apt-get &>/dev/null; then
    PKG_MANAGER="apt"
elif command -v dnf &>/dev/null; then
    PKG_MANAGER="dnf"
elif command -v yum &>/dev/null; then
    PKG_MANAGER="yum"
elif command -v pacman &>/dev/null; then
    PKG_MANAGER="pacman"
elif command -v zypper &>/dev/null; then
    PKG_MANAGER="zypper"
elif command -v apk &>/dev/null; then
    PKG_MANAGER="apk"
else
    print_err "Ne najdem package managerja (apt, dnf, yum, pacman, zypper, apk)"
    exit 1
fi
print_ok "Package manager: $PKG_MANAGER"

install_pkg() {
    local pkg="$1"
    local pkg_name="$2"  # display name
    if command -v "$pkg" &>/dev/null; then
        print_ok "$pkg_name ze namescen"
        return 0
    fi
    print_warn "$pkg_name manjka - nameščam..."
    case "$PKG_MANAGER" in
        apt)     sudo apt-get update -qq && sudo apt-get install -y -qq "$pkg_name" ;;
        dnf)     sudo dnf install -y -q "$pkg_name" ;;
        yum)     sudo yum install -y -q "$pkg_name" ;;
        pacman)  sudo pacman -S --noconfirm "$pkg_name" ;;
        zypper)  sudo zypper install -y "$pkg_name" ;;
        apk)     sudo apk add "$pkg_name" ;;
    esac
    if command -v "$pkg" &>/dev/null; then
        print_ok "$pkg_name uspesno namescen"
    else
        print_err "Namestitev $pkg_name ni uspela"
        exit 1
    fi
}

# Protokol-specificne odvisnosti
case "$TRANSFER_PROTOCOL" in
    rsync)
        install_pkg rsync rsync
        install_pkg sshpass sshpass
        install_pkg ssh openssh-client 2>/dev/null || install_pkg ssh openssh-clients 2>/dev/null || install_pkg ssh openssh 2>/dev/null || true
        ;;
    sftp)
        install_pkg sshpass sshpass
        install_pkg sftp openssh-client 2>/dev/null || install_pkg sftp openssh-clients 2>/dev/null || install_pkg sftp openssh 2>/dev/null || true
        ;;
    ftp)
        install_pkg lftp lftp
        install_pkg curl curl
        ;;
esac

install_pkg crontab cron 2>/dev/null || install_pkg crond cronie 2>/dev/null || true

if [ "$TRANSFER_PROTOCOL" != "ftp" ] && ! command -v ssh-keygen &>/dev/null; then
    print_err "ssh-keygen ni na voljo. Namesti openssh."
    exit 1
fi
print_ok "Vse odvisnosti OK"

# ============================================================================
# KORAK 3: Podatki o strežniku
# ============================================================================
echo ""
print_step 3 "Podatki o oddaljenem strezniku"
echo ""

REMOTE_IP=$(ask "IP naslov ali hostname streznika")
REMOTE_PORT=""

if [ "$TRANSFER_PROTOCOL" = "ftp" ]; then
    REMOTE_USER=$(ask "FTP uporabnisko ime")
    REMOTE_PASS=$(ask_secret "FTP geslo")
    REMOTE_PORT=$(ask "FTP port" "21")

    echo ""
    echo -e "  Testiram FTP povezavo na ${BOLD}${REMOTE_IP}:${REMOTE_PORT}${NC}..."
    if curl -s --connect-timeout 10 -u "$REMOTE_USER:$REMOTE_PASS" "ftp://$REMOTE_IP:$REMOTE_PORT/" >/dev/null 2>&1; then
        REMOTE_HOSTNAME="$REMOTE_IP"
        print_ok "FTP povezava uspesna!"
    else
        # Poskusi FTPS
        if curl -s --connect-timeout 10 --ssl-reqd -u "$REMOTE_USER:$REMOTE_PASS" "ftp://$REMOTE_IP:$REMOTE_PORT/" >/dev/null 2>&1; then
            REMOTE_HOSTNAME="$REMOTE_IP"
            FTP_SSL="yes"
            print_ok "FTPS povezava uspesna! (SSL)"
        else
            print_err "Ne morem se povezati na FTP $REMOTE_IP:$REMOTE_PORT"
            print_err "Preveri IP, port, uporabnisko ime in geslo."
            exit 1
        fi
    fi
else
    REMOTE_USER=$(ask "SSH uporabnisko ime" "root")
    REMOTE_PASS=$(ask_secret "SSH geslo")
    REMOTE_PORT=$(ask "SSH port" "22")

    echo ""
    echo -e "  Testiram povezavo na ${BOLD}${REMOTE_USER}@${REMOTE_IP}:${REMOTE_PORT}${NC}..."
    if sshpass -p "$REMOTE_PASS" ssh -p "$REMOTE_PORT" -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$REMOTE_USER@$REMOTE_IP" "echo OK" &>/dev/null; then
        REMOTE_HOSTNAME=$(sshpass -p "$REMOTE_PASS" ssh -p "$REMOTE_PORT" -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_IP" "hostname" 2>/dev/null)
        print_ok "Povezava uspesna! Streznik: $REMOTE_HOSTNAME"
    else
        print_err "Ne morem se povezati na $REMOTE_USER@$REMOTE_IP:$REMOTE_PORT"
        print_err "Preveri IP, port, uporabnisko ime in geslo."
        exit 1
    fi
fi

# ============================================================================
# KORAK 4: Kaj backupirati
# ============================================================================
echo ""
print_step 4 "Kaj zelis backupirati?"
echo ""

FINAL_PATHS=()

if [ "$TRANSFER_PROTOCOL" = "rsync" ]; then
    # ---- Polna odkrivanje (samo rsync) ----
    echo -e "  Iscem kaj je na strezniku..."
    echo ""

    REMOTE_INFO=$(sshpass -p "$REMOTE_PASS" ssh -p "$REMOTE_PORT" -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_IP" '
    echo "=== DOCKER ==="
    if command -v docker &>/dev/null; then
        docker ps --format "{{.Names}}" 2>/dev/null | sort
    else
        echo "NONE"
    fi
    echo "=== DATABASES ==="
    if docker ps --format "{{.Names}}" 2>/dev/null | grep -qi "postgres\|supabase-db"; then
        echo "postgresql: $(docker ps --format "{{.Names}}" 2>/dev/null | grep -i "postgres\|supabase-db" | head -1)"
    fi
    if docker ps --format "{{.Names}}" 2>/dev/null | grep -qi "mysql\|mariadb"; then
        echo "mysql: $(docker ps --format "{{.Names}}" 2>/dev/null | grep -i "mysql\|mariadb" | head -1)"
    fi
    echo "=== EXISTING_BACKUPS ==="
    for dir in /opt/backups /root/backups /var/backups /home/*/backups; do
        [ -d "$dir" ] && echo "$dir: $(du -sh "$dir" 2>/dev/null | cut -f1)"
    done
    echo "=== DOCKER_COMPOSE ==="
    find /opt -maxdepth 2 -name "docker-compose.yml" -o -name "docker-compose.yaml" 2>/dev/null | head -20
    echo "=== END ==="
    ' 2>/dev/null)

    BACKUP_OPTIONS=()
    BACKUP_PATHS=()
    IDX=0

    while IFS= read -r line; do
        if [[ "$line" == /opt/* ]] || [[ "$line" == /root/* ]] || [[ "$line" == /var/* ]] || [[ "$line" == /home/* ]]; then
            DIR=$(echo "$line" | cut -d: -f1)
            SIZE=$(echo "$line" | cut -d: -f2 | xargs)
            IDX=$((IDX + 1))
            BACKUP_OPTIONS+=("Obstoječi backupi: $DIR ($SIZE)")
            BACKUP_PATHS+=("$DIR")
        fi
    done <<< "$(echo "$REMOTE_INFO" | sed -n '/=== EXISTING_BACKUPS ===/,/=== /p' | grep -v "===")"

    DB_CONTAINER=""
    while IFS= read -r line; do
        if [[ "$line" == postgresql:* ]]; then
            DB_CONTAINER=$(echo "$line" | cut -d: -f2 | xargs)
            IDX=$((IDX + 1))
            BACKUP_OPTIONS+=("PostgreSQL baza (container: $DB_CONTAINER)")
            BACKUP_PATHS+=("POSTGRES:$DB_CONTAINER")
        elif [[ "$line" == mysql:* ]]; then
            DB_CONTAINER=$(echo "$line" | cut -d: -f2 | xargs)
            IDX=$((IDX + 1))
            BACKUP_OPTIONS+=("MySQL baza (container: $DB_CONTAINER)")
            BACKUP_PATHS+=("MYSQL:$DB_CONTAINER")
        fi
    done <<< "$(echo "$REMOTE_INFO" | sed -n '/=== DATABASES ===/,/=== /p' | grep -v "===")"

    COMPOSE_FILES=$(echo "$REMOTE_INFO" | sed -n '/=== DOCKER_COMPOSE ===/,/=== END ===/p' | grep -v "===" | grep -v "^$")
    if [ -n "$COMPOSE_FILES" ]; then
        IDX=$((IDX + 1))
        BACKUP_OPTIONS+=("Docker Compose konfiguracije")
        BACKUP_PATHS+=("CONFIGS")
    fi

    IDX=$((IDX + 1))
    BACKUP_OPTIONS+=("Vpisi svojo pot (custom)")
    BACKUP_PATHS+=("CUSTOM")

    echo -e "  ${BOLD}Najdeno na strezniku:${NC}"
    echo ""
    for i in "${!BACKUP_OPTIONS[@]}"; do
        echo -e "    ${CYAN}$((i + 1)))${NC} ${BACKUP_OPTIONS[$i]}"
    done
    echo ""

    echo -e "  Izberi kaj zelis backupirati (vec stevilk loci z vejico, npr: 1,2,3)"
    SELECTION=$(ask "Izbira")

    SELECTED_ITEMS=()
    IFS=',' read -ra SEL_ARRAY <<< "$SELECTION"
    for sel in "${SEL_ARRAY[@]}"; do
        sel=$(echo "$sel" | xargs)
        idx=$((sel - 1))
        if [ "$idx" -ge 0 ] && [ "$idx" -lt "${#BACKUP_PATHS[@]}" ]; then
            SELECTED_ITEMS+=("${BACKUP_PATHS[$idx]}")
            print_ok "Izbrano: ${BACKUP_OPTIONS[$idx]}"
        fi
    done

    if [ ${#SELECTED_ITEMS[@]} -eq 0 ]; then
        print_err "Nic ni izbrano!"
        exit 1
    fi

    for item in "${SELECTED_ITEMS[@]}"; do
        if [ "$item" = "CUSTOM" ]; then
            CUSTOM_PATH=$(ask "Vpisi pot na strezniku za backup")
            FINAL_PATHS+=("$CUSTOM_PATH")
        else
            FINAL_PATHS+=("$item")
        fi
    done

else
    # ---- SFTP/FTP: ročni vnos poti ----
    echo -e "  ${TRANSFER_PROTOCOL^^} podpira samo prenos map. Vpisi poti na strezniku."
    echo ""
    while true; do
        CUSTOM_PATH=$(ask "Pot na strezniku (npr: /volume1/web)")
        if [ -n "$CUSTOM_PATH" ]; then
            FINAL_PATHS+=("$CUSTOM_PATH")
            print_ok "Dodano: $CUSTOM_PATH"
        fi
        echo ""
        if ! ask_yesno "Dodaj se eno pot?"; then
            break
        fi
    done

    if [ ${#FINAL_PATHS[@]} -eq 0 ]; then
        print_err "Nic ni izbrano!"
        exit 1
    fi
fi

# ============================================================================
# KORAK 5: Kam shraniti
# ============================================================================
echo ""
print_step 5 "Kam shraniti backupe?"
echo ""

DEFAULT_BACKUP_DIR="$HOME/backups/${REMOTE_HOSTNAME:-$REMOTE_IP}"
BACKUP_DIR=$(ask "Lokalna pot za backupe" "$DEFAULT_BACKUP_DIR")
mkdir -p "$BACKUP_DIR"
print_ok "Mapa ustvarjena: $BACKUP_DIR"

echo ""
echo -e "  ${BOLD}Kdaj naj se backup izvaja?${NC}"
echo ""
echo -e "    ${CYAN}1)${NC} Vsak dan ob 4:00"
echo -e "    ${CYAN}2)${NC} Vsak dan ob 2:00"
echo -e "    ${CYAN}3)${NC} Vsakih 12 ur"
echo -e "    ${CYAN}4)${NC} Vsakih 6 ur"
echo -e "    ${CYAN}5)${NC} Vpisi svoj cron izraz"
echo ""
SCHEDULE_SEL=$(ask "Izbira" "1")

case "$SCHEDULE_SEL" in
    1) CRON_EXPR="0 4 * * *"; SCHEDULE_DESC="vsak dan ob 4:00" ;;
    2) CRON_EXPR="0 2 * * *"; SCHEDULE_DESC="vsak dan ob 2:00" ;;
    3) CRON_EXPR="0 */12 * * *"; SCHEDULE_DESC="vsakih 12 ur" ;;
    4) CRON_EXPR="0 */6 * * *"; SCHEDULE_DESC="vsakih 6 ur" ;;
    5) CRON_EXPR=$(ask "Cron izraz (npr: 0 4 * * *)"); SCHEDULE_DESC="po meri: $CRON_EXPR" ;;
    *) CRON_EXPR="0 4 * * *"; SCHEDULE_DESC="vsak dan ob 4:00" ;;
esac
print_ok "Urnik: $SCHEDULE_DESC"

RETENTION=$(ask "Koliko dni hraniti stare backupe?" "14")
print_ok "Rotacija: $RETENTION dni"

# ============================================================================
# KORAK 6: SSH ključ (rsync/sftp) ali shranitev FTP podatkov
# ============================================================================
echo ""
print_step 6 "Nastavljam avtentikacijo..."
echo ""

SSH_KEY=""

if [ "$TRANSFER_PROTOCOL" = "ftp" ]; then
    print_warn "FTP podatki (uporabnisko ime in geslo) bodo shranjeni v backup skripti."
    print_warn "Poskrbite da ima skripta ustrezne pravice (chmod 600)."
    print_ok "FTP podatki pripravljeni"
else
    SSH_KEY="$HOME/.ssh/id_ed25519_backup"
    if [ -f "$SSH_KEY" ]; then
        print_ok "SSH kljuc ze obstaja: $SSH_KEY"
    else
        ssh-keygen -t ed25519 -f "$SSH_KEY" -N "" -q -C "backup@$(hostname)"
        print_ok "SSH kljuc ustvarjen: $SSH_KEY"
    fi

    PUBKEY=$(cat "${SSH_KEY}.pub")
    sshpass -p "$REMOTE_PASS" ssh -p "$REMOTE_PORT" -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_IP" "
        mkdir -p ~/.ssh
        chmod 700 ~/.ssh
        if ! grep -qF '$PUBKEY' ~/.ssh/authorized_keys 2>/dev/null; then
            echo '$PUBKEY' >> ~/.ssh/authorized_keys
            chmod 600 ~/.ssh/authorized_keys
        fi
    " 2>/dev/null

    if ssh -i "$SSH_KEY" -p "$REMOTE_PORT" -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o PasswordAuthentication=no "$REMOTE_USER@$REMOTE_IP" "echo OK" &>/dev/null; then
        print_ok "SSH brez gesla deluje!"
    else
        print_err "SSH brez gesla ne deluje. Preveri nastavitve."
        exit 1
    fi
fi

# ============================================================================
# KORAK 7: Ustvari backup skripto in cron
# ============================================================================
echo ""
print_step 7 "Ustvarjam backup skripto..."
echo ""

SCRIPT_PATH="$BACKUP_DIR/run_backup.sh"
LOG_PATH="$BACKUP_DIR/backup.log"

# ---- Glava skripte ----
cat > "$SCRIPT_PATH" << SCRIPTEOF
#!/bin/bash
# Avtomatski backup - ustvarjeno $(date '+%Y-%m-%d %H:%M')
# Streznik: ${REMOTE_USER}@${REMOTE_IP} (${REMOTE_HOSTNAME:-$REMOTE_IP})
# Protokol: $TRANSFER_PROTOCOL
# Urnik: $SCHEDULE_DESC
# Rotacija: $RETENTION dni

BACKUP_DIR="$BACKUP_DIR"
RETENTION=$RETENTION
LOG="$LOG_PATH"
DATE=\$(date '+%Y%m%d_%H%M')

log() { echo "\$(date '+%Y-%m-%d %H:%M:%S') | \$1" >> "\$LOG"; }

log "=== Backup started ($TRANSFER_PROTOCOL) ==="

SCRIPTEOF

# ---- Protokol-specificne spremenljivke ----
case "$TRANSFER_PROTOCOL" in
    rsync)
        cat >> "$SCRIPT_PATH" << VARSEOF
REMOTE="$REMOTE_USER@$REMOTE_IP"
SSH_KEY="$SSH_KEY"
SSH_OPTS="-i \$SSH_KEY -p $REMOTE_PORT -o StrictHostKeyChecking=no -o ConnectTimeout=30"

VARSEOF
        ;;
    sftp)
        cat >> "$SCRIPT_PATH" << VARSEOF
REMOTE_USER="$REMOTE_USER"
REMOTE_IP="$REMOTE_IP"
REMOTE_PORT="$REMOTE_PORT"
SSH_KEY="$SSH_KEY"
SSH_OPTS="-i \$SSH_KEY -P \$REMOTE_PORT -o StrictHostKeyChecking=no -o ConnectTimeout=30"

VARSEOF
        ;;
    ftp)
        cat >> "$SCRIPT_PATH" << VARSEOF
FTP_USER="$REMOTE_USER"
FTP_PASS="$REMOTE_PASS"
FTP_HOST="$REMOTE_IP"
FTP_PORT="$REMOTE_PORT"
FTP_SSL="${FTP_SSL:-no}"

VARSEOF
        ;;
esac

# ---- Backup ukazi za vsako izbrano pot ----
for item in "${FINAL_PATHS[@]}"; do
    if [[ "$item" == POSTGRES:* ]]; then
        CONTAINER=$(echo "$item" | cut -d: -f2)
        cat >> "$SCRIPT_PATH" << DBEOF

# --- PostgreSQL backup ---
DB_DIR="\$BACKUP_DIR/database"
mkdir -p "\$DB_DIR"
log "PostgreSQL dump iz containerja $CONTAINER..."
ssh \$SSH_OPTS "\$REMOTE" "docker exec $CONTAINER pg_dumpall -U postgres 2>/dev/null | gzip" > "\$DB_DIR/postgres_\${DATE}.sql.gz" 2>/dev/null
SIZE=\$(du -h "\$DB_DIR/postgres_\${DATE}.sql.gz" 2>/dev/null | cut -f1)
if [ -s "\$DB_DIR/postgres_\${DATE}.sql.gz" ]; then
    log "  PostgreSQL OK: \$SIZE"
else
    rm -f "\$DB_DIR/postgres_\${DATE}.sql.gz"
    log "  PostgreSQL NAPAKA: dump prazen ali ni uspel"
fi
find "\$DB_DIR" -name "postgres_*.sql.gz" -mtime +\$RETENTION -delete 2>/dev/null
DBEOF

    elif [[ "$item" == MYSQL:* ]]; then
        CONTAINER=$(echo "$item" | cut -d: -f2)
        cat >> "$SCRIPT_PATH" << DBEOF

# --- MySQL backup ---
DB_DIR="\$BACKUP_DIR/database"
mkdir -p "\$DB_DIR"
log "MySQL dump iz containerja $CONTAINER..."
ssh \$SSH_OPTS "\$REMOTE" "docker exec $CONTAINER mysqldump --all-databases -u root 2>/dev/null | gzip" > "\$DB_DIR/mysql_\${DATE}.sql.gz" 2>/dev/null
SIZE=\$(du -h "\$DB_DIR/mysql_\${DATE}.sql.gz" 2>/dev/null | cut -f1)
if [ -s "\$DB_DIR/mysql_\${DATE}.sql.gz" ]; then
    log "  MySQL OK: \$SIZE"
else
    rm -f "\$DB_DIR/mysql_\${DATE}.sql.gz"
    log "  MySQL NAPAKA: dump prazen ali ni uspel"
fi
find "\$DB_DIR" -name "mysql_*.sql.gz" -mtime +\$RETENTION -delete 2>/dev/null
DBEOF

    elif [ "$item" = "CONFIGS" ]; then
        cat >> "$SCRIPT_PATH" << CFGEOF

# --- Docker Compose konfiguracije ---
CFG_DIR="\$BACKUP_DIR/configs"
mkdir -p "\$CFG_DIR"
log "Backup Docker Compose konfiguracij..."
ssh \$SSH_OPTS "\$REMOTE" "tar czf - \$(find /opt -maxdepth 2 -name 'docker-compose.yml' -o -name 'docker-compose.yaml' -o -name '.env' 2>/dev/null | tr '\n' ' ') 2>/dev/null" > "\$CFG_DIR/configs_\${DATE}.tar.gz" 2>/dev/null
SIZE=\$(du -h "\$CFG_DIR/configs_\${DATE}.tar.gz" 2>/dev/null | cut -f1)
log "  Configs OK: \$SIZE"
find "\$CFG_DIR" -name "configs_*.tar.gz" -mtime +\$RETENTION -delete 2>/dev/null
CFGEOF

    else
        # Prenos mape - odvisno od protokola
        DIRNAME=$(basename "$item")

        case "$TRANSFER_PROTOCOL" in
            rsync)
                cat >> "$SCRIPT_PATH" << SYNCEOF

# --- Rsync: $item ---
SYNC_DIR="\$BACKUP_DIR/$DIRNAME"
mkdir -p "\$SYNC_DIR"
log "Rsync $item..."
rsync -avz --delete -e "ssh \$SSH_OPTS" "\$REMOTE:$item/" "\$SYNC_DIR/" >> "\$LOG" 2>&1
if [ \$? -eq 0 ]; then
    SIZE=\$(du -sh "\$SYNC_DIR" 2>/dev/null | cut -f1)
    log "  Rsync OK: \$SIZE"
else
    log "  Rsync NAPAKA"
fi
SYNCEOF
                ;;
            sftp)
                cat >> "$SCRIPT_PATH" << SFTPEOF

# --- SFTP: $item ---
SYNC_DIR="\$BACKUP_DIR/$DIRNAME"
mkdir -p "\$SYNC_DIR"
log "SFTP prenos $item..."
sftp \$SSH_OPTS "\$REMOTE_USER@\$REMOTE_IP" >> "\$LOG" 2>&1 << SFTPBATCH
cd $item
lcd \$SYNC_DIR
get -r *
bye
SFTPBATCH
if [ \$? -eq 0 ]; then
    SIZE=\$(du -sh "\$SYNC_DIR" 2>/dev/null | cut -f1)
    log "  SFTP OK: \$SIZE"
else
    log "  SFTP NAPAKA"
fi
SFTPEOF
                ;;
            ftp)
                cat >> "$SCRIPT_PATH" << FTPEOF

# --- FTP: $item ---
SYNC_DIR="\$BACKUP_DIR/$DIRNAME"
mkdir -p "\$SYNC_DIR"
log "FTP mirror $item..."
LFTP_SSL=""
if [ "\$FTP_SSL" = "yes" ]; then
    LFTP_SSL="set ftp:ssl-force true; set ssl:verify-certificate no;"
fi
lftp -c "\${LFTP_SSL} set ftp:passive-mode true; open -u \$FTP_USER,\$FTP_PASS -p \$FTP_PORT \$FTP_HOST; mirror --delete --verbose $item \$SYNC_DIR" >> "\$LOG" 2>&1
if [ \$? -eq 0 ]; then
    SIZE=\$(du -sh "\$SYNC_DIR" 2>/dev/null | cut -f1)
    log "  FTP OK: \$SIZE"
else
    log "  FTP NAPAKA"
fi
FTPEOF
                ;;
        esac
    fi
done

# ---- Noga skripte ----
cat >> "$SCRIPT_PATH" << 'FOOTEREOF'

# --- Disk space ---
DISK=$(df -h "$BACKUP_DIR" 2>/dev/null | tail -1 | awk '{print $4 " free (" $5 " used)"}')
log "Disk: $DISK"
log "=== Backup done ==="
FOOTEREOF

chmod 600 "$SCRIPT_PATH"
chmod +x "$SCRIPT_PATH"
print_ok "Skripta ustvarjena: $SCRIPT_PATH"

# Set up cron
(crontab -l 2>/dev/null | grep -v "$SCRIPT_PATH"; echo "$CRON_EXPR $SCRIPT_PATH") | crontab -
print_ok "Cron nastavljen: $SCHEDULE_DESC"

# ============================================================================
# PRVI BACKUP
# ============================================================================
echo ""
echo -e "  ${BOLD}Vse je nastavljeno! Pozenem prvi backup...${NC}"
echo ""

"$SCRIPT_PATH"

echo ""
print_ok "Prvi backup koncen!"
echo ""

# Rezultat
echo -e "${BLUE}============================================================${NC}"
echo -e "${BOLD}  SETUP KONCAN${NC}"
echo -e "${BLUE}============================================================${NC}"
echo ""
echo -e "  ${BOLD}Streznik:${NC}      $REMOTE_USER@$REMOTE_IP (${REMOTE_HOSTNAME:-$REMOTE_IP})"
echo -e "  ${BOLD}Protokol:${NC}      $TRANSFER_PROTOCOL"
echo -e "  ${BOLD}Backupi v:${NC}     $BACKUP_DIR"
echo -e "  ${BOLD}Urnik:${NC}         $SCHEDULE_DESC"
echo -e "  ${BOLD}Rotacija:${NC}      $RETENTION dni"
if [ -n "$SSH_KEY" ]; then
    echo -e "  ${BOLD}SSH kljuc:${NC}     $SSH_KEY"
fi
echo -e "  ${BOLD}Skripta:${NC}       $SCRIPT_PATH"
echo -e "  ${BOLD}Log:${NC}           $LOG_PATH"
echo ""
echo -e "  ${BOLD}Uporabni ukazi:${NC}"
echo -e "    Rocni backup:    ${CYAN}$SCRIPT_PATH${NC}"
echo -e "    Poglej log:      ${CYAN}cat $LOG_PATH${NC}"
echo -e "    Poglej backupe:  ${CYAN}ls -lh $BACKUP_DIR${NC}"
echo -e "    Uredi cron:      ${CYAN}crontab -e${NC}"
echo -e "    Odstrani:        ${CYAN}crontab -l | grep -v run_backup | crontab -${NC}"
echo ""
echo -e "  ${GREEN}Backup se bo avtomatsko izvajal $SCHEDULE_DESC.${NC}"
echo ""
