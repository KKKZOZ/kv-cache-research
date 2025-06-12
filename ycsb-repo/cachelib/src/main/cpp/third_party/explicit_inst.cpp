#include <cachelib/allocator/CacheAllocator.h>
#include <cachelib/allocator/MMLru.h>  // 确保包含MMLru定义

template class facebook::cachelib::CacheAllocator<facebook::cachelib::LruCacheTrait>;

