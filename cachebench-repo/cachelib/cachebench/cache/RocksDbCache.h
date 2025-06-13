#pragma once
#include <memory>
#include <string>

#include <folly/String.h>
#include <rocksdb/db.h>
#include <rocksdb/options.h>

#include "cachelib/cachebench/util/CacheConfig.h"               // 配置字段
#include "cachelib/cachebench/cache/CacheStats.h"               // Stats 结构

namespace facebook::cachelib::cachebench {

// 用别名，省得写长名字
using Stats = facebook::cachelib::cachebench::Stats;

// 轻量包装：不继承 CacheLib 的模板 Cache
class RocksDbCache {
 public:
  explicit RocksDbCache(const CacheConfig& cfg);
  ~RocksDbCache();                                   // 需要明确声明

  bool set(const std::string& key,
           folly::StringPiece value,
           uint32_t ttlSec = 0);

  bool get(const std::string& key,
           std::string& out);

  bool del(const std::string& key);

  size_t size() const;
  void   reset();

  const Stats& getStats() const { return stats_; }

 private:
  std::unique_ptr<rocksdb::DB> db_;
  rocksdb::ReadOptions         ro_;
  rocksdb::WriteOptions        wo_;
  Stats                        stats_;
};

} // namespace facebook::cachelib::cachebench

