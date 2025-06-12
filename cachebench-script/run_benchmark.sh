#!/bin/bash

# 默认配置
TEST_MODE=false
DBS=("cachelib")  # 默认只跑 cachelib

# 时间戳函数
timestamp() {
  date +"%Y%m%d_%H%M%S"
}

# 解析参数
while [[ $# -gt 0 ]]; do
  case $1 in
    -dbs)
      shift
      IFS=' ' read -r -a DBS <<< "$1"
      ;;
    -test)
      TEST_MODE=true
      ;;
    *)
      echo "未知参数: $1"
      exit 1
      ;;
  esac
  shift
done

# 可执行文件路径
BENCH="../cachebench-repo/opt/cachelib/bin/cachebench"

# 路径检查
if [ ! -x "$BENCH" ]; then
  echo "CacheBench 可执行文件未找到: $BENCH"
  exit 1
fi

# 创建公共日志目录
mkdir -p "./logs"
mkdir -p "./result"

for DB in "${DBS[@]}"; do
  CONFIG_DIR="./${DB}_configs"
  RESULT_DIR="./result/${DB}"
  LOG_DIR="./logs"

  if [ ! -d "$CONFIG_DIR" ]; then
    echo "配置目录不存在: $CONFIG_DIR"
    continue
  fi

  mkdir -p "$RESULT_DIR"

  echo "开始运行 $DB 测试..."

  if [ "$TEST_MODE" = true ]; then
    JSON_FILES=("$CONFIG_DIR/test.json")
  else
    JSON_FILES=("$CONFIG_DIR"/*.json)
  fi

  for json_file in "${JSON_FILES[@]}"; do
    if [ ! -f "$json_file" ]; then
      echo "未找到文件: $json_file"
      continue
    fi

    base_name=$(basename "$json_file" .json)
    ts=$(timestamp)
    log_file_success="$RESULT_DIR/${base_name}_${ts}.log"
    log_file_fail="$LOG_DIR/${DB}_${base_name}_${ts}.log"

    echo "运行配置: $json_file"
    echo "保存日志至: $log_file_success"

    "$BENCH" --json_test_config "$json_file" 2>&1 | tee "$log_file_success"

    if [ "${PIPESTATUS[0]}" -eq 0 ]; then
      echo "成功: $json_file"
    else
      mv "$log_file_success" "$log_file_fail"
      echo "失败: $json_file，日志已移动到 $log_file_fail"
    fi

    echo "--------------------------------------------------"
  done

  echo "完成 $DB 所有测试。"
done
