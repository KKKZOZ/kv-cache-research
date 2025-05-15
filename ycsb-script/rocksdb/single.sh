#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 默认参数
threads=8
workload="readheavy_10G"
round=1
verbose=false

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
    -v | --verbose) verbose=true ;;
    *)
        echo "Unknown parameter passed: $1"
        exit 1
        ;;
    esac
    shift
done

PROJECT_ROOT="$(cd "$(dirname "$0")" && cd ../../ && pwd)"
YCSB_DIR="$PROJECT_ROOT/ycsb-repo"
ROCKSDB_DATA_DIR_BASE="$PROJECT_ROOT/ycsb-script/rocksdb-dir"
LOG_DIR="$PROJECT_ROOT/ycsb-script/rocksdb"

log() {
    local color=${2:-$NC}
    if [[ "${verbose}" = true ]]; then
        echo -e "${color}$1${NC}"
    fi
}

mkdir -p "$LOG_DIR"

cd "$YCSB_DIR"

# echo "Starting YCSB benchmark with Workload: $workload, Threads: $threads, Rounds: $round"

for i in $(seq 1 "$round"); do
    log "--------------------------------------------------" "$GREEN"
    log "Starting Round $i of $round" "$GREEN"
    log "--------------------------------------------------" "$GREEN"

    LOAD_LOG_FILE="$LOG_DIR/load_${workload}_threads_${threads}_round_${i}.log"
    RUN_LOG_FILE="$LOG_DIR/run_${workload}_threads_${threads}_round_${i}.log"

    log "Cleaning up RocksDB data directory for round $i: $ROCKSDB_DATA_DIR_BASE" "$YELLOW"
    rm -rf "$ROCKSDB_DATA_DIR_BASE"
    mkdir -p "$ROCKSDB_DATA_DIR_BASE"

    log "Running YCSB Load for Round $i..." "$GREEN"
    log "Workload file: workloads/ours/$workload" "$BLUE"
    log "RocksDB data directory: $ROCKSDB_DATA_DIR_BASE" "$BLUE"
    log "Load log file: $LOAD_LOG_FILE" "$BLUE"

    # 执行 YCSB load 命令
    ./bin/ycsb load rocksdb -s -P "workloads/ours/$workload" -threads "$threads" -p rocksdb.dir="$ROCKSDB_DATA_DIR_BASE" >"$LOAD_LOG_FILE" 2>&1

    if [ $? -ne 0 ]; then
        log "Error during YCSB Load for Round $i. Check log: $LOAD_LOG_FILE" "$RED"
        # exit 1 # 或者 continue 到下一轮，或者记录错误并继续
        continue
    fi

    log "Running YCSB Run for Round $i..." "$GREEN"
    log "Run log file: $RUN_LOG_FILE" "$BLUE"

    # 执行 YCSB run 命令
    ./bin/ycsb run rocksdb -s -P "workloads/ours/$workload" -threads "$threads" -p rocksdb.dir="$ROCKSDB_DATA_DIR_BASE" >"$RUN_LOG_FILE" 2>&1
    if [ $? -ne 0 ]; then
        log "Error during YCSB Run for Round $i. Check log: $RUN_LOG_FILE" "$RED"
        # exit 1 # 或者 continue，或者记录错误并继续
    fi

    log "Finished Round $i of $round" "$GREEN"
done

log "--------------------------------------------------" "$YELLOW"
log "All rounds completed." "$YELLOW"
log "Logs are in: $LOG_DIR" "$YELLOW"
log "--------------------------------------------------" "$YELLOW"
