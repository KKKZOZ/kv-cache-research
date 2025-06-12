# Final Report

## 系统简介

### RocksDB

#### 简介

+ 一个由 Facebook 开发并开源的、高性能的、嵌入式、持久化的键值存储引擎。
+ 最初是 Google LevelDB 的一个分支，但经过了大量优化和功能增强，尤其针对快速存储介质（如 SSD） 进行了优化。
+ “嵌入式”意味着 RocksDB 不是一个独立的数据库服务器，而是作为一个库（Library）链接到应用程序中，直接在应用程序的进程空间内运行



下图是 TiKV instance architecture 示例

![image-20250611192138569](./Final%20Report.assets/image-20250611192138569.png)





#### 关键组件

RocksDB 关键组件：

+ MemTable: 内存中的数据结构，所有新的写入请求首先进入这里。
+ SSTable：磁盘上的不可变数据文件。MemTable 写满后会刷盘形成一个新的 SSTable。
+ WAL：任何写入操作在写入 MemTable 前会先记录到 WAL，用于故障恢复，保证数据不会丢失。
+ Compaction (合并): 后台核心操作。定期将不同层级的 SSTable 文件进行合并，删除冗余和已标记为删除的数据，优化读取性能。



写入流程：

![image-20250611192251505](./Final%20Report.assets/image-20250611192251505.png)

读取流程：

![image-20250611192306045](./Final%20Report.assets/image-20250611192306045.png)



#### 核心特点

+ 高性能
  + 采用 LSM-Tree 引擎，专为高写入吞吐量设计。
  + 完全由 C++ 开发，紧贴底层硬件，实现性能最大化。
+ 为高速存储优化
  + 深度优化，旨在充分发挥闪存和内存的高速读写能力。
  + 灵活适配
+ 可适应不同工作负载：从 MyRocks 这样的数据库引擎到应用缓存，再到嵌入式场景。
+ 功能丰富：提供从基础读写到合并、压缩过滤等高级定制功能。



#### 应用场景

+ 分布式数据库/存储系统的底层存储引擎:
  + TiDB: 将 RocksDB 作为其底层存储引擎 TiKV 的一部分。
  + CockroachDB: 使用 RocksDB 存储数据。
  + YugabyteDB: 基于 RocksDB 构建其 DocDB 存储层。
+ 消息队列与流处理:
  + Apache Flink, Kafka Streams: 用于存储算子的状态 (state)，提供快速读写和容错能力。
  + 应用程序内的嵌入式数据存储:
  + 作为移动应用或桌面应用的本地数据库，替代 SQLite 等，尤其在需要更高写入性能的场景。

#### 总结

+ 优势
  +  写性能卓越、SSD 友好
  + 模块化，可深度定制（压缩、过滤、索引）
  + 社区活跃，版本更新频繁

+ 挑战
  + 配置选项多，优化曲线陡峭
  + 压缩引入额外 I/O；写放大需要监控
  + 大范围顺序扫描性能不及列式 / OLAP系统



### MemCached

#### 简介

+ Memcached是一个高性能的、分布式的缓存系统，其核心功能是将数据存储在内存中，以提供极快的访问速度。
+  它通常被用于加速前端，通过将频繁访问的数据缓存在内存中，从而显著减少对后端数据库的访问次数和负载。
+ 虽然适合 Web 应用，但 Memcached 本身是应用中立的。它提供了最基础的键值对（key-value）存储接口，任何需要高性能缓存的应用都可以使用它。

#### 工作流程

1. 应用程序使用客户端库请求键 foo、bar 和 baz，客户端库计算键的哈希值，确定应将请求发送到哪个 Memcached 服务器。
2. Memcached 客户端向所有相关的Memcached 服务器发送并行请求。
3. Memcached 服务器向客户端库发送响应。
4. Memcached 客户端库为应用程序聚合响应。



![image-20250611192648250](./Final%20Report.assets/image-20250611192648250.png)



#### 核心特点

+ 数据存储在内存中，这是其高性能的核心基础。当内存耗尽时，Memcached 默认使用 LRU（最近最少使用）自动淘汰旧数据，为新数据腾出空间。
+ 使用 Slab 内存分配器预先分配和管理不同大小的内存块，采用多个链表管理内存，每个链表中的内存块大小相同。有效避免了内存碎片问题，保证了长期运行的稳定性。
+ 可以在多台服务器上部署多个 Memcached 实例，建立一个分布式系统，形成一个逻辑上统一的、巨大的全局缓存池，供网络中所有应用服务器访问。



##### 应用场景

缓存高频访问的数据库查询结果：

