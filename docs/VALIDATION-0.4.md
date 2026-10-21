# MoonOHOS 0.4 验证记录

记录日期：2026-10-21。0.1–0.3 记录保留在 [VALIDATION.md](VALIDATION.md)、[VALIDATION-0.2.md](VALIDATION-0.2.md)、[VALIDATION-0.3.md](VALIDATION-0.3.md)。

## 环境

- Windows 11 x64；Moon `0.1.20260920 (914d7da)`，moonc `v0.10.14+7d59c7ec9`；MSVC 14.43（宿主 ASan）。
- DevEco Studio 26.0.0.821，HarmonyOS SDK API 26（26.0.0.105），hvigor 6.26.4，ohpm 26.0.0.630。
- 模拟器 Pura 90 Pro，x86_64，HarmonyOS API 26。

## 结果总览

| 能力 | 已实现 | 宿主验证 | 模拟器验证 |
|---|---|---|---|
| 工作线程执行 MoonBit、UI 不阻塞 | ✓ | ✓ 并发与压力测试 | ✓ 探针与检索应用（UI 定时器在建索引期间持续触发） |
| CancelToken 取消（执行前 / 执行中） | ✓ | ✓ | ✓ AbortError，约 150–170 ms 结束 |
| 句柄 close / 固定中关闭 / 终结 / 环境销毁 | ✓ | ✓ | ✓ 离开页面后 `liveHandles=0` |
| 业务错误（`raise` → `ERR_MOONOHOS_BUSINESS`） | ✓ | ✓ | ✓ RawFile 错误路径（宿主）；设备上未单独触发 |
| Native 依赖描述机制 | ✓ | ✓ CLI 拒绝/接受用例 | ✓ 动态库链接 `libhilog_ndk.z.so`、`librawfile.z.so` 并在设备加载 |
| HiLog 平台包 | ✓ | ✓ 宿主回退 | ✓ MoonBit 写出 `MOONSEARCH_INDEX_*` 日志 |
| RawFile 平台包与 ResourceManager 适配 | ✓ | ✓ 宿主目录替身 | ✓ 在工作线程读取 2000 个打包文档 |
| `moonohos init` | ✓ | ✓ CLI 用例 | — |
| `moonohos har`（含 hvigor assembleHar） | ✓ | ✓ 准备阶段 CLI 用例 | ✓ 独立应用仅依赖 `.har` 安装运行 |
| 离线文档检索示例 | ✓ | ✓ 7 个单元测试 | ✓ 两次完整运行（各含两轮进入/离开） |
| 0.3 能力回归（标量、引用、容器） | ✓ | ✓ | ✓ 13 + 14 + 10 项检查，两次重启 |

## 单元与宿主测试

| 检查 | 结果 | 证据 |
|---|---|---|
| 根模块 `moon test --target native --deny-warn` | 44/44 | — |
| `ohos` 模块测试（hilog、rawfile、task 宿主回退） | 3/3 | — |
| 检索核心测试（分词、BM25、摘要、取消、RawFile） | 7/7 | — |
| 标量与引用 ASan（10000 轮） | 通过，活跃分配增量 0 | [host_bridge](evidence/v0.4/host-host_bridge.log) |
| 数组 / 记录 / 引用矩阵 ASan | 通过 | [array](evidence/v0.4/host-array_bridge.log)、[record](evidence/v0.4/host-record_bridge.log)、[matrix](evidence/v0.4/host-matrix_bridge.log) |
| 异步、句柄、适配器、业务错误、取消、环境销毁、失败注入、并发、10000 轮 | 通过，`live_handles=0 pending=0` | [async](evidence/v0.4/host-async_bridge.log) |
| 8 线程 × 20000 轮并发调用 | 通过，活跃分配 0 | [thread](evidence/v0.4/host-thread_probe.log) |

宿主测试使用 `tests/mock/napi/native_api.h` 替身：async work 的 execute 在真实 `std::thread` 上运行，complete 在调用线程执行；Promise 重复 settle、async work 重复删除会直接报错。替身不模拟 HarmonyOS 加载器和 ArkRuntime。

## CLI 与集成

