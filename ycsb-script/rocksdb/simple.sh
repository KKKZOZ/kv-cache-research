#! /bin/bash

PROJECT_ROOT="$(cd "$(dirname "$0")" && cd ../../ && pwd)"

cd "$PROJECT_ROOT/ycsb-repo"

rm -rf "$PROJECT_ROOT/ycsb-script/rocksdb-dir"

./bin/ycsb load rocksdb -s -P workloads/workloada -p rocksdb.dir="$PROJECT_ROOT/ycsb-script/rocksdb-dir" >"$PROJECT_ROOT/ycsb-script/load_output.txt"

./bin/ycsb run rocksdb -s -P workloads/workloada -p rocksdb.dir="$PROJECT_ROOT/ycsb-script/rocksdb-dir" >"$PROJECT_ROOT/ycsb-script/run_output.txt"