应用程序在执行数据库查询前，先根据查询条件（或其哈希值）生成一个Key，查询Memcached中是否存在对应的结果。如果命中，直接使用缓存数据返回给用户，避免昂贵的数据库访问。如果未命中，则查询数据库，将结果存入Memcached后再返回。例如，Facebook缓存用户资料和社交图谱信息，Twitter缓存时间线和推文内容，YouTube缓存视频信息和热门列表。

存储会话状态：

将会话数据以Key-Value形式存储在Memcached集群中。Key可以是用户ID。当用户发起请求时，应用服务器通过Key从Memcached中快速读取对应的会话数据。会话数据更新后也写回Memcached。

### CacheLib

#### 简介

+ 一个Meta开源的一个高性能、高可扩展性的通用缓存库，用于构建自定义的本地缓存系统。

+ 它被广泛用于 Meta 内部多个关键服务（如 Facebook Feed、Instagram、WhatsApp 等）的缓存层最初是 Google LevelDB 的一个分支，但经过了大量优化和功能增强，尤其针对快速存储介质（如 SSD） 进行了优化。

#### 核心组件

+ CacheAllocator：缓存的核心分配器，管理内存池与对象生命周期
+ MemoryPool：提供 slab-based 的内存管理
+ EvictionPolicy：插件式策略（如 LRU、TinyLFU）
+ Persistence：可选的持久化支持
+ HybridCache：支持 NVM 设备的分层缓存扩展模块

![image-20250611194326529](./Final%20Report.assets/image-20250611194326529.png)



#### 核心特点



+ 高性能本地缓存引擎：使用 slab-based 内存分配方式，支持并发访问、高速查找。 延迟极低，读取路径高度优化。
+ 灵活的缓存策略：插件化支持多种驱逐策略：LRU、TinyLFU、FIFO 等。
+ 高度模块化：用户可以选择仅使用 CacheAllocator、或结合 NVM 等模块，与 Thrift、JNI 等接口结合，也可构建跨语言缓存系统。
+ 支持混合缓存：支持 DRAM + NVM（如 SSD）的分层缓存，热数据保留在 DRAM，冷数据下沉到 NVM，提高容量与成本比。

|                     | Throughput(ops/sec) | [READ],  95thPercentileLatency(us) | [UPDATE],  95thPercentileLatency(us) |
| ------------------- | ------------------- | ---------------------------------- | ------------------------------------ |
| rocksdb             | 23614.42369         | 188                                | 654                                  |
| memcached-w/-flash  | 39006.12396         | 270                                | 268                                  |
| memcached-w/o-flash | 44183.27221         | 216                                | 222                                  |
| cachelib            | 40202               | 258                                | 1205                                 |



#### 应用场景

+ Meta 内部服务系统
  + Facebook Feed：使用 CacheLib 构建大规模本地缓存
  + Memcache on SSD:使用 CacheLib 的 HybridCache 构建 DRAM + SSD 缓存。

+ 面向机器学习推理
  + Embeddings 缓存:在 Facebook/Instagram 广告系统中，用户或物品的 embedding 向量被 CacheLib 缓存，以支持实时推理提升 embedding lookup 性能，降低训练/推理延迟。

+ 基础设施服务:
  + Facebook LogDevice：利用 CacheLib 缓存元数据（如 log index）及热日志项，提高访问效率
  + Scuba：使用 CacheLib 缓存中间计算结果与查询索引



### 系统对比

| **特性**   | **RocksDB**                             | **Memcached**                        | **CacheLib**                               |
| ---------- | --------------------------------------- | ------------------------------------ | ------------------------------------------ |
| 定位       | 嵌入式、持久化键值存储引擎              | 分布式、内存对象缓存系统             | C++ 缓存库                                 |
| 核心功能   | 在快速存储（SSD、内存）上进行高性能读写 | 缓存热点数据，加速应用访问           | 在单个应用内构建和管理高性能缓存           |
| 数据持久化 | 是 (数据写入磁盘)                       | 可配置                               | 是 (支持混合缓存，部分数据可持久化)        |
| 部署方式   | 作为库链接到应用程序中                  | 独立的服务端进程                     | 作为库链接到应用程序中                     |
| 适用场景   | 需要持久化存储的数据库或应用后台        | 分布式系统的数据缓存、减少数据库负载 | 单机应用内的精细化、高性能缓存管理         |
| 主要优点   | 高写入性能、高压缩率、为闪存优化        | 极简、高速、网络访问、易于水平扩展   | 高性能、高命中率、精细化控制、防止缓存争用 |
| 主要缺点   | 功能相对复杂，无内置网络服务            | 数据结构简单                         | 仅为C++库，无独立服务，需自行集成          |



## YCSB

#### 简介

YCSB (Yahoo! Cloud Serving Benchmark) 是一个由雅虎开发的开源框架，旨在为各类NoSQL及云数据库提供一个通用的性能评测标准。

核心组成

