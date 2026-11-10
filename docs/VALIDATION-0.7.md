# MoonOHOS 0.7（开发中）验证记录

记录日期：2026-11-11。0.5、0.6 的记录见 [VALIDATION-0.5.md](VALIDATION-0.5.md)。本文件随 0.7 开发持续追加；版本号仍为 0.6.0，尚未发布。

## 环境

- Windows 11 x64；Moon `0.1.20261104 (940aa18)`，moonc `v0.10.20+65efd5b93`；MSVC（宿主 ASan）。
- DevEco Studio 26（HarmonyOS SDK API 26）。
- 模拟器：Pura 90 Pro，HarmonyOS 7.0.0（API 26），x86_64，`127.0.0.1:5555`。启动方式：
  `Emulator.exe -hvd "Pura 90 Pro" -instancePath D:\Code\Harmony\Emulator -imageRoot D:\Code\Harmony\Emulator\SDK`。
- CI：Windows（固定工具链 0.10.20）、Ubuntu 24.04、macOS 15、最新 MoonBit（预警）。

## 编译器升级到 0.10.20

| 变化 | 处理 |
|---|---|
| 尾随 `derive(...)` 被标为弃用语法（警告 0027，`--deny-warn` 下报错） | 7 处改为类型前的 `#derive(...)`（根模块 5 处、`cmd` 1 处、`ohos/deviceinfo` 1 处），由 `moon fmt` 迁移 |
| 0.10.18 无法解析 `#derive(...)`（用官方 0.10.18 包实测：根模块 73 个错误，`ohos` 2 个） | `build`/`doctor` 的最低版本由 0.10.16 提到 0.10.20；接入包校验另设下限 0.10.16，0.4.1–0.6.x 构建的 HAR 仍可通过 `verify` |
| `Ref` 移入 `moonbitlang/core/ref`，记录字面量 `{ val: ... }` 和 `Ref(...)` 在未导入该包的模块里都无法编译 | 回调 fixture 改用数组保存回调。这是上次回调 ASan 套件“既无通过也无失败”的原因：代码生成阶段编译失败后 panic，没有走到测试 |
| `moon version` 在版本行后追加 `Feature flags enabled: ...` | 清单的 `moon`、`moonc` 字段只取第一行（`tool_banner`） |
| `moon fmt` 会把示例里的 `Int` 改写为 `Int32` | 示例保持 `Int` 写法，`--deny-warn` 下无警告 |

## 本地全量检查

| 检查 | 结果 |
|---|---|
| `moon fmt`、`moon check --deny-warn --warn-list +73`、`moon info` | 通过 |
| 根模块 / `ohos` / `examples/search` / `examples/core` 测试 | 73 / 6 / 11 / 2，全部通过 |
| 宿主 ASan 套件（数组、记录、引用矩阵、异步、线程探针、Int64、Option、枚举、句柄方法与类型标记、回调） | 10 项全部通过，日志见 `evidence/v0.7/host-*.log` |
| `verify_cli.py`（含 0.3 schema v1 旧版清单路径） | 41 个场景通过 |
| `verify_integration.py` | 11 项通过 |
| `verify_init_flow.ps1` | 通过 |
| 生产代码统计 / `moon package` | 7351 行（门槛 4000）/ 通过 |

## 模拟器运行：检索示例

`build_search.ps1` 用当前 CLI 重新构建：MoonBit → 双 ABI `libmoonsearch.so`（清单记录 moonc `v0.10.20+65efd5b93`，两个 ABI 的 ELF 校验通过）→ HAR → 独立应用 HAP。`verify_search_device.ps1` 安装 HAP，脚本化场景连续运行两次，两次都通过（`SEARCH_DEVICE_PASS runs=2`）。

| 能力 | 版本 | 设备上的证据（HiLog） |
|---|---|---|
| 后台线程异步任务 | 0.4 | 2000 篇文档在工作线程建索引，用时约 5.2–6.4 s，期间界面计时器走了 49–57 次（`ui_ticks`），界面没有卡住 |
| 取消 | 0.4 | 150 ms 后取消大索引：`MOONSEARCH_INDEX_CANCELLED at=…`，Promise 以 `AbortError: task cancelled` 拒绝；离开页面时自动取消正在进行的重建 |
| ArkTS 回调（进度） | 0.6 | `MOONSEARCH_PROGRESS dir=docs reported=12 documents=12`、`dir=docs_large reported=2000 documents=2000`：最后一次进度回调在 Promise 完成之前送达 |
| 句柄方法 | 0.5 | 探针用 `index.stats()` 读取自己的索引 |
| 句柄类型标记 | 0.7 | `MOONSEARCH_TYPETAG pass own=ok foreign=TypeError kind=TypeError plain=TypeError method=TypeError close=TypeError after=ok` |
| 句柄生命周期 | 0.4 | 每轮结束 `live_handles=0 pending_tasks=0`；两轮后 `released=5 completed=9 cancelled=4` |

类型标记探针（`examples/search-app/entry/src/main/ets/pages/TypeTagProbe.ts`）的各项含义：

- `foreign`：把系统的 `ResourceManager`（由另一个原生模块包装的对象）当作 `SearchIndex` 传入。加标记之前，这种对象能通过 `napi_unwrap`，其内部指针会被当作 MoonOHOS 句柄读取；现在在读取指针之前就以 TypeError 拒绝。
- `kind`：本模块的 `CancelToken` 当作 `SearchIndex` 传入，按句柄种类拒绝。
- `plain`：普通对象 `{}`。
- `method` / `close`：用 `call` 把 `this` 换成外来对象，分别调用声明的方法 `stats` 和内置的 `close`。
- `own` / `after`：本模块的句柄在拒绝外来对象前后都能正常使用。

