# MoonOHOS 0.5 验证记录

记录日期：2026-11-01。0.4 及更早记录见 [VALIDATION-0.4.md](VALIDATION-0.4.md)。

## 环境

- Windows 11 x64；Moon `0.1.20261028 (e1e1f15)`，moonc `v0.10.18+6c83a7f62`；MSVC 14.43（宿主 ASan）。
- DevEco Studio 26（HarmonyOS SDK API 26），hvigor、ohpm 同 0.4。
- CI：Windows（固定工具链）、Ubuntu 24.04、macOS 15、最新 MoonBit（预警，不阻塞）。

## 新增能力与证明范围

| 能力 | 已实现 | 宿主验证 | SDK 交叉编译 / HAR / HAP | 设备运行 |
|---|---|---|---|---|
| `Int64` ↔ `bigint`（参数、返回、数组、结构体字段） | ✓ | ✓ `wide_bridge.cpp`：范围检查、类型错误、失败注入、10000 轮无泄漏 | ✓ | 未验证 |
| `T?` / `Option[T]` ↔ `T \| undefined`（含缺失字段、`null`） | ✓ | ✓ `option_bridge.cpp` | ✓ 双 ABI 构建并通过 `verify` | 未验证 |
| 无载荷枚举 ↔ 字符串字面量联合 | ✓ | ✓ `enum_bridge.cpp`：未知名称、数组、Option | ✓ HAR 门面重导出类型，hvigor assembleHar 通过 | 未验证 |
| 句柄方法（`index.search(q)`） | ✓ | ✓ `method_bridge.cpp`：同步、异步、raises、已关闭、失败注入 | ✓ 检索示例声明方法，HAP 构建通过 | 未验证 |
| `deviceinfo`、`netconn`、`vibrator` 平台包 | ✓ | ✓ 宿主回退测试 6/6 | ✓ 双 ABI 链接 `libdeviceinfo_ndk.z.so`、`libnet_connection.so`、`libohvibrator.z.so`，`verify` 通过 | 未验证 |
| `init` 演示应用 + `har --app` | ✓ | ✓ 模板单元测试 | ✓ `verify_init_flow.ps1`：init → build → HAR → HAP，HAP 含两个 ABI 的库 | 未验证 |
| CLI 跨平台（Linux、macOS） | ✓ | ✓ CI 无 SDK 流程 | — | — |

Option 与枚举不依赖编译器内存布局：生成的 MoonBit 包装层在 C 边界把 Option 降为 0/1 元素数组、把枚举降为整数标签，再在另一侧恢复。

## 本地全量检查（2026-11-01）

| 检查 | 结果 |
|---|---|
| `moon fmt` 无差异、`moon check --deny-warn --warn-list +73`、`moon info` 接口一致 | 通过 |
| 根模块测试 / `ohos` / `examples/search` / `examples/core` | 65 / 6 / 10 / 2，全部通过 |
| 宿主 ASan 套件（数组、记录、引用矩阵、异步、8 线程并发、Int64、Option、枚举、句柄方法） | 9 项全部通过 |
| `verify_cli.py` | 41 个场景通过 |
| `verify_integration.py` | 10 项通过（第 11 项“回归应用 HAP”只在本机已构建 `examples/harmony` 时运行，本次工作树未构建） |
| `verify_init_flow.ps1`（含演示应用 HAP） | 通过 |
| `build_search.ps1`（CLI → HAR → HAP，SearchIndex 带方法） | 通过 |
| 生产代码统计 | 7077 行（门槛 4000） |

## 开发中：ArkTS 回调（未发布，2026-11-01）

| 检查 | 结果 |
|---|---|
| 根模块测试（新增 `callback_types_test.mbt`：语法、`.mbti` 核对、参数限制、生成代码、符号冲突） | 70 / 70 |
| `ohos` / `examples/search`（新增进度回调测试） / `examples/core` | 6 / 11 / 2 |
| 宿主 ASan `callback_core` / `callback_bridge.cpp` | 通过：同步回调与各类参数（结构体、Option、Bytes、Int64、枚举）、回调中重入调用本模块、回调抛错、非函数参数、非有限 Double、保存后再调用的闭包被忽略、同步调用每个 Node-API 失败点、异步按序投递且 Promise 在最后一个回调后完成（两种 complete/回调先后顺序）、双回调顺序、回调抛错拒绝、执行前取消、异步失败注入、环境销毁时排队与暂存的任务、16 任务 × 50 轮真实线程、10000 轮无分配增长；结束时引用、handle scope、线程安全函数全部释放，`pendingTasks` 为 0 |
| 其余 9 个宿主 ASan 套件 | 全部通过（进程门改为可重入后回归） |
| `verify_cli.py` / `verify_integration.py` | 41 / 11 通过 |
| `verify_init_flow.ps1` | 通过 |
| `build_search.ps1`（`build_index_reporting` 进度回调，HAR 门面与页面 ArkTS 编译） | 通过；`libmoonsearch.so` 双 ABI，导入 `napi_create_threadsafe_function` / `napi_call_threadsafe_function` |
| 生产代码统计 | 7331 行 |

SDK 头文件（API 26 `napi/native_api.h`）说明 `func` 与 `call_js_cb` 不能同时为空；生成代码传空 `func`、在 `call_js` 中取引用值，符合该约定。回调尚未在模拟器或真机上运行。

## 未验证

- 0.5 新能力和开发中的回调在模拟器或真机上的运行：本次没有连接设备，只完成宿主 ASan、SDK 交叉编译、HAR/HAP 打包。
- `netconn`、`vibrator` 在设备上的权限路径（201 错误）只在宿主回退中模拟。
- ARM64 真机、签名与上架流程。
- ArrayBuffer/其他 TypedArray、带载荷枚举、有返回值的回调（尚未实现，见 README 路线图）。
