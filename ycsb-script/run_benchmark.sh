#!/bin/bash

# ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Default parameters
threads=6
user_specified_workloads=""
round=1
verbose=false
dbs="rocksdb"

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
    -wl | --workloads)
        user_specified_workloads=$2
        shift
        ;;
    -t | --threads)
        threads=$2
        shift
        ;;
    -r | --round)
        round=$2
        shift
        ;;
    -dbs | --dbs)
        dbs=$2
        shift
        ;;
    -v | --verbose)
        verbose=true
        ;;
    *)
        echo -e "${RED}Unknown parameter passed: $1${NC}"
        exit 1
        ;;
    esac
    shift
done

# Project directories
PROJECT_ROOT="$(cd "$(dirname "$0")" && cd ../ && pwd)"
YCSB_DIR="$PROJECT_ROOT/ycsb-repo"
workload_files_dir="workloads/kv-cache-research"
LOG_DIR_BASE="$PROJECT_ROOT/ycsb-script/benchmark-result"

# Logging function
log() {
    local color=${2:-$NC}
    if [[ $verbose == true ]]; then
        echo -e "${color}$1${NC}"
    fi
}

# Choose search command
if command -v rg &>/dev/null; then
    SEARCH_COMMAND=rg
    log "Using rg for log parsing" $GREEN
else
    SEARCH_COMMAND="grep -E"
    log "rg not found, using grep -E" $YELLOW
fi

# YCSB load phase
ycsb_load() {
    local wf=$1
    local logdir=$2
    local loadlog="$logdir/load_threads_${threads}.log"

    log "Cleaning up $db data directory: $DB_DATA_DIR_BASE" $YELLOW
    rm -rf "$DB_DATA_DIR_BASE"
    mkdir -p "$DB_DATA_DIR_BASE"

    if [[ $db == "memcached" ]]; then
        log "Flushing Memcached server..." $YELLOW
        # Flush all keys in Memcached
        printf "flush_all\r\nquit\r\n" | nc -q 1 localhost 11211
        if [ $? -ne 0 ]; then
            log "Error flushing Memcached server. Ensure it is running." $RED
            return 1
        fi
    fi

    log "Loading YCSB for $db - Workload: $workload..." $GREEN
    ./bin/ycsb load $db -s -P "$wf" -threads "$threads" -p "${db}.dir=$DB_DATA_DIR_BASE" -p "memcached.hosts=127.0.0.1:11211" >"$loadlog" 2>&1
    if [ $? -ne 0 ]; then
        log "Error during YCSB Load for $db (Workload: $workload). Check log: $loadlog" $RED
        return 1
    fi
    log "YCSB Load for $db (Workload: $workload) completed successfully." $GREEN
}

# YCSB run phase
ycsb_run() {
    local wf=$1
    local logdir=$2
    local rn=$3
    local rawlog="$logdir/run_threads_${threads}_round_${rn}_raw.log"

    log "Running YCSB Round $rn of $round (DB: $db, Workload: $workload)..." $GREEN
    ./bin/ycsb run $db -s -P "$wf" -threads "$threads" -p "${db}.dir=$DB_DATA_DIR_BASE" -p "memcached.hosts=127.0.0.1:11211" >"$rawlog" 2>&1
    if [ $? -ne 0 ]; then
        log "Error during YCSB Run Round $rn (DB: $db, Workload: $workload). Check log: $rawlog" $RED
    # else
    #     log "YCSB Run Round $rn for $db (Workload: $workload) completed successfully." $GREEN
    fi
}

# Summarize results
summarize() {
    local dir="$LOG_DIR_BASE/$db/$workload"
    for i in $(seq 1 $round); do
        local rawlog="$dir/run_threads_${threads}_round_${i}_raw.log"
        local sumlog="$dir/run_threads_${threads}_round_${i}.log"
        if [ -f "$rawlog" ]; then
            $SEARCH_COMMAND "\[(OVERALL|READ|READ-MODIFY-WRITE|CLEANUP|UPDATE|UPDATE-FAILED|INSERT|INSERT-FAILED|SCAN)\]" "$rawlog" >"$sumlog"
        else
            log "Run log file not found for summary: $rawlog" $RED
        fi
    done
}

main() {
    cd "$YCSB_DIR" || {
        echo -e "${RED}Failed to change directory to $YCSB_DIR. Exiting.${NC}"
        exit 1
    }

    # Build workload list
    local workloads_to_run=()
    if [[ -n $user_specified_workloads ]]; then
        read -r -a workloads_to_run <<<"$user_specified_workloads"
        log "Using user-specified workloads: ${workloads_to_run[*]}" $GREEN
    else
        log "Scanning directory for workloads: $workload_files_dir" $YELLOW
        for f in "$workload_files_dir"/*; do
            [[ -f "$f" ]] && workloads_to_run+=("$(basename "$f")")
        done
    fi
    [[ ${#workloads_to_run[@]} -eq 0 ]] && {
        echo -e "${RED}No workloads found. Exiting.${NC}"
        exit 1
    }

    # Sort by data-size suffix: test, 10G, 40G
    local sorted=()
    for size in test 10G 40G; do
        for w in "${workloads_to_run[@]}"; do
            if [[ $w == *_$size ]]; then
                sorted+=("$w")
            fi
        done
    done
    workloads_to_run=("${sorted[@]}")
    log "Workload order: ${workloads_to_run[*]}" $BLUE

    for db in $dbs; do
        DB_DATA_DIR_BASE="$PROJECT_ROOT/ycsb-script/${db}-dir"
        log "==================================================" $YELLOW
        log "Starting benchmarks for Database: $db" $YELLOW
        log "==================================================" $YELLOW

        local cur_size=""
        for workload in "${workloads_to_run[@]}"; do
            size=${workload##*_}
            local dir="$LOG_DIR_BASE/$db/$workload"
            mkdir -p "$dir"

            # Only load data when size changes
            if [[ $size != $cur_size ]]; then
                cur_size=$size
                log "--------------------------------------------------" $PURPLE
                log "Switching data size to: $cur_size for DB: $db" $PURPLE
                log "Clearing data dir for size $cur_size (DB: $db)" $YELLOW
                rm -rf "$DB_DATA_DIR_BASE" && mkdir -p "$DB_DATA_DIR_BASE"

                # Load phase for this size
                ycsb_load "$workload_files_dir/$workload" "$dir" || {
                    echo
                    continue
                }
            fi

            # Run rounds for each workload (no reload)
            for i in $(seq 1 $round); do
                ycsb_run "$workload_files_dir/$workload" "$dir" $i
            done

            # Summarize
            summarize
            log "Finished benchmark for DB: $db, Workload: $workload" $CYAN
        done

        log "==================================================" $YELLOW
        log "All workloads processed for Database: $db" $YELLOW
        log "==================================================" $YELLOW
    done

    log "Benchmark script completed for all databases." $GREEN
}

main "$@"
