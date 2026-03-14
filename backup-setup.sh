#!/bin/bash
# ============================================================================
# AVTOMATSKI BACKUP SETUP
# ============================================================================
# Univerzalna skripta za nastavitev avtomatskega backupa z oddaljenega strežnika.
# Poženi na kateremkoli Linux računalniku - vse naredi sama.
#
# Uporaba:
#   chmod +x backup-setup.sh
#   ./backup-setup.sh
#
# Kaj naredi:
#   1. Namesti manjkajoče orodja (rsync, sshpass, cron)
#   2. Vpraša za podatke o strežniku
#   3. Vpraša kaj in kam backupirati
#   4. Ustvari SSH ključ za avtomatsko povezavo
#   5. Nastavi dnevni cron job
#   6. Požene prvi backup
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

TOTAL_STEPS=6

# ============================================================================
# KORAK 1: Preveri in namesti odvisnosti
# ============================================================================
print_header "AVTOMATSKI BACKUP SETUP"
echo -e "Ta skripta nastavi avtomatski dnevni backup z oddaljenega strežnika."
echo -e "Vse kar potrebuješ je IP naslov strežnika in SSH geslo."
echo ""

print_step 1 "Preverjam odvisnosti..."

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

install_pkg rsync rsync
install_pkg sshpass sshpass
install_pkg ssh openssh-client 2>/dev/null || install_pkg ssh openssh-clients 2>/dev/null || install_pkg ssh openssh 2>/dev/null || true
install_pkg crontab cron 2>/dev/null || install_pkg crond cronie 2>/dev/null || true

# Make sure ssh-keygen is available
if ! command -v ssh-keygen &>/dev/null; then
    print_err "ssh-keygen ni na voljo. Namesti openssh."
    exit 1
fi
print_ok "Vse odvisnosti OK"

# ============================================================================
# KORAK 2: Podatki o strežniku
# ============================================================================
print_step 2 "Podatki o oddaljenem strezniku"
echo ""

REMOTE_IP=$(ask "IP naslov streznika")
REMOTE_USER=$(ask "SSH uporabnisko ime" "root")
REMOTE_PASS=$(ask_secret "SSH geslo")