截图 `evidence/v0.7/search-page.jpeg` 是第一轮大型文档集查询后的页面。完整日志：`evidence/v0.7/search-device-run-1.log`、`search-device-run-2.log`；HAP 的 SHA-256 记录在 `search-device-summary.json`。

## 胶水层补强：TypedArray、外部内存、多环境（2026-11-11）

### 宿主

| 检查 | 结果 |
|---|---|
| 根模块测试（新增 `typed_array_types_test.mbt`，`method_types_test.mbt` 增加 size 校验） | 77 / 77 |
| `typed_core` / `typed_bridge.cpp` | 通过：四种 TypedArray 作为参数、返回值、结构体字段、Option、数组元素、异步结果和回调参数；带偏移的视图、空数组、NaN/-0/Infinity 原样；元素类型不符、Uint8Array、普通数组、Sendable 视图或缓冲区、已分离缓冲区抛 TypeError；超出元素数和 64 MiB 预算抛 RangeError；Node-API 失败注入、C++ 分配失败注入、10000 轮无泄漏 |
| `async_core` / `method_bridge.cpp` | 通过：`size` 在同步和异步创建时各取一次，`napi_wrap_enhance` 收到 1028 字节，`nativeBytes` 随关闭扣除；`CancelToken` 仍走 `napi_wrap` |
| `async_core` / `env_bridge.cpp` | 通过：两个环境的导出各绑定自己的状态；Worker 环境在任务排队时销毁，只关闭它自己的句柄、只取消它自己的任务，UI 环境的句柄继续可用；4 个环境在 4 个线程上同时调用（每轮 500 次同步调用加异步任务，共 20 轮） |
| 其余 10 个 ASan 套件 | 全部通过 |

`env_bridge.cpp` 发现了一个进程门的竞态：一个线程清空待释放队列之后、解锁之前，另一个线程放进队列的释放请求会一直留到下一次调用 MoonBit。4 线程场景下 25 次中有 2 次各剩 3 个分配（一个 Counter 对象）。修复后 `Retry` 在解锁后重新检查队列，连续 60 次通过。

HarmonyOS SDK 的 `libace_napi.z.so`（两个 ABI）不导出 `napi_adjust_external_memory`，头文件中该函数标为 deprecated；外部内存上报因此改用导出的 `napi_wrap_enhance`（API 18 起）。

### 模拟器

检索示例新增 `index_texts`（内存文本建索引）、`term_idf`（返回 `FixedArray[Double]` 的句柄方法），并为 `SearchIndex` 声明 `"size": "index_bytes"`。应用新增 Worker 脚本和 TaskPool 并发函数。`verify_search_device.ps1` 连续两轮通过，HiLog：

```text
MOONSEARCH_TYPEDARRAY pass type=[object Float64Array] length=3 values=2.159,1.649,0.000
MOONSEARCH_MEMORY pass declared=20395336 delta=20395336 after_close_delta=0
MOONSEARCH_WORKER pass ok hits=2 top=mem/a.md idf=2 envs=2 cleaned=1 envs_before=1 envs_after=1 waited_ms=100
MOONSEARCH_TASKPOOL pass ok hits=1 top=mem/b.md idf=2 envs=2 | ok hits=1 top=mem/b.md idf=2 envs=2 | ok hits=1 top=mem/b.md idf=2 envs=2
MOONSEARCH_PASS live_handles=0 released=11 pending_tasks=0 completed=16 cancelled=4
```

- TypedArray：返回值在 ArkTS 中是真正的 `Float64Array`，未出现的词 IDF 为 0。
- 外部内存：2000 篇文档的索引声明 20,395,336 字节，`nativeBytes` 恰好增加这么多，关闭后回到原值。设备上看不到 ArkTS 垃圾回收器内部如何使用这个数字，这里只证明它经 `napi_wrap_enhance` 传入并随关闭扣除。
- Worker：模块在 Worker 中加载（`liveEnvs` 为 2），在 Worker 里异步建索引、检索、取 TypedArray 都正常；`terminate()` 后 100 ms 内该环境的清理钩子运行（`envCleanups` 加 1），`liveEnvs` 回到 1。
- TaskPool：3 个并发任务都在 TaskPool 线程中完成异步建索引和检索。3 个任务报告的 `liveEnvs` 都是 2，说明它们落在同一个 TaskPool 线程环境里；TaskPool 线程不随任务结束而销毁，所以这里没有观察清理。
- 第一次构建时 `Concurrency.ets` 从 Worker 脚本导入 `SearchJob`，主线程因此执行了 Worker 脚本的顶层代码，页面没有继续运行。把消息类挪到单独的 `workers/SearchJob.ets` 后通过。Worker 脚本只应被 `ThreadWorker` 加载。

证据：`evidence/v0.7/search07-device-run-1.log`、`search07-device-run-2.log`、`search07-page.jpeg`、`host-typed_bridge.log`、`host-env_bridge.log`、`host-method_bridge.log`。

## 未验证

- 0.5 的 `Int64`、Option、枚举，以及 `deviceinfo`、`netconn`、`vibrator` 平台包仍未在设备上运行（检索示例没有用到它们）。`Float32Array`、`Int32Array`、`BigInt64Array` 只在宿主上验证，设备上只运行了 `Float64Array`。
- TaskPool 线程环境的销毁（应用退出时）没有单独观察。
- `init` 演示应用的 HAP 只完成构建，没有在模拟器上运行。
- ARM64 真机、签名与上架流程。
