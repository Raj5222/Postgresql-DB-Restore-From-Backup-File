#!/bin/bash

set -e              
set -o pipefail     
# set -u            

# --- Database Credentials ---
DB_HOST="localhost"
DB_PORT="5432"
DB_NAME="terotam_local"
DB_USER="postgres"
DB_PASS="0206" 

# --- Backup Source ---
BACKUP_FILE="/home/ubuntu/sandbox-db.dump"

# --- Target Tables Configuration ---
TARGETS=(
    "custom_module_data : customer_id : 708"
    "custom_module_equipment_map : cm_id : 1710,1709,1708,1707,1706,1705,1704,1703"
)

SCHEMA="public"

DISABLE_CONSTRAINTS="true"
OVERRIDE_IDENTITY="true"

export PGPASSWORD="$DB_PASS"
export PGOPTIONS='-c client_min_messages=error' 

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

ts() { date +'%H:%M:%S'; }
log_info()    { echo -e "${BLUE}[$(ts)] [INFO]${NC}  $1"; }
log_step()    { echo -e "${CYAN}[$(ts)] [STEP]${NC}  $1"; }
log_process() { echo -e "${MAGENTA}[$(ts)] [PROC]${NC}  $1"; }
log_success() { echo -e "${GREEN}[$(ts)] [PASS]${NC}  $1"; }
log_warn()    { echo -e "${YELLOW}[$(ts)] [WARN]${NC}  $1"; }
log_error()   { echo -e "${RED}[$(ts)] [FAIL]${NC}  $1"; echo -e "${RED}Process Aborted.${NC}"; exit 1; }
log_header()  { echo -e "\n${BOLD}====================================================================================================${NC}\n${BOLD}   $1${NC}\n${BOLD}====================================================================================================${NC}"; }

# Quiet Wrapper
exec_silent() {
    "$@" 2> >(grep -vE "collation version mismatch|DETAIL:|HINT:" >&2)
}

# --- AUTOMATIC CLEANUP TRAP ---
declare -a GLOBAL_TEMP_TABLES
COMMIT_SUCCESS="false"

cleanup_handler() {
    if [ "$COMMIT_SUCCESS" == "true" ]; then return; fi
    echo -e "\n${RED}[ERROR] Process interrupted or failed${NC}"
    echo -e "${YELLOW}      Transaction automatically rolled back${NC}"
    echo -e "${YELLOW}      Removing temporary tables...${NC}"
    for TMP in "${GLOBAL_TEMP_TABLES[@]}"; do
        if [[ -n "$TMP" ]]; then
            PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -q -c "DROP TABLE IF EXISTS ${SCHEMA}.${TMP};" >/dev/null 2>&1
        fi
    done
    echo -e "${RED}[FAIL] Operation cancelled${NC}"
}
trap cleanup_handler EXIT INT TERM

clear
log_header "RESTORE OPERATION STARTED"

# Tools
for tool in psql pg_restore sed awk grep; do
    if ! command -v $tool &> /dev/null; then log_error "Missing tool: $tool"; fi
done

# File
if [[ ! -f "$BACKUP_FILE" ]]; then log_error "Backup file not found: $BACKUP_FILE"; fi 
log_success "Backup file found: $BACKUP_FILE"

# Connection
log_info "Checking database connection..."
if ! exec_silent psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "SELECT 1" >/dev/null; then
    log_error "Failed to connect to database."
fi
log_success "Database connection successful: ${DB_NAME}"


log_header "PHASE 1: EXTRACTING DATA FROM BACKUP"

declare -a ARR_TABLES
declare -a ARR_TEMP_TABLES
declare -a ARR_COUNTS
declare -a ARR_MODES
declare -a ARR_WHERES
declare -a ARR_PKS  # PK Cache

