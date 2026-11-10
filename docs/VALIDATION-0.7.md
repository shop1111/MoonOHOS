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

## 未验证

- 0.5 的 `Int64`、Option、枚举，以及 `deviceinfo`、`netconn`、`vibrator` 平台包仍未在设备上运行（检索示例没有用到它们）。
- `init` 演示应用的 HAP 只完成构建，没有在模拟器上运行。
- ARM64 真机、签名与上架流程。
