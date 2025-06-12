#include "CacheLibWrapper.h"

#include <cachelib/allocator/CacheAllocator.h>
#include <cachelib/allocator/CacheAllocatorConfig.h>

#include <fstream>
#include "nlohmann/json.hpp"
#include <stdexcept>
#include <cstring>
#include <iostream>
#include <mutex>  


using json = nlohmann::json;
using namespace facebook::cachelib;
using Cache = LruAllocator;

class CacheLibWrapperImpl {
public:
    explicit CacheLibWrapperImpl(const std::string& configPath) {
        // 读取 JSON 配置
        std::ifstream file(configPath);
        if (!file.is_open()) {
            throw std::runtime_error("Cannot open config file: " + configPath);
        }
        json j;
        file >> j;

        auto& cacheCfg = j.at("cache_config");

        size_t cacheSizeMB = cacheCfg.value("cacheSizeMB", 128);
        int numPools = cacheCfg.value("numPools", 1);
        std::vector<double> poolSizes = cacheCfg.value("poolSizes", std::vector<double>{1.0});
        std::string persistencePath = cacheCfg.value("persistencePath", "");

        if (poolSizes.size() != static_cast<size_t>(numPools)) {
            throw std::runtime_error("poolSizes length must match numPools");
        }

        // 配置 CacheAllocatorConfig
        CacheAllocatorConfig<Cache> config;
        config.setCacheSize(cacheSizeMB * 1024 * 1024)
            .setCacheName("cachelib");

        bool attached = false;
        if (!persistencePath.empty()) {
            config.enableCachePersistence(persistencePath);

            // 尝试 attach
            try {
                allocator_ = std::make_unique<Cache>(Cache::SharedMemAttach, config);
                std::cout << "Attached to existing cache at " << persistencePath << std::endl;
                attached = true;
            } catch (const std::exception& ex) {
                std::cerr << "Attach failed: " << ex.what() << std::endl;
            }
        }

        if (!attached) {
            allocator_ = !persistencePath.empty()
                ? std::make_unique<Cache>(Cache::SharedMemNew, config)
                : std::make_unique<Cache>(config);  // fallback to in-process if no persistence
            std::cout << "Created new cache instance" << std::endl;

            // 新建缓存时需要 addPool
            pools_.clear();
            size_t totalCacheSize = config.getCacheSize();
            double reservedRatio = 0.1; // 预留10%
            size_t usableCacheSize = static_cast<size_t>(totalCacheSize * (1.0 - reservedRatio));

            for (int i = 0; i < numPools; ++i) {
                size_t poolSizeBytes = static_cast<size_t>(usableCacheSize * poolSizes[i]);
                pools_.push_back(allocator_->addPool("pool_" + std::to_string(i), poolSizeBytes));
            }

            if (pools_.empty()) {
                throw std::runtime_error("No pools created in CacheLibWrapperImpl");
            }
            pool_ = pools_.front();  // 默认使用第一个pool
        } else {
            // attach 成功时，从已有池中获取
            pool_ = allocator_->getPoolId("pool_0");
            if (pool_ == PoolId{}) {
                throw std::runtime_error("Failed to get pool_0 from attached cache");
            }
        }
    }

    ~CacheLibWrapperImpl() = default;

    bool insert(const std::string& key, const std::vector<uint8_t>& value) {
        std::lock_guard<std::mutex> lock(mutex_);
        auto handle = allocator_->allocate(pool_, key, value.size());
        if (!handle) return false;
        std::memcpy(handle->getMemory(), value.data(), value.size());
        allocator_->insertOrReplace(handle);
        return true;
    }

    bool read(const std::string& key, std::vector<uint8_t>& valueOut) {
        std::lock_guard<std::mutex> lock(mutex_);
        auto handle = allocator_->find(key);
        if (!handle) return false;
        auto data = static_cast<const uint8_t*>(handle->getMemory());
        valueOut.assign(data, data + handle->getSize());
        return true;
    }

    bool update(const std::string& key, const std::vector<uint8_t>& value) {
        return insert(key, value);  // 覆盖写
    }

    bool remove(const std::string& key) {
        std::lock_guard<std::mutex> lock(mutex_);
        return allocator_->remove(key) == Cache::RemoveRes::kSuccess;
    }

private:
    std::unique_ptr<Cache> allocator_;
    std::vector<PoolId> pools_;
    PoolId pool_;
    std::mutex mutex_;
};

// C++ 封装接口实现
CacheLibWrapper::CacheLibWrapper(const std::string& configPath) {
    cache_ = new CacheLibWrapperImpl(configPath);
}

CacheLibWrapper::~CacheLibWrapper() {
    delete static_cast<CacheLibWrapperImpl*>(cache_);
}

bool CacheLibWrapper::insert(const std::string& key, const std::vector<uint8_t>& value) {
    return static_cast<CacheLibWrapperImpl*>(cache_)->insert(key, value);
}

bool CacheLibWrapper::read(const std::string& key, std::vector<uint8_t>& valueOut) {
    return static_cast<CacheLibWrapperImpl*>(cache_)->read(key, valueOut);
}

bool CacheLibWrapper::update(const std::string& key, const std::vector<uint8_t>& value) {
    return static_cast<CacheLibWrapperImpl*>(cache_)->update(key, value);
}

bool CacheLibWrapper::remove(const std::string& key) {
    return static_cast<CacheLibWrapperImpl*>(cache_)->remove(key);
}


extern "C" {
    CacheLibWrapper* createCacheLibWrapper(const std::string& configPath) {
        return new CacheLibWrapper(configPath);
    }

    void destroyCacheLibWrapper(CacheLibWrapper* wrapper) {
        delete wrapper;
    }
}