for config in "${TARGETS[@]}"; do
    IFS=':' read -r RAW_TABLE RAW_COL RAW_IDS <<< "$config"
    CUR_TABLE=$(echo "$RAW_TABLE" | xargs)
    CUR_COL=$(echo "$RAW_COL" | xargs)
    CUR_IDS=$(echo "${RAW_IDS:-}" | xargs)

    # Validation & PK Detection
    CHECK=$(exec_silent psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -A -c "SELECT to_regclass('${SCHEMA}.${CUR_TABLE}');")
    if [[ -z "$CHECK" ]]; then log_error "Table '${SCHEMA}.${CUR_TABLE}' does not exist."; fi

    # DETECT PRIMARY KEY
    PK_COL=$(exec_silent psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -A -c "
        SELECT a.attname
        FROM   pg_index i
        JOIN   pg_attribute a ON a.attrelid = i.indrelid
                             AND a.attnum = ANY(i.indkey)
        WHERE  i.indrelid = '${SCHEMA}.${CUR_TABLE}'::regclass
        AND    i.indisprimary;
    ")
    
    if [[ -z "$PK_COL" ]]; then
        log_warn "Primary key not found for $CUR_TABLE. Using 'id' as fallback."
        PK_COL="id"
    fi

    # Determine Mode
    if [[ "$CUR_COL" == "FULL" || "$CUR_COL" == "ALL" ]]; then
        MODE="FULL"
        CUR_IDS="ALL_ROWS"
        WHERE_CLAUSE=""
    else
        MODE="PARTIAL ($CUR_COL -> $CUR_IDS)"
        if [[ -z "$CUR_IDS" ]]; then log_error "Config Error: Missing IDs for $CUR_TABLE"; fi
        WHERE_CLAUSE="WHERE ${CUR_COL} IN (${CUR_IDS})"
    fi

    # Generate Temp Name
    TEMP_TABLE="${CUR_TABLE}_tmp_$(date +%s)"
    GLOBAL_TEMP_TABLES+=("$TEMP_TABLE")

    log_info "${BOLD}${CUR_TABLE}${NC} [${MODE}] (PK: $PK_COL)"
    
    # Create Temp
    log_process "Creating temporary table: ${TEMP_TABLE}"
    exec_silent psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -q -c "
        DROP TABLE IF EXISTS ${SCHEMA}.${TEMP_TABLE};
        CREATE TABLE ${SCHEMA}.${TEMP_TABLE} (LIKE ${SCHEMA}.${CUR_TABLE} INCLUDING DEFAULTS);
    "

    # Load Data
    log_process "Loading data from backup..."
    (
        pg_restore -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" --data-only -f - -t "$CUR_TABLE" "$BACKUP_FILE" | \
        sed -E "s/COPY ([\"]?${SCHEMA}[\"]?\.)?[\"]?${CUR_TABLE}[\"]? /COPY ${SCHEMA}.${TEMP_TABLE} /" | \
        psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -q > /dev/null
    ) 2> >(grep -vE "collation version mismatch|DETAIL:|HINT:" >&2)

    # Validation Count
    if [ "$MODE" == "FULL" ]; then
        VAL_SQL="SELECT count(*) FROM ${SCHEMA}.${TEMP_TABLE}"
    else
        VAL_SQL="SELECT count(*) FROM ${SCHEMA}.${TEMP_TABLE} ${WHERE_CLAUSE}"
    fi

    COUNT=$(exec_silent psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -A -c "$VAL_SQL")

    if [[ -z "$COUNT" || "$COUNT" -eq 0 ]]; then
        log_error "No matching rows found in backup for ${CUR_TABLE}."
    fi
    log_success "Loaded ${COUNT} rows successfully."

    # Store in Arrays for Phase 2
    ARR_TABLES+=("$CUR_TABLE")
    ARR_TEMP_TABLES+=("$TEMP_TABLE")
    ARR_COUNTS+=("$COUNT")
    ARR_MODES+=("$MODE")
    ARR_WHERES+=("$WHERE_CLAUSE")
    ARR_PKS+=("$PK_COL")
done


log_header "PHASE 2: APPLYING DATA TO DATABASE"
log_info "Preparing transaction..."

SQL_BLOCK=""
ID_SQL=""
if [ "$OVERRIDE_IDENTITY" = "true" ]; then ID_SQL="OVERRIDING SYSTEM VALUE"; fi
CON_SQL=""
if [ "$DISABLE_CONSTRAINTS" = "true" ]; then CON_SQL="SET session_replication_role = 'replica';"; fi

# Build Logic
LEN=${#ARR_TABLES[@]}
for (( i=0; i<$LEN; i++ )); do
    TBL="${ARR_TABLES[$i]}"
    TMP="${ARR_TEMP_TABLES[$i]}"
    CNT="${ARR_COUNTS[$i]}"
    MDE="${ARR_MODES[$i]}"
    WHR="${ARR_WHERES[$i]}"
    PK="${ARR_PKS[$i]}"

    if [ "$MDE" == "FULL" ]; then
        LOGIC="
        -- 1. Get current count before delete
        SELECT count(*) INTO v_del_cnt FROM ${SCHEMA}.${TBL};
        
        -- 2. Delete Everything (Delete is safer than Truncate for foreign keys)
        DELETE FROM ${SCHEMA}.${TBL}; 
        
        -- 3. Insert
        INSERT INTO ${SCHEMA}.${TBL} $ID_SQL SELECT * FROM ${SCHEMA}.${TMP};
        "
    else
        LOGIC="
        v_del_cnt := 0;
        v_tmp_cnt := 0;

        -- 1. Clean current customer data (Count and Delete)
        WITH d1 AS (DELETE FROM ${SCHEMA}.${TBL} $WHR RETURNING 1)
        SELECT count(*) INTO v_tmp_cnt FROM d1;
        v_del_cnt := v_del_cnt + v_tmp_cnt;
        
        -- 2. Clean conflicting Primary Keys (Count and Delete)
        WITH d2 AS (
            DELETE FROM ${SCHEMA}.${TBL} 
            WHERE $PK IN (SELECT $PK FROM ${SCHEMA}.${TMP} $WHR)
            RETURNING 1
        )
        SELECT count(*) INTO v_tmp_cnt FROM d2;
        v_del_cnt := v_del_cnt + v_tmp_cnt;
        
        -- 3. Insert
        INSERT INTO ${SCHEMA}.${TBL} $ID_SQL SELECT * FROM ${SCHEMA}.${TMP} $WHR;
        "
    fi

    SQL_BLOCK="${SQL_BLOCK}
    ${LOGIC}
    GET DIAGNOSTICS v_ins_cnt = ROW_COUNT;
    IF v_ins_cnt != $CNT THEN
        RAISE EXCEPTION 'Integrity Error on $TBL: Expected % rows, Inserted %', $CNT, v_ins_cnt;
    END IF;
    v_stats := v_stats || '${TBL}|' || v_del_cnt || '|' || $CNT || '#';
    "
done

log_process "Executing transaction..."

# Run psql
RESULT=$(exec_silent psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -A -q <<EOF
\set ON_ERROR_STOP on
BEGIN;

SET statement_timeout = 0;
SET idle_in_transaction_session_timeout = 0;

$CON_SQL

DO \$$
DECLARE
    v_del_cnt INT;
    v_ins_cnt INT;
    v_tmp_cnt INT;
    v_stats TEXT := '';
BEGIN
    $SQL_BLOCK
    PERFORM set_config('my.global_stats', v_stats, false);
END \$$;

COMMIT;
SELECT current_setting('my.global_stats');
EOF
)

if [ $? -ne 0 ]; then
    exit 1 # Trap will handle output
fi

COMMIT_SUCCESS="true"
log_success "Transaction committed successfully."


log_header "PHASE 3: CLEANUP AND FINAL REPORT"

for TMP in "${GLOBAL_TEMP_TABLES[@]}"; do
    log_process "Removing temporary table: ${TMP}"
    exec_silent psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -q -c "DROP TABLE IF EXISTS ${SCHEMA}.${TMP};"
done
log_success "Temporary tables cleaned up."

echo ""
echo -e "${CYAN}==============================================================================${NC}"
echo -e "${BOLD}                       RESTORE SUMMARY                                   ${NC}"
echo -e "${CYAN}==============================================================================${NC}"
printf "%-30s | %-10s | %-10s | %s\n" "TABLE NAME" "OLD" "NEW" "NET CHANGE"
echo "------------------------------------------------------------------------------"

IFS='#' read -ra STAT_ROWS <<< "$RESULT"
for ROW in "${STAT_ROWS[@]}"; do
    if [[ -n "$ROW" ]]; then
        IFS='|' read -r T O N <<< "$ROW"
        DIFF=$((N - O))
        printf "%-30s | %-10s | %-10s | %+d\n" "$T" "$O" "$N" "$DIFF"
    fi
done

echo -e "${CYAN}==============================================================================${NC}"

unset PGPASSWORD
exit 0