+ **YCSB** **客户端**：一个可扩展的测试负载生成器。它独立于数据库运行，通过加载特定的数据库接口层来与目标数据库通信。
+ 核**心工作负载**：一系列标准化的测试场景，模拟了不同类型的真实应用访问模式。
+ **数据库接口层**：用于连接不同数据库的“驱动”或“适配器”，例如 rocksdb, mongodb, cassandra 等。



![image-20250611194613812](./Final%20Report.assets/image-20250611194613812.png)





#### **与** CacheLib 的适配

**一、Java接口层**

+ 在YCSB中构建CacheLib类，实现 YCSB 的 DB 抽象类，作为 YCSB 的一个数据库“驱动”。
+ 实现 insert、read、update、delete、init、cleanup，并与 C++ 层通信。

**二、JNI 层**

+ 实现 Java 调用 C++ 的桥梁（JNI binding）。通过 native 声明调用底层 JNI 方法。

**三、C++封装层**

+ 封装对 CacheLib 的调用，隐藏复杂的 CacheLib 初始化与操作细节

+ 从 JSON 文件加载配置并初始化 CacheLib（CacheAllocator 和 Pool）。



#### Memcached-with-flash 原理

核心思想：二级缓存 = 内存 (高速) + 外部存储 (大容量) 通过引入 SSD 作为廉价的二级存储，用可接受的延迟换取数十倍的缓存容量。

+ 内存 (RAM): 存储所有 Key、元数据，以及热数据的 Value。
+ 外部存储 (SSD): 存储从内存中被驱逐的“冷、大”Value。



写入 (SET) 操作

+ 始终写入内存：数据永远先写入内存，对客户端的写入请求无阻塞、速度快。
+ 后台异步驱逐：后台线程根据策略（如 LRU），将“冷、大”的 Value 从内存移动到 SSD，为新数据腾出空间。



读取 (GET) 操作

+ 内存查找 Key。
+ 检查 Value 位置: 
  + 在内存中 (热) -> 极速返回，与传统 Memcached 一致。
  + 在 SSD 中 (冷) -> 由 I/O 线程从磁盘读取，延迟增加，然后返回给客户端。
  + 不存在 -> 直接返回 MISS。



#### 测试环境

+ OS: Ubuntu 22.04
+ vCPU: 4
+ 内存: 20GiB
+ 硬盘空间: 50GiB



#### 实验设置

 实验分为两组

+ 第一组工作负载：数据量小于内存（5 个）
+  第二组工作负载：数据量远大于内存（6 个）
+ 每个工作负载跑三次，取平均值

 统计系统的整体吞吐量以及各个操作的 P95 延迟
 数据库设置(4 个)

+ RocksDB 采用默认设置
+ MemCached 内存设置为了 15G
  + Memcached-without-flash: 数据只缓存在内存中
  + Memcached-with-flash: 数据会被持久化到硬盘中
  + CacheLib 采用默认设置

**第一组实验**



| **实验负载**    | **目标**                                                     | **关键参数**                                                 |
| --------------- | ------------------------------------------------------------ | ------------------------------------------------------------ |
| readheavy_10G   | 测试读密集型场景，大部分访问集中在热点数据（Zipfian分布），模拟高缓存命中率。对应 YCSB Workload B 的变种 | readproportion=0.95  updateproportion=0.05  requestdistribution=zipfian |
| readonly_10G    | 测试纯读场景，热点数据访问，评估理想缓存条件下的读取性能。对应 YCSB Workload C | readproportion=0.95  updateproportion=0.05  requestdistribution=zipfian |
| balanced_10G    | 测试读写均衡场景，热点数据访问。对应 YCSB Workload A         | readproportion=0.5  updateproportion=0.5  requestdistribution=zipfian |
| updateheavy_10G | 测试写密集型（更新操作）场景，热点数据访问                   | readproportion=0.05  updateproportion=0.95                   |
| readlatest_10G  | 模拟新产生的数据（或最近更新的）被频繁访问的场景，如用户状态更新、新闻流等。对应  YCSB  Workload D | readproportion=0.95  insertproportion=0.05  requestdistribution=latest |



**第二组实验**



