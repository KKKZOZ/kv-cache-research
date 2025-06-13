#include "cachelib/cachebench/cache/RocksDbCache.h"

#include <stdexcept>

namespace facebook::cachelib::cachebench {

RocksDbCache::RocksDbCache(const CacheConfig& cfg) {
  rocksdb::Options opts;
  opts.create_if_missing = true;
  auto s = rocksdb::DB::Open(opts, "/tmp/cachebench_rocks", &db_);
  if (!s.ok()) {
    throw std::runtime_error(s.ToString());
  }
 // wo_.disableWAL = cfg.disableWAL();
}

RocksDbCache::~RocksDbCache() = default;

bool RocksDbCache::set(const std::string& key,
                       folly::StringPiece value,
                       uint32_t /*ttlSec*/) {
  auto s = db_->Put(wo_, key,
                    rocksdb::Slice(value.data(), value.size()));
  if (s.ok()) {
    stats_.allocAttempts++;          // 随便占个字段示例
  }
  return s.ok();
}

bool RocksDbCache::get(const std::string& key,
                       std::string& out) {
  auto s = db_->Get(ro_, key, &out);
  if (s.IsNotFound()) {
    stats_.numCacheGetMiss++;
    return false;
  }
  if (!s.ok()) {
    return false;
  }
  stats_.numCacheGets++;
  return true;
}

bool RocksDbCache::del(const std::string& key) {
  return db_->Delete(wo_, key).ok();
}

size_t RocksDbCache::size() const {
  uint64_t sz{0};
  db_->GetIntProperty("rocksdb.estimate-live-data-size", &sz);
  return static_cast<size_t>(sz);
}

void RocksDbCache::reset() {
  db_.reset();
}

} // namespace facebook::cachelib::cachebench

