// Copyright (c) Meta Platforms, Inc. and affiliates.
// Licensed under the Apache License, Version 2.0 (the "License");
// You may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//     http://www.apache.org/licenses/LICENSE-2.0
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#include "cachelib/cachebench/runner/RocksDbStressor.h"

#include <folly/Random.h>
#include <folly/system/ThreadName.h>
#include <iostream>
#include <random>

#include "cachelib/cachebench/util/Exceptions.h"
#include "cachelib/cachebench/workload/WorkloadGenerator.h"

namespace facebook::cachelib::cachebench {

// -------------------- ctor / dtor ----------------------------------------- //
RocksDbStressor::RocksDbStressor(const CacheConfig& cfg,
                                 const StressorConfig& sCfg)
    : cfg_{cfg},
      sCfg_{sCfg},
      cache_{std::make_unique<RocksDbCache>(cfg_)},
      wg_{std::make_unique<WorkloadGenerator>(sCfg_)},
      thrStats_(sCfg_.numThreads) {
  if (sCfg_.opRatePerSec > 0) {
    rateLimiter_ = std::make_unique<folly::BasicTokenBucket<>>(sCfg_.opRatePerSec,
                                                              sCfg_.opRatePerSec);
  }
}

RocksDbStressor::~RocksDbStressor() { finish(); }

// -------------------- public API ------------------------------------------ //
void RocksDbStressor::start() {
  startTime_ = std::chrono::steady_clock::now();
  for (uint64_t t = 0; t < sCfg_.numThreads; ++t) {
    threads_.emplace_back([this, t] {
      folly::setThreadName(folly::sformat("rocksdb_stressor_{}", t));
      std::cout << "[Thread " << t << "] started\n";
      worker(t);
      std::cout << "[Thread " << t << "] finished\n";
    });
  }
}

void RocksDbStressor::finish() {
  // Wait for worker threads to finish naturally (each runs numOps operations)
  for (auto& th : threads_) {
    if (th.joinable()) {
      th.join();
    }
  }
  threads_.clear();
  endTime_ = std::chrono::steady_clock::now();
  if (wg_) {
    wg_->markShutdown();
  }
}

Stats RocksDbStressor::getCacheStats() const { return cache_->getStats(); }

ThroughputStats RocksDbStressor::aggregateThroughputStats() const {
  ThroughputStats agg;
  for (const auto& s : thrStats_) {
    agg += s;
  }
  return agg;
}

uint64_t RocksDbStressor::getTestDurationNs() const {
  return std::chrono::duration_cast<std::chrono::nanoseconds>(endTime_ - startTime_)
      .count();
}

// -------------------- worker --------------------------------------------- //
void RocksDbStressor::worker(uint64_t tid) {
  std::mt19937_64 rng{folly::Random::rand64()};
  std::discrete_distribution<> opPoolDist{sCfg_.opPoolDistribution.begin(),
                                          sCfg_.opPoolDistribution.end()};
  std::optional<uint64_t> lastRid = std::nullopt;

  const uint64_t logEvery = 100; // print every N ops per thread

  for (uint64_t i = 0; i < sCfg_.numOps &&
                       !stop_.load(std::memory_order_acquire); /* ++i inside */) {
    if (rateLimiter_) {
      rateLimiter_->consumeWithBorrowAndWait(1);
    }

    try {
      auto pid          = static_cast<PoolId>(opPoolDist(rng));
      const Request& rq = getReq(pid, rng, lastRid);
      lastRid           = rq.requestId;

      switch (rq.getOp()) {
      case OpType::kSet:
      case OpType::kLoneSet: {
        std::string payload(*rq.sizeBegin, 'x');
        cache_->set(rq.key, payload, rq.ttlSecs);
        ++thrStats_[tid].set;
        break;
      }
      case OpType::kGet:
      case OpType::kLoneGet: {
        std::string out;
        bool hit = cache_->get(rq.key, out);
        ++thrStats_[tid].get;
        thrStats_[tid].getMiss += !hit;
        break;
      }
      case OpType::kDel: {
        cache_->del(rq.key);
        ++thrStats_[tid].del;
        break;
      }
      default:
        break; // unsupported op types ignored for now
      }

      ++thrStats_[tid].ops;
      if (rq.requestId) {
        wg_->notifyResult(*rq.requestId, OpResultType::kNop);
      }
      ++i; // increment AFTER successful operation
      if (i % logEvery == 0) {

        std::cout << "[Thread " << tid << "] processed " << i << " ops\n";
      }

    } catch (const cachebench::EndOfTrace&) {
      std::cout << "[Thread " << tid << "] workload exhausted at op " << i << "\n";
      break;
    }
  }
  wg_->markFinish();
}

// -------------------- helper --------------------------------------------- //
const Request& RocksDbStressor::getReq(const PoolId&             pid,
                                       std::mt19937_64&         gen,
                                       std::optional<uint64_t>& lastRid) {
  return wg_->getReq(pid, gen, lastRid);
}

} // namespace facebook::cachelib::cachebench