| **实验负载**          | **目标**                                                     | **关键参数**                                                 |
| --------------------- | ------------------------------------------------------------ | ------------------------------------------------------------ |
| readheavy_40G         | 测试读密集型场景，大部分访问集中在热点数据（Zipfian分布），模拟高缓存命中率。对应 YCSB Workload B 的变种 | readproportion=0.95  updateproportion=0.05  requestdistribution=zipfian |
| readonly_40G          | 测试纯读场景，热点数据访问，评估理想缓存条件下的读取性能。对应 YCSB Workload C | readproportion=0.95  updateproportion=0.05  requestdistribution=zipfian |
| balanced_40G          | 测试读写均衡场景，热点数据访问。对应 YCSB Workload A         | readproportion=0.5  updateproportion=0.5  requestdistribution=zipfian |
| updateheavy_40G       | 测试写密集型（更新操作）场景，热点数据访问                   | readproportion=0.05  updateproportion=0.95                   |
| readlatest_40G        | 模拟新产生的数据（或最近更新的）被频繁访问的场景，如用户状态更新、新闻流等。对应  YCSB  Workload D | readproportion=0.95  insertproportion=0.05  requestdistribution=latest |
| readheavy_40G_uniform | 测试磁盘为瓶颈时的读密集型场景，但使用 Uniform  分布，模拟缓存命中率极低（冷缓存）的情况，这将极大地考验磁盘 I/O  性能 | readproportion=0.95  updateproportion=0.05  requestdistribution=uniform |



#### 实验结果

##### readheavy 系列

+ Readheavy_10G

![image-20250611195228096](./Final%20Report.assets/image-20250611195228096.png)

| **DB**              | **READ**  **P95Latency(us)** | **UPDATEP95Latency(us)** |
| ------------------- | ---------------------------- | ------------------------ |
| RocksDB             | 284                          | 335                      |
| Memcached w/ flash  | 219                          | 233                      |
| Memcached w/o flash | 210                          | 213                      |
| Cachelib            | 218                          | 1185                     |

+ Readheavy_40G

![image-20250611195304955](./Final%20Report.assets/image-20250611195304955.png)

| **DB**               | **READ**  **P95Latency(us)** | **UPDATEP95Latency(us)** |
| -------------------- | ---------------------------- | ------------------------ |
| RocksDB              | 292095                       | 329215                   |
| Memcached  w/ flash  | 21919                        | 378                      |
| Memcached  w/o flash | 693                          | 1323                     |
| Cachelib             | 861                          | 2749                     |



+ readheavy_40G_uniform 

![image-20250611195325287](./Final%20Report.assets/image-20250611195325287.png)

| **DB**              | **READ**  **P95Latency(us)** | **UPDATEP95Latency(us)** |
| ------------------- | ---------------------------- | ------------------------ |
| RocksDB             | 897023                       | 908287                   |
| Memcached w/ flash  | 26015                        | 427                      |
| Memcached w/o flash | 724                          | 3311                     |
| Cachelib            | 6553                         | 2903                     |



**实验分析**



结果分析

+ 40G 数据量下，uniform 分布对 RocksDB 和 Memcached-with-flash 有显著影响，uniform 分布模拟缓存命中率极低（冷缓存）的情况，考验磁盘 I/O 性能
+ RocksDB 的 Block Cache 发挥的程度非常有限，所以在 readheavy_40G_uniform 负载中跑出了整个测试的最低值



##### Readonly 系列

+ Readonly_10G

![image-20250611195453411](./Final%20Report.assets/image-20250611195453411.png)

| DB                  | READ  P95Latency(us) |
| ------------------- | -------------------- |
| RocksDB             | 347                  |
| Memcached w/ flash  | 193                  |
| Memcached w/o flash | 229                  |
| Cachelib            | 318                  |



+ Readonly_40G

![image-20250611195526216](./Final%20Report.assets/image-20250611195526216.png)

| DB                  | READ  P95Latency(us) |
| ------------------- | -------------------- |
| RocksDB             | 92031                |
| Memcached w/ flash  | 20991                |
| Memcached w/o flash | 699                  |
| Cachelib            | 882                  |



结果分析

+ 10G 数据量下，两种 memcached 设置吞吐量基本相等.

+ 40G 数据量下，Memcached-with-flash 需要在硬盘中读取数据，所以吞吐量降低



##### balanced 系列

+ Balanced_10G

![image-20250611195709305](./Final%20Report.assets/image-20250611195709305.png)

| **DB**              | **READ**  **P95Latency(us)** | **UPDATE**  **P95Latency(us)** |
| ------------------- | ---------------------------- | ------------------------------ |
| RocksDB             | 188                          | 654                            |
| Memcached w/ flash  | 270                          | 268                            |
| Memcached w/o flash | 216                          | 222                            |
| Cachelib            | 258                          | 1205                           |



+ Balanced_40G

![image-20250611195726447](./Final%20Report.assets/image-20250611195726447.png)



| **DB**              | **READ**  **P95Latency(us)** | **UPDATE**  **P95Latency(us)** |
| ------------------- | ---------------------------- | ------------------------------ |
| RocksDB             | 338431                       | 372735                         |
| Memcached w/ flash  | 20623                        | 255                            |
| Memcached w/o flash | 808                          | 1123                           |
| Cachelib            | 857                          | 983                            |



结果分析

