#pragma once

#include <string>
#include <vector>
#include <cstdint>

class CacheLibWrapper {
public:
    explicit CacheLibWrapper(const std::string& configPath);
    ~CacheLibWrapper();

    bool insert(const std::string& key, const std::vector<uint8_t>& value);
    bool read(const std::string& key, std::vector<uint8_t>& valueOut);
    bool update(const std::string& key, const std::vector<uint8_t>& value);
    bool remove(const std::string& key);

private:
    void* cache_;
};

// C 接口
extern "C" {
    CacheLibWrapper* createCacheLibWrapper(const std::string& configPath);
    void destroyCacheLibWrapper(CacheLibWrapper* wrapper);
}