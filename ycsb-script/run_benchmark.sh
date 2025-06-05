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
user_specified_workloads=""
round=1
verbose=false
db=rocksdb

while [[ "$#" -gt 0 ]]; do
    case $1 in
    -wl | --workloads)
        user_specified_workloads="$2"
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
        echo -e "${RED}Unknown parameter passed: $1${NC}"
        exit 1
        ;;
    esac
    shift
done

PROJECT_ROOT="$(cd "$(dirname "$0")" && cd ../ && pwd)"
YCSB_DIR="$PROJECT_ROOT/ycsb-repo"
DB_DATA_DIR_BASE="$PROJECT_ROOT/ycsb-script/${db}-dir"
LOG_DIR_BASE="$PROJECT_ROOT/ycsb-script/benchmark-result"

# Global workload variable that will be updated in the loop
workload=""

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
    local current_log_dir="$LOG_DIR_BASE/${db}/${workload}"

    for i in $(seq 1 "$round"); do
        RAW_RUN_LOG_FILE="$current_log_dir/run_threads_${threads}_round_${i}_raw.log"
        SUMMARY_LOG_FILE="$current_log_dir/run_threads_${threads}_round_${i}.log"

        if [ -f "$RAW_RUN_LOG_FILE" ]; then
            "$SEARCH_COMMAND" "\[(OVERALL|READ|READ-MODIFY-WRITE|CLEANUP|UPDATE|INSERT|SCAN)\]" "$RAW_RUN_LOG_FILE" >"$SUMMARY_LOG_FILE"
            log "Summary created: $SUMMARY_LOG_FILE" "$BLUE"
        else
            log "Run log file not found for summary: $RAW_RUN_LOG_FILE" "$RED"
        fi
    done
}

main() {
    cd "$YCSB_DIR" || {
        echo -e "${RED}Error: Failed to change directory to $YCSB_DIR. Exiting.${NC}"
        exit 1
    }

    local workloads_to_run=()
    local workload_files_dir="workloads/kv-cache-research" # Relative to YCSB_DIR

    if [ -n "$user_specified_workloads" ]; then
        log "Using user-specified workloads: \"$user_specified_workloads\"" "$GREEN"
        # Parse the space-separated string into an array
        read -r -a workloads_to_run <<<"$user_specified_workloads"
    else
        log "No user-specified workloads. Scanning directory: $YCSB_DIR/$workload_files_dir for workloads." "$YELLOW"
        if [ ! -d "$workload_files_dir" ]; then
            log "Workload directory '$YCSB_DIR/$workload_files_dir' not found. Exiting." "$RED"
            exit 1
        fi

        # Populate from directory
        for file_path in "$workload_files_dir"/*; do
            if [ -f "$file_path" ]; then
                workloads_to_run+=("$(basename "$file_path")")
            fi
        done
    fi

    if [ ${#workloads_to_run[@]} -eq 0 ]; then
        if [ -n "$user_specified_workloads" ]; then
            log "User-specified workloads list \"$user_specified_workloads\" resulted in an empty set or all names were invalid. Exiting." "$RED"
        else
            log "No workload files found in $YCSB_DIR/$workload_files_dir. Exiting." "$RED"
        fi
        exit 1
    fi

    log "Final list of workloads to process:" "$GREEN"
    for workload in "${workloads_to_run[@]}"; do
        log "  + $workload" "$GREEN"
    done
    echo

    # Loop for each workload
    for current_workload_item in "${workloads_to_run[@]}"; do
        workload="$current_workload_item" # Set global workload

        local current_workload_log_dir="$LOG_DIR_BASE/${db}/${workload}"
        mkdir -p "$current_workload_log_dir"

        log "--------------------------------------------------" "$PURPLE"
        log "Starting Benchmark for Workload: $workload" "$PURPLE"
        log "--------------------------------------------------" "$PURPLE"
        log "Database: $db, Threads: $threads, Run Rounds: $round" "$GREEN"

        if [ ! -f "$workload_files_dir/$workload" ]; then
            log "Workload file '$workload_files_dir/$workload' not found. Skipping this workload." "$RED"
            echo
            continue
        fi

        log "Cleaning up $db data directory: $DB_DATA_DIR_BASE (for workload $workload)" "$YELLOW"
        rm -rf "$DB_DATA_DIR_BASE"
        mkdir -p "$DB_DATA_DIR_BASE"

        LOAD_LOG_FILE="$current_workload_log_dir/load_threads_${threads}.log"

        log "Loading YCSB for $db - Workload: $workload..." "$GREEN"

        ./bin/ycsb load "$db" -s -P "$workload_files_dir/$workload" -threads "$threads" -p "${db}.dir=$DB_DATA_DIR_BASE" >"$LOAD_LOG_FILE" 2>&1

        if [ $? -ne 0 ]; then
            log "Error during YCSB Load for $db (Workload: $workload). Check log: $LOAD_LOG_FILE" "$RED"
            log "Skipping runs for this workload and proceeding to the next." "$RED"
            echo
            continue
        fi
        log "YCSB Load phase for $db (Workload: $workload) completed successfully." "$GREEN"

        # --- YCSB Run Phase (multiple rounds) ---
        for i in $(seq 1 "$round"); do
            log "--------------------------------------------------" "$CYAN"
            log "Starting Run Round $i of $round for Workload: $workload (DB: $db)" "$CYAN"
            log "--------------------------------------------------" "$CYAN"

            RUN_LOG_FILE_RAW="$current_workload_log_dir/run_threads_${threads}_round_${i}_raw.log"

            log "Running YCSB for Round $i (DB: $db, Workload: $workload)..." "$GREEN"

            ./bin/ycsb run "$db" -s -P "$workload_files_dir/$workload" -threads "$threads" -p "${db}.dir=$DB_DATA_DIR_BASE" >"$RUN_LOG_FILE_RAW" 2>&1

            if [ $? -ne 0 ]; then
                log "Error during YCSB Run for Round $i (DB: $db, Workload: $workload). Check log: $RUN_LOG_FILE_RAW" "$RED"
            else
                log "YCSB Run for Round $i (DB: $db, Workload: $workload) completed successfully." "$GREEN"
            fi
            log "Finished Run Round $i of $round for Workload: $workload (DB: $db)" "$CYAN"
        done

        summarize

        log "--------------------------------------------------" "$PURPLE"
        log "Finished benchmark for Workload: $workload" "$PURPLE"
        log "--------------------------------------------------" "$PURPLE"
        echo

    done # End of workloads loop

    log "==================================================" "$YELLOW"
    log "All specified workloads have been processed for database $db." "$YELLOW"
    log "Base log directory: $LOG_DIR_BASE/${db}" "$YELLOW"
    log "==================================================" "$YELLOW"
}

main "$@"