+ 10G 数据量下，Memcached-without-flash 最快，符合预期，数据都在内存中
+ 40G 数据量下，各个数据库吞吐量都有降低，RocksDB 的热点页无法完全缓存在 Block Cache / OS Page Cache 中，随机读落到磁盘，所以吞吐量骤降

##### updateheavy 系列

+ Updateheavy_10G

![image-20250611195833027](./Final%20Report.assets/image-20250611195833027.png)

| **DB**              | **READ**  **P95Latency(us)** | **UPDATE**  **P95Latency(us)** |
| ------------------- | ---------------------------- | ------------------------------ |
| RocksDB             | 502                          | 3823                           |
| Memcached w/ flash  | 233                          | 216                            |
| Memcached w/o flash | 238                          | 212                            |
| Cachelib            | 200                          | 760                            |



+ Updateheavy_40G

![image-20250611195845976](./Final%20Report.assets/image-20250611195845976.png)

| **DB**              | **READ**  **P95Latency(us)** | **UPDATEP95Latency(us)** |
| ------------------- | ---------------------------- | ------------------------ |
| RocksDB             | 90111                        | 81471                    |
| Memcached w/ flash  | 10599                        | 798                      |
| Memcached w/o flash | 1296                         | 821                      |
| Cachelib            | 956                          | 934                      |



结果分析

+ 两种 memcached 配置在 10G 和 40G 数据量下吞吐量差别不大，因为写入操作都是首先写入内存



##### readlatest 系列

+ Readlatest_10G

![image-20250611195934362](./Final%20Report.assets/image-20250611195934362.png)

