// Copyright (c) Meta Platforms, Inc. and affiliates.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#pragma once

#include <atomic>
#include <chrono>
#include <memory>
#include <optional>
#include <random>
#include <thread>
#include <vector>

#include <folly/Random.h>
#include <folly/TokenBucket.h>

#include "cachelib/cachebench/cache/RocksDbCache.h"
#include "cachelib/cachebench/runner/Stressor.h"
#include "cachelib/cachebench/util/Config.h"
#include "cachelib/cachebench/util/Request.h"
#include "cachelib/cachebench/workload/GeneratorBase.h"

namespace facebook::cachelib::cachebench {

/**
 * A stressor that drives a RocksDB‑backed cache with a WorkloadGenerator.
 * It implements the same public API as CacheStressor so the runner code
 * can treat them interchangeably.
 */
class RocksDbStressor final : public Stressor {
 public:
  RocksDbStressor(const CacheConfig& cfg, const StressorConfig& sCfg);
  ~RocksDbStressor() override;

  // ---- Stressor interface ----
  void start() override;
  void finish() override;
  Stats           getCacheStats() const override;
  ThroughputStats aggregateThroughputStats() const override;
  uint64_t        getTestDurationNs() const override;

 private:
  // Thread body
  void worker(uint64_t tid);

  // Fetch next synthetic request
  const Request& getReq(const PoolId& pid,
                        std::mt19937_64& gen,
                        std::optional<uint64_t>& lastRid);

  // ---------------- data members ----------------
  CacheConfig                     cfg_;
  StressorConfig                  sCfg_;

  std::unique_ptr<RocksDbCache>   cache_;
  std::unique_ptr<GeneratorBase>  wg_;

  std::vector<std::thread>        threads_;
  std::vector<ThroughputStats>    thrStats_;

  std::atomic<bool>               stop_{false};

  // optional ops‑per‑second limiter
  std::unique_ptr<folly::BasicTokenBucket<>> rateLimiter_;

  // timing
  std::chrono::steady_clock::time_point startTime_;
  std::chrono::steady_clock::time_point endTime_;
};

} // namespace facebook::cachelib::cachebench

