import json
import sys
from pathlib import Path

# 读取命令行参数
backend = sys.argv[1].lower() if len(sys.argv) > 1 else "cachelib"

# 根据参数设置输出目录和cache_config里backend字段
if backend == "cachelib":
    output_dir = Path("./cachelib_configs")
    backend_field = None
elif backend == "rocksdb":
    output_dir = Path("./rocksdb_configs")
    backend_field = "rocksdb"
elif backend == "memcached":
    output_dir = Path("./memcached_configs")
    backend_field = "memcached"
else:
    print(f"Warning: Unknown backend '{backend}', defaulting to cachelib")
    output_dir = Path("./cachelib_configs")
    backend_field = None

output_dir.mkdir(parents=True, exist_ok=True)

# 基础cache配置
base_cache_config = {
    "cacheSizeMB": 15360,
    "poolRebalanceIntervalSec": 1,
    "moveOnSlabRelease": False,
    "numPools": 1
}

# 如果有指定 backend，加入字段
if backend_field:
    base_cache_config["backend"] = backend_field

# KV 模式定义

kv_modes = {
    "KV-small": {
        "keySizeRange": [4, 8],
        "keySizeRangeProbability": [1],
        "valSizeRange": [32, 128],
        "valSizeRangeProbability": [1]  # 修正为匹配两值
    },
    "KV-mixed": {
        "keySizeRange": [4, 16, 64],
        "keySizeRangeProbability": [0.3, 0.7],
        "valSizeRange": [64, 512, 4096],
        "valSizeRangeProbability": [0.5, 0.5]
    },
    "KV-large": {
        "keySizeRange": [4, 64],
        "keySizeRangeProbability": [1],
        "valSizeRange": [64, 512, 10240, 409200],
        "valSizeRangeProbability": [0.1, 0.2, 0.7]
    }
}





# 读写负载定义
workloads = {
    "balanced": (0.5, 0.5),
    "readonly": (1.0, 0.0),
    "readheavy": (0.95, 0.05),
    "setheavy": (0.05, 0.95)
}

# 数据量（设置 numKeys）

data_sizes = {
    "KV-small":{
        "2G" : 1431655,
    },
    "KV-mixed":{
        "2G" : 1543841,
    },
    "KV-large":{
        "2G" : 112386,
    }
}



# 固定测试参数
fixed_test_params = {
    "numOps": 100000,
    "numThreads": 6,
    "distribution": "range",
    "opDelayBatch": 1,
    "opDelayNs": 200,
    "delRatio": 0.0
}

for workload_name, (get_ratio, set_ratio) in workloads.items():
    for kv_name, kv_params in kv_modes.items():
        kv_data_sizes = data_sizes[kv_name]  # 取出对应KV模式的数据量设置
        for size_label, num_keys in kv_data_sizes.items():
            test_config = {
                **fixed_test_params,
                "getRatio": get_ratio,
                "setRatio": set_ratio,
                "numKeys": num_keys,
                **kv_params
            }

            full_config = {
                "cache_config": base_cache_config,
                "test_config": test_config
            }

            filename = f"{workload_name}_{kv_name}_{size_label}.json"
            filepath = output_dir / filename

            with open(filepath, "w") as f:
                json.dump(full_config, f, indent=2)





print(f"Generated configs in: {output_dir.resolve()}")