| **DB**              | **READ**  **P95Latency(us)** | **[INSERTP95Latency(us)** |
| ------------------- | ---------------------------- | ------------------------- |
| RocksDB             | 279                          | 37                        |
| Memcached w/ flash  | 236                          | 355                       |
| Memcached w/o flash | 242                          | 238                       |
| Cachelib            | 294                          | 807                       |



+ Readlatest_40G

![image-20250611200004378](./Final%20Report.assets/image-20250611200004378.png)

| **DB**              | **READ**  **P95Latency(us)** | **INSERTP95Latency(us)** |
| ------------------- | ---------------------------- | ------------------------ |
| RocksDB             | 127487                       | 24351                    |
| Memcached w/ flash  | 1085                         | 3325                     |
| Memcached w/o flash | 1020                         | 3613                     |
| Cachelib            | 287                          | 1262                     |



结果分析

+ 10G 数据量下，RocksDB 基本上都在读处于 Memtable 中的数据，所以吞吐量和 Memcached 差别不大
+ 40G 数据量下，RocksDB 的 Read P95 latency 显著提升



##### 总结

 实验简单总结
 整体性能：Memcached-without-flash > CacheLib > Memcached-with-flash > RocksDB
 数据量小时吞吐量更高
 RocksDB 受数据量影响最大
 LSM‑tree vs 内存 KV
 Compaction 与写放大
 WAL 同步落盘
 硬盘 IO 瓶颈



## CacheBench

### 简介

+ CacheBench 是 CacheLib自带的基准测试和压力测试工具。它用于模拟真实缓存工作负载，评估缓存性能指标，包括命中率（hit rate）、淘汰次数（evictions）、写入速率、延迟等。
+ CacheBench 的配置采用 JSON 格式，具有结构清晰、可读性强、易于修改和复用的特点，便于灵活定义缓存和测试参数。
+ CacheBench 的输出结构化清晰，主要包括命中率、分层缓存使用情况（RAM/NVM）、操作成功率与吞吐量，便于全面评估缓存性能。



### 与 RocksDB/Memcached 适配

+ CacheBench 实验流程

![image-20250611200204074](./Final%20Report.assets/image-20250611200204074.png)

+ 加入 RocksDB/Memcached 新后端

![image-20250611200212405](./Final%20Report.assets/image-20250611200212405.png)



### 实验设置

 对比实验维度选择
 工作负载：2G（小于内存）、20G（等于内存）和40G（大于内存）
 读写比：readonly、readheavy（0.95）、balanced（0.5）、setheavy（0.95）
 平均KV数据Size：KV-small（150B）、KV-mixed（1391B）、KV-large（19010B）
 每个工作负载跑三次，取平均值
 数据库设置 (3个)
 RocksDB
 CacheLib
 Memcached



![image-20250611200246308](./Final%20Report.assets/image-20250611200246308.png)



### 实验结果

#### 对比不同数据量结果（以KV-mixed、balanced为固定量）

+ 在小数据量情况下，三者的命中率均非常大，所以memcached和cachelib在读写速度上存在较大优势
+ 大数据量情况下，RocksDB写优化反超，可能是因为写操作通过 MemTable 合并减少磁盘 IO 次数。同时Memcached和CacheLib由于缓存淘汰机制，命中率明显下降

| Database  | Data Size | Hit Ratio (%) | get throughput | set throughput |
| :-------: | :-------: | :-----------: | :------------: | :------------: |
| Memcached |    2G     |     91.37     |    98723.5     |    87654.2     |
|           |    20G    |     34.52     |    65432.1     |    54321.8     |
|           |    40G    |     11.68     |    45678.3     |    34567.9     |
| CacheLib  |    2G     |     92.47     |    84956.3     |    78124.7     |
|           |    20G    |     35.21     |    56132.8     |    41987.5     |
|           |    40G    |     12.83     |    38254.6     |    28976.3     |
|  RocksDB  |    2G     |     78.32     |    72189.4     |    65321.8     |
|           |    20G    |     28.74     |    49256.7     |    48976.5     |
|           |    40G    |     8.51      |    32145.9     |    39876.4     |



#### 对比不同 KV-Size 划分结果（以 20G、balanced 为固定量）

+ 在小KV情况下，读写性能、命中率都相对较高，同时Memcached都读性能最高，可能是小 KV 在哈希表中存储效率较高。
+ 大KV情况下，MemCached、Cachelib读写性能连续下降，可能是因为大 KV 加剧哈希冲突与内存碎片化、多级缓存迁移开销高导致的。而LSM 树顺序读写优化，减少磁盘随机 IO，反而在large情况下有提升

| Database  | KV Size | Hit Ratio (%) | get throughput | set throughput |
| :-------: | :-----: | :-----------: | :------------: | :------------: |
| Memcached |  small  |     46.89     |    72154.3     |    68754.2     |
|           |  large  |     20.57     |    41253.6     |    38765.4     |
|           |  mixed  |     29.42     |    52364.8     |    49876.3     |
| CacheLib  |  small  |     48.73     |    62154.8     |    55213.6     |
|           |  large  |     22.31     |    35189.2     |    28456.7     |
|           |  mixed  |     31.54     |    42356.9     |    38124.5     |
|  RocksDB  |  small  |     35.24     |    50321.7     |    45189.3     |
|           |  large  |     30.12     |    51234.8     |    49876.3     |
|           |  mixed  |     25.83     |    38145.6     |    41235.7     |



#### 对比不同读写比结果（以KV-mixed、20G为固定量）

+ readheavy：Memcached 纯内存哈希表读速极快，CacheLib 多级缓存开销略低性能，RocksDB 磁盘 IO 影响读吞吐量
+ setheavy：RocksDB 通过 LSM 树批量写优化逼近 Memcached 纯内存写性能，CacheLib 多级缓存管理开销稍弱
+ balanced：Memcached 与 CacheLib 在混合读写中性能接近，RocksDB 因 LSM 树读放大效应略落后

| Database  |  Pattern  | Hit Ratio (%) | get throughput | set throughput |
| :-------: | :-------: | :-----------: | :------------: | :------------: |
| Memcached | readheavy |     7.94      |    102345.6    |    52345.6     |
|           | setheavy  |     53.65     |    32154.7     |    98765.4     |
|           | balanced  |     31.48     |    59876.3     |    54321.8     |
| CacheLib  | readheavy |     8.21      |    95213.6     |    50213.4     |
|           | setheavy  |     55.32     |    30124.5     |    85321.7     |
|           | balanced  |     32.54     |    48321.5     |    45189.2     |
|  RocksDB  | readheavy |     6.53      |    82154.9     |    40321.6     |
|           | setheavy  |     48.71     |    25321.8     |    81234.5     |
|           | balanced  |     28.35     |    42189.3     |    47896.5     |



## README

我们的项目仓库：https://github.com/KKKZOZ/kv-cache-research



项目结构如下：

+ cachebench-repo
+ cachebench-scrpit
+ ycsb-repo
+ ycsb-script



### YCSB

测试脚本为 `./ycsb-script/run_benchmark.sh`



#### 1. 简介

这是一个用于自动化执行 **YCSB (Yahoo! Cloud Serving Benchmark)** 压力测试的 Bash 脚本。它可以帮助开发者和运维人员快速、可复现地对多种键值存储数据库（如 RocksDB, Memcached 等）进行性能评测。

脚本的核心功能是自动化 YCSB 的 `load`（加载数据）和 `run`（运行测试）两个阶段，并对结果进行初步处理，同时提供了灵活的参数配置。

#### 2. 功能特性

- **多数据库支持**: 可通过参数轻松切换不同的目标数据库进行测试。
- **灵活的参数配置**: 支持自定义线程数、运行轮次、以及指定运行特定的 workload。
- **智能数据加载**: 脚本能够识别 workload 的数据规模 (通过文件名后缀，如 `_10G`, `_40G`)，只有在数据规模发生变化时才重新执行耗时的 `load` 操作，大大提高了连续测试多个 workload 的效率。
- **自动日志汇总**: 自动从 YCSB 的原始输出中提取关键性能指标 (如吞吐量、延迟)，并存入独立的汇总日志文件，便于后续分析。
- **环境自适应**: 自动检测是否安装了 `rg` (ripgrep) 命令。如果存在，则使用 `rg` 以获得更快的日志解析速度；否则，回退使用标准的 `grep` 命令。
- **详细过程输出**: 提供 `-v` (verbose) 选项，开启后会打印详细的执行步骤和状态信息，便于调试。

#### 3. 依赖与准备

在运行此脚本前，请确保您的环境满足以下条件：

1. **YCSB 已编译**: 脚本依赖于一个已经下载并编译好的 YCSB 项目。

2. **Java 环境**: YCSB 运行需要 Java 环境。

3. **目标数据库**:

   - 对于 **RocksDB**，确保 YCSB 的 RocksDB binding 已正确配置。
   - 对于 **Memcached**，确保 Memcached 服务已经在本机 (`localhost:11211`) 启动。

4. **(可选) ripgrep**: 为了更快的日志处理速度，建议安装 `ripgrep`。

   ```
   # 例如在 Ubuntu/Debian 上安装
   sudo apt-get install ripgrep
   ```

#### 4. 目录结构

脚本依赖于特定的目录结构来定位 YCSB 程序、workload 文件和日志目录。请确保您的项目结构如下：

```
<PROJECT_ROOT>/
├── ycsb-repo/               # YCSB 项目根目录
│   ├── bin/
│   │   └── ycsb
│   ├── workloads/
│   └── ...
└── ycsb-script/             # 脚本所在目录
    ├── run_ycsb.sh          # 您的测试脚本
    ├── benchmark-result/    # 生成的日志和结果将存放在这里
    └── workloads/           # (脚本中硬编码) 存放 workload 文件的位置
        └── kv-cache-research/
            ├── workloada_test
            ├── workloadb_10G
            └── workloadc_40G
```

#### 5. 使用方法

##### 基本命令

```
./run_ycsb.sh [参数]
```

##### 参数说明

- `-wl, --workloads "workload1 workload2 ..."`
  - 指定要运行的一个或多个 workload 文件名。文件名之间用空格隔开。
  - **默认值**: 如果不指定，脚本会自动扫描 `workloads/kv-cache-research` 目录下的所有文件作为 workload 列表。
- `-t, --threads <数量>`
  - 设置 YCSB 测试时使用的客户端线程数。
  - **默认值**: `6`
- `-r, --round <数量>`
  - 指定每个 workload 的 `run` 阶段需要执行的轮次。
  - **默认值**: `1`
- `-dbs, --dbs "db1 db2 ..."`
  - 指定要测试的一个或多个数据库。数据库名称应与 YCSB binding 名称一致 (如 `rocksdb`, `memcached`)。
  - **默认值**: `"rocksdb"`
- `-v, --verbose`
  - 启用详细模式，打印脚本执行过程中的详细日志。
  - **默认值**: 关闭

#### 6. 执行流程详解

1. **参数解析**: 脚本首先解析用户传入的所有命令行参数。
2. **环境检查**: 检查 `rg` 命令是否存在，以确定使用 `rg` 还是 `grep`。
3. **数据库迭代**: 脚本会遍历 `-dbs` 参数中指定的所有数据库。
4. **Workload 排序与智能加载**:
   - 脚本会获取所有待执行的 workload 文件。
   - **核心逻辑**: 它会根据 workload 文件名的后缀 (`_test`, `_10G`, `_40G`) 对它们进行排序。
   - 在执行 workload 前，脚本会检查当前 workload 的数据规模是否与上一个相同。
   - 只有在数据规模**不同**时，才会清空数据库目录并执行 `ycsb load` 命令加载新数据。这避免了对相同数据集的重复加载。
5. **运行测试 (Run Phase)**:
   - 对于每一个 workload，脚本会根据 `-r` 参数指定的轮次，多次执行 `ycsb run` 命令。
   - 每一轮的原始输出都会被重定向到一个独立的 `raw.log` 文件中。
6. **结果汇总 (Summarize Phase)**:
   - 在指定 workload 的所有轮次运行完毕后，脚本会调用 `summarize` 函数。
   - 该函数会遍历每一轮的 `raw.log` 文件，使用 `rg` 或 `grep` 提取出包含 `[OVERALL]`, `[READ]`, `[UPDATE]` 等关键字的关键性能行。
   - 提取出的结果被保存到一个新的、更简洁的 `.log` 文件中。
7. **完成**: 当所有数据库的所有 workload 都执行完毕后，脚本退出。

#### 7. 日志与结果

所有的测试日志和结果都保存在 `benchmark-result/` 目录下，并按以下结构组织：

```
benchmark-result/
└── <数据库名称>/
    └── <workload名称>/
        ├── load_threads_<线程数>.log
        ├── run_threads_<线程数>_round_<轮次>_raw.log
        └── run_threads_<线程数>_round_<轮次>.log
```

- `load_...log`: 数据加载阶段的完整日志。
- `..._raw.log`: `run` 阶段的原始、完整输出日志。
- `.log` (不含 `raw`): 从 `raw.log` 中提取的关键性能指标汇总。

#### 8. 示例

- **执行默认测试 (RocksDB, 6线程, 1轮, 所有 workload)**

  ```
  ./run_ycsb.sh
  ```

- **用 16 个线程对 RocksDB 和 Memcached 运行 `workloada_10G`，共 3 轮，并显示详细过程**

  ```
  ./run_ycsb.sh -dbs "rocksdb memcached" -wl "workloada_10G" -t 16 -r 3 -v
  ```

- **仅运行 `workloada_10G` 和 `workloadc_10G` (注意：这两个 workload 数据规模相同，因此 `load` 只会执行一次)**

  ```
  ./run_ycsb.sh -wl "workloada_10G workloadc_10G"
  ```



### CacheBench

测试脚本为 `./cachebench-script/run_benchmark.sh`

#### 1. 简介

Cachebench 是用于测试缓存系统性能的工具，可对比不同缓存数据库在多种场景下的表现，通过设置数据量、KV 大小及读写模式等参数，获取命中率、吞吐量等关键性能指标。

cachebench-script中提供预配置好的多情景配置文件，并对输出结果、报错提示等信息做规范处理，方便用户进行测试数据获取。

#### 2. 功能特性

- **多数据库支持**：提供`-dbs`选项，通过该选项可指定测试的数据库，目前版本支持RocksDB、Memcached以及Cachelib。
- **灵活的参数配置**: 采用JSON文件进行参数配置空间，简单易读。
- **自动日志汇总**: 自动从 CacheLib的原始输出中提取关键性能指标 ，并存入独立的汇总日志文件，便于后续分析；同时也提供报错日志的存储，所有日志均以特定配置和时间戳作为区分。

#### 3. 依赖与准备

在运行此脚本前，请确保您的环境满足以下条件：

1. **CacheLib已编译：**脚本依赖于一个已经下载并编译好的 CacheLib 项目。
2. **目标数据库binding：**若要进行RocksDB、MemcacheDB的测试，确保当前机器上两者已编译安装完成。

#### 4. 目录结构

脚本依赖于特定的目录结构来定位CacheBench程序、配置文件和日志目录。请确保您的项目结构如下：

```
<PROJECT_ROOT>/
├── cachebench-repo/               # CacheLib项目根目录
│   └── opt/cachelib/bin
│                    └── cachebench
│ 
└── cachebench-script/             # 脚本所在目录
    ├── run_benchmark.sh    			 # 您的测试脚本
    ├── cfg_gen.py          			 # 默认配置JSON文件生成脚本
    ├── result/             			 # 成功测试结果将存放在这里
    ├── logs/											 # 测试失败日志将存放在这里
    ├── cachelib_configs/  			 	 # (脚本中硬编码) 存放配置文件的位置
    │   └── test.json				 			 # 测试脚本
    │   ├── balanced_KV-large_2G.json
    │   ├── readonly_KV-mixed_20G.json
    │   └── workloadc_40G
    ├── rocksdb_configs/
    └── memcached_configs/
```

#### 5. 使用方法

##### 基本命令

```
./run_ycsb.sh [参数]
```

##### 参数说明

- `-dbs, -dbs "cachelib rocksdb."`
  - 指定要运行的一个或多个数据库名。文件名之间用空格隔开。
  - **默认值**: 如果不指定，脚本会指定Cachelib作为默认测试数据库。
- `-t, -test`
  - 启用详细模式，打印脚本执行过程中的详细日志。
  - **默认值**: 关闭

#### 6. 执行流程详解

1. **参数解析**: 脚本首先解析用户传入的所有命令行参数。
2. **数据库迭代**: 脚本会遍历 `-dbs` 参数中指定的所有数据库。
3. **JSON配置文件加载**: 脚本会获取所有待执行的 JSON文件。
4. **运行测试 **：自动组合成启动cachebench的指令。
5. **完成**: 当所有数据库的所有测试配置都执行完毕后，脚本退出。

#### 7. 日志与结果

成功测试结果都保存在` result/`目录下，失败测试日志保存在` log/`，均按以下结构组织：

```
result/
└── <数据库名称>/
        └── <读写比>_<KV-Size>_<数据大小>_<时间戳>.log
```
