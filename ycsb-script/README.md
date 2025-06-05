
# YCSB Benchmark Automation Script

This script automates the process of running YCSB (Yahoo! Cloud Serving Benchmark) tests for one or more workloads against a specified database. It handles data loading, multiple run rounds, and result summarization.

## Usage

Execute the script from its location (e.g., within the `ycsb-script` directory or using its full path):

```bash
./run_benchmark.sh [OPTIONS]
```

### Options

The script accepts the following command-line options:

* `-wl <workloads_list>`, `--workloads <workloads_list>`

  * Specifies a list of YCSB workload files to run.
  * The list should be a single string with workload names separated by spaces (e.g., `"workloada workloadb workloadc"`).
  * These workload files are expected to be found in the `$YCSB_DIR/workloads/kv-cache-research/` directory.
  * If this option is not provided or is an empty string, the script will automatically discover and run **all workload files** found in `$YCSB_DIR/workloads/kv-cache-research/`.
  * Default: (empty string - scans directory)

* `-t <num_threads>`, `--threads <num_threads>`

  * Sets the number of client threads YCSB will use for the load and run phases.
  * Default: `6`

* `-r <num_rounds>`, `--round <num_rounds>`

  * Sets the number of times the 'run' phase of YCSB will be executed for each workload after the initial 'load' phase.
  * Default: `1`

* `-db <database_name>`, `--database <database_name>`

  * Specifies the YCSB database binding to use (e.g., `rocksdb`, `mongodb`, `cassandra`).
  * Default: `rocksdb`

* `-v`, `--verbose`

  * Enables verbose logging to the console, showing detailed steps and commands being executed.
  * Default: Disabled

### Output

* **Log Files**: Raw logs for YCSB load and run phases are stored in:
    `PROJECT_ROOT/ycsb-script/benchmark-result/<database_name>/<workload_name>/`
  * Load logs: `load_threads_<threads>.log`
  * Raw run logs: `run_threads_<threads>_round_<round_num>_raw.log`
* **Summary Files**: Summarized results (extracted from raw run logs) are stored in the same directory:
    `run_threads_<threads>_round_<round_num>.log`
* **Data Directory**: A temporary data directory for the database being tested is created at:
    `PROJECT_ROOT/ycsb-script/<database_name>-dir/`. This directory is cleaned up before each new workload's load phase.

## Examples

1. **Run all workloads in the default directory against RocksDB with default settings:**

    ```bash
    ./run_benchmark.sh
    ```

2. **Run specific workloads ("workloada" and "workloadc") against Memcached with 32 threads and 3 rounds, with verbose output:**

    ```bash
    ./run_benchmark.sh -wl "workloada workloadc" -db memcached -t 32 -r 3 -v
    ```

3. **Run a single workload "my\_custom\_workload" against RocksDB with 8 threads:**

    ```bash
    ./run_benchmark.sh --workloads "my_custom_workload" --threads 8
    ```

    (Ensure `my_custom_workload` exists in `$YCSB_DIR/workloads/kv-cache-research/`)
