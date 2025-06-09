#!/bin/bash
# 监控 /dev/sda 的读写速率（KB/s 和 IOPS）

# 提取指定设备行的“扇区数读取”（第 6 列）和“扇区数写入”（第 10 列）
get_stats() {
  # 注意调整 'sda' 为你的设备名
  awk '$3=="sda" {print $6, $10}' /proc/diskstats
}

# 第一次取样
read prev_read prev_write < <(get_stats)
prev_ts=$(date +%s)

while true; do
  sleep 1
  read cur_read cur_write < <(get_stats)
  cur_ts=$(date +%s)
  dt=$((cur_ts - prev_ts))

  # 计算差值
  delta_read=$((cur_read - prev_read))
  delta_write=$((cur_write - prev_write))

  # 扇区转字节，再转 KB
  kb_read=$((delta_read * 512 / 1024))
  kb_write=$((delta_write * 512 / 1024))

  # IOPS 就是操作次数差（reads completed + writes completed），
  # 如果想更精细，可以取 $4（读操作次数）和 $8（写操作次数）两列
  # 这里简单用扇区数算“块 IOPS”
  iops=$((delta_read + delta_write))

  echo "$(date +'%H:%M:%S')  Read: ${kb_read}KB/s  Write: ${kb_write}KB/s  Total IOPS: ${iops}/s"

  # 为下一次循环保存
  prev_read=$cur_read
  prev_write=$cur_write
  prev_ts=$cur_ts
done