# Test connection
echo ""
echo -e "  Testiram povezavo na ${BOLD}${REMOTE_USER}@${REMOTE_IP}${NC}..."
if sshpass -p "$REMOTE_PASS" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$REMOTE_USER@$REMOTE_IP" "echo OK" &>/dev/null; then
    REMOTE_HOSTNAME=$(sshpass -p "$REMOTE_PASS" ssh -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_IP" "hostname" 2>/dev/null)
    print_ok "Povezava uspesna! Streznik: $REMOTE_HOSTNAME"
else
    print_err "Ne morem se povezati na $REMOTE_USER@$REMOTE_IP"
    print_err "Preveri IP, uporabnisko ime in geslo."
    exit 1
fi

# ============================================================================
# KORAK 3: Kaj backupirati
# ============================================================================
print_step 3 "Kaj zelis backupirati?"
echo ""

# Discover what's on the remote server
echo -e "  Iscem kaj je na strezniku..."
echo ""

REMOTE_INFO=$(sshpass -p "$REMOTE_PASS" ssh -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_IP" '
# Check for common backup sources
echo "=== DOCKER ==="
if command -v docker &>/dev/null; then
    docker ps --format "{{.Names}}" 2>/dev/null | sort
else
    echo "NONE"
fi
echo "=== DATABASES ==="
# PostgreSQL
if docker ps --format "{{.Names}}" 2>/dev/null | grep -qi "postgres\|supabase-db"; then
    echo "postgresql: $(docker ps --format "{{.Names}}" 2>/dev/null | grep -i "postgres\|supabase-db" | head -1)"
fi
# MySQL/MariaDB
if docker ps --format "{{.Names}}" 2>/dev/null | grep -qi "mysql\|mariadb"; then
    echo "mysql: $(docker ps --format "{{.Names}}" 2>/dev/null | grep -i "mysql\|mariadb" | head -1)"
fi
# Check for existing backup dirs
echo "=== EXISTING_BACKUPS ==="
for dir in /opt/backups /root/backups /var/backups /home/*/backups; do
    [ -d "$dir" ] && echo "$dir: $(du -sh "$dir" 2>/dev/null | cut -f1)"
done
echo "=== DOCKER_COMPOSE ==="
find /opt -maxdepth 2 -name "docker-compose.yml" -o -name "docker-compose.yaml" 2>/dev/null | head -20
echo "=== END ==="
' 2>/dev/null)

# Parse and display options
BACKUP_OPTIONS=()
BACKUP_PATHS=()
IDX=0

# Check for existing backup directories
while IFS= read -r line; do
    if [[ "$line" == /opt/* ]] || [[ "$line" == /root/* ]] || [[ "$line" == /var/* ]] || [[ "$line" == /home/* ]]; then
        DIR=$(echo "$line" | cut -d: -f1)
        SIZE=$(echo "$line" | cut -d: -f2 | xargs)
        IDX=$((IDX + 1))
        BACKUP_OPTIONS+=("Obstoječi backupi: $DIR ($SIZE)")
        BACKUP_PATHS+=("$DIR")
    fi
done <<< "$(echo "$REMOTE_INFO" | sed -n '/=== EXISTING_BACKUPS ===/,/=== /p' | grep -v "===")"

# Check for databases
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

# Check for docker compose configs
COMPOSE_FILES=$(echo "$REMOTE_INFO" | sed -n '/=== DOCKER_COMPOSE ===/,/=== END ===/p' | grep -v "===" | grep -v "^$")
if [ -n "$COMPOSE_FILES" ]; then
    IDX=$((IDX + 1))
    BACKUP_OPTIONS+=("Docker Compose konfiguracije")
    BACKUP_PATHS+=("CONFIGS")
fi

# Add custom option
IDX=$((IDX + 1))
BACKUP_OPTIONS+=("Vpisi svojo pot (custom)")
BACKUP_PATHS+=("CUSTOM")

# Display options
echo -e "  ${BOLD}Najdeno na strezniku:${NC}"
echo ""
for i in "${!BACKUP_OPTIONS[@]}"; do
    echo -e "    ${CYAN}$((i + 1)))${NC} ${BACKUP_OPTIONS[$i]}"
done
echo ""

# Let user select (multiple)
echo -e "  Izberi kaj zelis backupirati (vec stevilk loci z vejico, npr: 1,2,3)"
SELECTION=$(ask "Izbira")

# Parse selection
SELECTED_ITEMS=()
IFS=',' read -ra SEL_ARRAY <<< "$SELECTION"
for sel in "${SEL_ARRAY[@]}"; do
    sel=$(echo "$sel" | xargs)  # trim
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

# Handle custom paths
FINAL_PATHS=()
for item in "${SELECTED_ITEMS[@]}"; do
    if [ "$item" = "CUSTOM" ]; then
        CUSTOM_PATH=$(ask "Vpisi pot na strezniku za backup")
        FINAL_PATHS+=("$CUSTOM_PATH")
    else
        FINAL_PATHS+=("$item")
    fi
done

# ============================================================================
# KORAK 4: Kam shraniti
# ============================================================================
print_step 4 "Kam shraniti backupe?"
echo ""

DEFAULT_BACKUP_DIR="$HOME/backups/$REMOTE_HOSTNAME"
BACKUP_DIR=$(ask "Lokalna pot za backupe" "$DEFAULT_BACKUP_DIR")
mkdir -p "$BACKUP_DIR"
print_ok "Mapa ustvarjena: $BACKUP_DIR"

# Ask for schedule
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

# Ask for retention
RETENTION=$(ask "Koliko dni hraniti stare backupe?" "14")
print_ok "Rotacija: $RETENTION dni"

# ============================================================================
# KORAK 5: SSH ključ
# ============================================================================
print_step 5 "Nastavljam SSH kljuc za avtomatsko povezavo..."
echo ""

SSH_KEY="$HOME/.ssh/id_ed25519_backup"
if [ -f "$SSH_KEY" ]; then
    print_ok "SSH kljuc ze obstaja: $SSH_KEY"
else
    ssh-keygen -t ed25519 -f "$SSH_KEY" -N "" -q -C "backup@$(hostname)"
    print_ok "SSH kljuc ustvarjen: $SSH_KEY"
fi

# Copy to remote server
PUBKEY=$(cat "${SSH_KEY}.pub")
sshpass -p "$REMOTE_PASS" ssh -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_IP" "
    mkdir -p ~/.ssh
    chmod 700 ~/.ssh
    # Add key if not already there
    if ! grep -qF '$PUBKEY' ~/.ssh/authorized_keys 2>/dev/null; then
        echo '$PUBKEY' >> ~/.ssh/authorized_keys
        chmod 600 ~/.ssh/authorized_keys
    fi
" 2>/dev/null

# Test passwordless SSH
if ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o PasswordAuthentication=no "$REMOTE_USER@$REMOTE_IP" "echo OK" &>/dev/null; then
    print_ok "SSH brez gesla deluje!"
else
    print_err "SSH brez gesla ne deluje. Preveri nastavitve."
    exit 1
fi

# ============================================================================
# KORAK 6: Ustvari backup skripto in cron
# ============================================================================
print_step 6 "Ustvarjam backup skripto..."
echo ""

SCRIPT_PATH="$BACKUP_DIR/run_backup.sh"
LOG_PATH="$BACKUP_DIR/backup.log"

# Build the backup script
cat > "$SCRIPT_PATH" << SCRIPTEOF
#!/bin/bash
# Avtomatski backup - ustvarjeno $(date '+%Y-%m-%d %H:%M')
# Streznik: $REMOTE_USER@$REMOTE_IP ($REMOTE_HOSTNAME)
# Urnik: $SCHEDULE_DESC
# Rotacija: $RETENTION dni

REMOTE="$REMOTE_USER@$REMOTE_IP"
SSH_KEY="$SSH_KEY"
BACKUP_DIR="$BACKUP_DIR"
RETENTION=$RETENTION
LOG="$LOG_PATH"
SSH_OPTS="-i \$SSH_KEY -o StrictHostKeyChecking=no -o ConnectTimeout=30"
DATE=\$(date '+%Y%m%d_%H%M')

log() { echo "\$(date '+%Y-%m-%d %H:%M:%S') | \$1" >> "\$LOG"; }

log "=== Backup started ==="

SCRIPTEOF

# Add backup commands for each selected item
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
        # Regular directory sync
        DIRNAME=$(basename "$item")
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

    fi
done

# Add footer to script
cat >> "$SCRIPT_PATH" << 'FOOTEREOF'

# --- Disk space ---
DISK=$(df -h "$BACKUP_DIR" 2>/dev/null | tail -1 | awk '{print $4 " free (" $5 " used)"}')
log "Disk: $DISK"
log "=== Backup done ==="
FOOTEREOF

chmod +x "$SCRIPT_PATH"
print_ok "Skripta ustvarjena: $SCRIPT_PATH"

# Set up cron
(crontab -l 2>/dev/null | grep -v "$SCRIPT_PATH"; echo "$CRON_EXPR $SCRIPT_PATH") | crontab -
print_ok "Cron nastavljem: $SCHEDULE_DESC"

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

# Show results
echo -e "${BLUE}============================================================${NC}"
echo -e "${BOLD}  SETUP KONCAN${NC}"
echo -e "${BLUE}============================================================${NC}"
echo ""
echo -e "  ${BOLD}Streznik:${NC}      $REMOTE_USER@$REMOTE_IP ($REMOTE_HOSTNAME)"
echo -e "  ${BOLD}Backupi v:${NC}     $BACKUP_DIR"
echo -e "  ${BOLD}Urnik:${NC}         $SCHEDULE_DESC"
echo -e "  ${BOLD}Rotacija:${NC}      $RETENTION dni"
echo -e "  ${BOLD}SSH kljuc:${NC}     $SSH_KEY"
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
