#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 默认参数
threads=6
workload="readheavy_10G"
round=1
verbose=false
db=rocksdb

# 解析命令行参数
while [[ "$#" -gt 0 ]]; do
    case $1 in
    -wl | --workload)
        workload="$2"
        shift
        ;;
    -t | --threads)
        threads="$2"
        shift
        ;;
    -r | --round)
        round="$2"
        shift
        ;;
    -db | --database)
        db="$2"
        shift
        ;;
    -v | --verbose) verbose=true ;;
    *)
        echo "Unknown parameter passed: $1"
        exit 1
        ;;
    esac
    shift
done

PROJECT_ROOT="$(cd "$(dirname "$0")" && cd ../ && pwd)"
YCSB_DIR="$PROJECT_ROOT/ycsb-repo"
DB_DATA_DIR_BASE="$PROJECT_ROOT/ycsb-script/${db}-dir"
LOG_DIR="$PROJECT_ROOT/ycsb-script/benchmark-result/${db}"

log() {
    local color=${2:-$NC}
    if [[ "${verbose}" = true ]]; then
        echo -e "${color}$1${NC}"
    fi
}

if command -v rg &>/dev/null; then
    SEARCH_COMMAND="rg"
    log "Using rg command for log parsing." "$GREEN"
else
    SEARCH_COMMAND="grep -E"
    log "rg command not found, falling back to grep -E for log parsing." "$YELLOW"
fi

summarize() {
    log "Extracting and summarizing results..." "$YELLOW"

    for i in $(seq 1 "$round"); do
        RAW_RUN_LOG_FILE="$LOG_DIR/${workload}_run_threads_${threads}_round_${i}_raw.log"

        SUMMARY_LOG_FILE="$LOG_DIR/${workload}_run_threads_${threads}_round_${i}.log"

        if [ -f "$RAW_RUN_LOG_FILE" ]; then
            "$SEARCH_COMMAND" "\[(OVERALL|READ|READ-MODIFY-WRITE|CLEANUP|UPDATE|INSERT|SCAN)\]" "$RAW_RUN_LOG_FILE" >"$SUMMARY_LOG_FILE"
        else
            log "Run log file not found: $RAW_RUN_LOG_FILE" "$RED"
        fi
    done
}

main() {
    mkdir -p "$LOG_DIR"

    cd "$YCSB_DIR"

    log "--------------------------------------------------" "$GREEN"
    log "Benchmark Setup" "$GREEN"
    log "Database: $db, Workload: $workload, Threads: $threads, Run Rounds: $round" "$GREEN"
    log "--------------------------------------------------" "$GREEN"

    log "Cleaning up $db data directory: $DB_DATA_DIR_BASE" "$YELLOW"
    rm -rf "$DB_DATA_DIR_BASE"
    mkdir -p "$DB_DATA_DIR_BASE"

    LOAD_LOG_FILE="$LOG_DIR/${workload}_load_threads_${threads}.log"

    log "Running YCSB Load (once) for $db..." "$GREEN"
    log "Workload file: workloads/kv-cache-research/$workload" "$BLUE"
    log "$db data directory: $DB_DATA_DIR_BASE" "$BLUE"
    log "Load log file: $LOAD_LOG_FILE" "$BLUE"

    ./bin/ycsb load "$db" -s -P "workloads/kv-cache-research/$workload" -threads "$threads" -p "${db}.dir=$DB_DATA_DIR_BASE" >"$LOAD_LOG_FILE" 2>&1

    if [ $? -ne 0 ]; then
        log "Error during YCSB Load for $db. Check log: $LOAD_LOG_FILE" "$RED"
        log "Exiting due to load failure." "$RED"
        exit 1
    fi
    log "YCSB Load phase for $db completed successfully." "$GREEN"

    # --- YCSB Run Phase (multiple rounds) ---
    for i in $(seq 1 "$round"); do
        log "--------------------------------------------------" "$CYAN"
        log "Starting Run Round $i of $round for $db" "$CYAN"
        log "--------------------------------------------------" "$CYAN"

        RUN_LOG_FILE="$LOG_DIR/${workload}_run_threads_${threads}_round_${i}_raw.log"

        log "Running YCSB Run for Round $i (DB: $db)..." "$GREEN"
        log "Workload file (for run parameters): workloads/kv-cache-research/$workload" "$BLUE"
        log "$db data directory (reusing loaded data): $DB_DATA_DIR_BASE" "$BLUE"
        log "Run log file: $RUN_LOG_FILE" "$BLUE"

        # 执行 YCSB run 命令
        ./bin/ycsb run "$db" -s -P "workloads/kv-cache-research/$workload" -threads "$threads" -p "${db}.dir=$DB_DATA_DIR_BASE" >"$RUN_LOG_FILE" 2>&1

        if [ $? -ne 0 ]; then
            log "Error during YCSB Run for Round $i (DB: $db). Check log: $RUN_LOG_FILE" "$RED"
        else
            log "YCSB Run for Round $i (DB: $db) completed successfully." "$GREEN"
        fi

        log "Finished Run Round $i of $round for $db" "$CYAN"
    done

    summarize

    log "--------------------------------------------------" "$YELLOW"
    log "All run rounds completed for $db." "$YELLOW"
    log "Logs are in: $LOG_DIR" "$YELLOW"
    log "--------------------------------------------------" "$YELLOW"
}

main "$@"
