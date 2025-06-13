# Copyright (c) Meta Platforms, Inc. and affiliates.
# SPDX-License-Identifier: Apache-2.0

# ──────────────────────────────
# ① 生成静态库：cachelib_cachebench
# ──────────────────────────────
add_library(cachelib_cachebench
  # ───► 现有源码
  ./cache/Cache.cpp
  ./cache/TimeStampTicker.cpp
  ./consistency/LogEventStream.cpp
  ./consistency/ShortThreadId.cpp
  ./consistency/ValueHistory.cpp
  ./consistency/ValueTracker.cpp
  ./runner/FastShutdown.cpp
  ./runner/IntegrationStressor.cpp
  ./runner/ProgressTracker.cpp
  ./runner/Runner.cpp
  ./runner/Stressor.cpp
  ./util/CacheConfig.cpp
  ./util/Config.cpp
  ./util/NandWrites.cpp
  ./workload/BlockChunkCache.cpp
  ./workload/BlockChunkReplayGenerator.cpp
  ./workload/PieceWiseCache.cpp
  ./workload/OnlineGenerator.cpp
  ./workload/WorkloadGenerator.cpp
  ./workload/PieceWiseReplayGenerator.cpp

  # ───► RocksDB 后端新增源码
  ./cache/RocksDbCache.cpp
  ./runner/RocksDbStressor.cpp
)
add_dependencies(cachelib_cachebench thrift_generated_files)

# ──────────────────────────────
# ② 让编译器找到 RocksDB 头文件
#    若 RocksDB 安装在其它前缀，请把路径改掉
# ──────────────────────────────
include_directories(/usr/local/include)

# ──────────────────────────────
# ③ 库链接
#    -librocksdb.a 及其常用依赖
# ──────────────────────────────
target_link_libraries(cachelib_cachebench PUBLIC
  cachelib_datatype
  cachelib_allocator
  gflags

  # RocksDB 主库 (静态版；若用 .so 请改名)
  /usr/local/lib/librocksdb.a

  # RocksDB 常见依赖（根据你编译选项增删）
  z         # zlib
  snappy
  lz4
  zstd
  bz2
  pthread
)

# ──────────────────────────────
# ④ 额外编译选项
# ──────────────────────────────
if ((CMAKE_SYSTEM_NAME STREQUAL Linux) AND
    (CMAKE_SYSTEM_PROCESSOR STREQUAL x86_64))
else()
  target_compile_definitions(cachelib_cachebench PRIVATE SKIP_OPTION_SIZE_VERIFY)
endif()

# ──────────────────────────────
# ⑤ cachebench 可执行文件
# ──────────────────────────────
add_executable(cachebench main.cpp)
target_link_libraries(cachebench
  cachelib_cachebench
  /usr/local/lib/librocksdb.a     # 静态编译保险起见再带一次
  z snappy lz4 zstd bz2 pthread)

install(TARGETS cachebench DESTINATION ${BIN_INSTALL_DIR})

# ──────────────────────────────
# ⑥ 可选：安装共享库
# ──────────────────────────────
if (BUILD_SHARED_LIBS)
  install(TARGETS cachelib_cachebench
          EXPORT cachelib-exports
          DESTINATION ${LIB_INSTALL_DIR})
endif()

# ──────────────────────────────
# ⑦ 单元测试（保持原样，仅缩进调整）
# ──────────────────────────────
if (BUILD_TESTS)
  add_library(cachebench_test_support INTERFACE)
  target_link_libraries(cachebench_test_support INTERFACE
    cachelib_cachebench
    glog::glog
    gflags
    GTest::gtest
    GTest::gtest_main
    GTest::gmock)

  function(ADD_TEST SOURCE_FILE)
    generic_add_test("cachebench-test" "${SOURCE_FILE}"
                     cachebench_test_support "${ARGN}")
  endfunction()

  add_test(workload/tests/WorkloadGeneratorTest.cpp)
  add_test(workload/tests/PieceWiseCacheTest.cpp)
  add_test(consistency/tests/RingBufferTest.cpp)
  add_test(consistency/tests/ShortThreadIdTest.cpp)
  add_test(consistency/tests/ValueHistoryTest.cpp)
  add_test(consistency/tests/ValueTrackerTest.cpp)
  add_test(util/tests/NandWritesTest.cpp)
  add_test(cache/tests/TimeStampTickerTest.cpp)
endif()