| 检查 | 结果 | 证据 |
|---|---|---|
| `verify_cli.py`：Unicode/空格路径、缓存、损坏恢复、ELF 篡改、init、工作区平台构建、5 类 Native 依赖拒绝、受描述 stub 接受、v1 清单兼容、HAR 准备 | 41 个场景通过 | [cli-results](evidence/v0.4/cli-results.json) |
| `verify_integration.py`：中文路径双 ABI 构建、错误配置、引用矩阵 ASan、HAP 双 ABI | 11 项通过 | — |
| `verify_init_flow.ps1`：新目录 init → 双 ABI build → har --assemble | 通过；HAR 含两 ABI 库、类型包、生成门面与来源记录 | [init-flow](evidence/v0.4/init-flow-summary.json) |
| 注册表消费：独立模块从 Mooncakes 安装 `shop1111/moonohos_ohos@0.4.0` 并运行宿主测试；`init`（不带 `--ohos`）工程从注册表解析平台包并完成构建 | 通过 | — |
| 生产代码统计（排除测试、示例、fixture、生成代码、注释和纯字符串行） | 5983 行（门槛 4000） | [production-lines](evidence/v0.4/production-lines.json) |

## 模拟器

### 探针（P1b/P3）

手写探针库经 hvigor 打包为 HAR，由独立应用以 `file:` 依赖安装。结论见 [ASYNC-THREADING.md](ASYNC-THREADING.md)。证据：[probe-runtime](evidence/v0.4/probe-runtime.log)、[probe-artifacts](evidence/v0.4/probe-artifacts.json)。

### 离线文档检索应用

`scripts/build_search.ps1` 构建：CLI 生成双 ABI 包 → `moonohos har --assemble` → 生成 2000 篇合成文档（8,571,784 字节，SHA256 `b27706087996e4eaac7ba69755d9ed7dc7dafca01a005e3e4d013248c8557abe`）→ 独立应用 assembleHap。`scripts/verify_search_device.ps1` 运行两次脚本化场景（每次之间强制停止），每次两轮：

1. 小型文档集（12 篇）建索引，异步查询“离线检索”，同步查询 `rawfile`；
2. 大型文档集建索引 150 ms 后取消 → `AbortError`；
3. 大型文档集完整建索引（约 2 秒，期间界面定时器触发约 20 次）并查询；
4. 再次建索引时离开页面 → 任务取消、索引关闭；
5. 返回首页读取诊断，再进入第二轮；最终 `MOONSEARCH_PASS live_handles=0 released=4 pending_tasks=0 completed=8 cancelled=4`。

| 产物 | SHA256 |
|---|---|
| `search.har` | `EF9B2EB2A8BFC195BAD848EE3C5DA0BE19CCBF439ADB748B2DFD12ACC739850A` |
| `entry-default-unsigned.hap`（search-app） | `548028C5EEAE52C4DEE2CD0771AF7248296CFDB36BD62B5548E7DCA93AD04639` |

证据：[run-1](evidence/v0.4/search-device-run-1.log)、[run-2](evidence/v0.4/search-device-run-2.log)、[summary](evidence/v0.4/search-device-summary.json)、[artifacts](evidence/v0.4/search-artifacts.json)、[截图](evidence/v0.4/search-page.jpeg)。

### 0.3 回归应用

`examples/harmony` 使用 0.4 生成的包：标量 13 项、引用 14 项、容器 10 项、重复调用 1000 次，强制停止后重启两次均通过。HAP SHA256 `969C4602F89708B8CEAB6C1A77D6263BAD01E39C75421B98BDBF4EE04038D33B`。证据：[runtime](evidence/v0.4/regression-runtime.log)、[restart-1](evidence/v0.4/regression-restart-1.log)、[restart-2](evidence/v0.4/regression-restart-2.log)、[截图](evidence/v0.4/regression-page.jpeg)。

回归过程中发现 ArkRuntime 以空 `code` 创建 `RangeError` 时得到普通 `Error`，已修复（同步转换错误改用 `napi_throw_range_error`），修复后上述检查通过。

## 未验证

- ARM64 真机运行（只验证了 arm64-v8a 交叉编译、ELF 检查和 HAP 打包）。
- 应用签名与上架流程；所有 HAP 为未签名调试包。
- 旧 SDK、独立 OpenHarmony 产品。
- 在 ArkTS Worker 中加载生成模块的完整场景（只用探针库验证了 Worker 终止顺序）。
- Option、Int64、枚举、类、回调、零复制缓冲区。

## 复现

```powershell
moon test --target native --deny-warn
python scripts\verify_containers.py async_core async_bridge.cpp
python scripts\verify_cli.py --sdk 'D:\apps\DevEco Studio\sdk'
python scripts\verify_integration.py 'D:\apps\DevEco Studio\sdk'
.\scripts\verify_init_flow.ps1
.\scripts\build_search.ps1
.\scripts\verify_search_device.ps1
```
