#! /bin/bash

./bin/ycsb load rocksdb -s -P workloads/workloada -p rocksdb.dir=./rocksdb-dir >../load_output.txt
