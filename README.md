# MoonOHOS：面向 HarmonyOS 的 MoonBit Native 模块开发框架

[![Windows](https://github.com/shop1111/MoonOHOS/actions/workflows/windows.yml/badge.svg)](https://github.com/shop1111/MoonOHOS/actions/workflows/windows.yml)
[![Linux and macOS](https://github.com/shop1111/MoonOHOS/actions/workflows/cross-platform.yml/badge.svg)](https://github.com/shop1111/MoonOHOS/actions/workflows/cross-platform.yml)
[![Mooncakes](https://img.shields.io/badge/mooncakes-shop1111%2Fmoonohos-orange)](https://mooncakes.io/docs/shop1111/moonohos)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue)](LICENSE)

中文 | [English](README.en.md)

用 MoonBit 编写鸿蒙应用的 Native 部分：耗时计算在后台线程执行，界面不卡；MoonBit 可以直接调用鸿蒙系统能力；结果打包成 HAR，ArkTS 导入即可使用。

## 为什么用它

大多数鸿蒙应用只用 ArkTS 就够了。以下情况值得把一部分代码放到 Native 层：

- **CPU 密集计算**：检索、解析、压缩、加密、图像和音频处理。
- **跨平台复用**：同一份核心逻辑还要给其他平台使用。
- **直接调用 NDK**：使用只有 C 接口的系统能力。

鸿蒙官方的 Native 方案是 C/C++。MoonOHOS 让你改用 MoonBit：内存安全，语法接近 TypeScript，编译快，产物小；不依赖平台包的 MoonBit 代码还能编译到 Wasm 和 JavaScript。

不适合的情况：

- 普通界面和业务逻辑：用 ArkTS 即可。
- 主要依赖现成 C++ 库的项目：直接用 C++ 更省事。
- 要求生态成熟度的项目：MoonBit 的库还不多，编译器仍在演进。
- 不能接受进程退出的场景：MoonBit `panic` 会结束应用进程。

## 架构与状态

| 层次 | 作用 | 状态 |
|---|---|---|
| 鸿蒙运行时 | ArkTS ↔ MoonBit：类型转换、d.ts 生成、后台线程任务、取消、ArkTS 回调、句柄生命周期 | **已实现**。宿主 ASan 覆盖全部能力。**x86_64 模拟器上已运行**（moonc 0.10.20 构建，2026-11-11）：后台线程异步任务、取消、ArkTS 进度回调、句柄方法、句柄类型标记、句柄生命周期，以及 0.7 的 `Float64Array`、外部内存上报、在 Worker 和 TaskPool 中加载模块。**设备上尚未运行**：Int64、Option、枚举、其他三种 TypedArray |
| 系统能力 | MoonBit 直接调用鸿蒙 NDK | **已实现（0.8）**：`moonohos bindgen` 由 SDK 自带的 clang 解析头文件，生成 MoonBit 包、C 桩函数和描述文件。14 个 `sys/*` 包（显示、传感器、电池、设备信息、HiTrace、HiDebug、QoS、时区、系统账号、权限自查、syscap、Wi-Fi、蓝牙、振动），共绑定 160 个函数，包括 SDK 句柄（销毁或回收时释放）和回调（MoonBit 闭包，在 SDK 线程上经进程门调用）。两个 ABI 都对着真实 SDK 以 `-Werror` 编译并链接通过；模拟器上运行过显示器句柄、显示变化监听和环境光传感器订阅。另有 6 个手写平台包（`hilog`、`rawfile`、`task` 等），以及第三方 C 依赖的接入机制。见 [BINDGEN.md](docs/BINDGEN.md) |
| 图形 | MoonBit 通过 XComponent 渲染画面、处理触摸 | **计划中** |
| 工程集成 | 初始化、交叉编译、HAR 打包、产物校验 | **已实现** CLI（`init`、`build`、`har`、`verify`）。**计划**：Hvigor 插件，在 DevEco 中直接构建；发布到 ohpm |

| 文档 | 内容 |
|---|---|
| [ASYNC-THREADING.md](docs/ASYNC-THREADING.md) | 线程模型、取消、回调、生命周期 |
| [NATIVE-EXTENSIONS.md](docs/NATIVE-EXTENSIONS.md) | 平台包与 Native 依赖接入 |
| [COMPARISON.md](docs/COMPARISON.md) | 与 napi-mbt、ohos-rs 的逐项对照 |
| [BINDGEN.md](docs/BINDGEN.md) | 系统能力绑定生成：清单格式、类型对应、校验方法、首批模块 |
| [VALIDATION-0.8.md](docs/VALIDATION-0.8.md) | 生成绑定的 SDK 编译链接与模拟器运行记录 |
| [VALIDATION-0.7.md](docs/VALIDATION-0.7.md) | moonc 0.10.20 构建的模拟器运行记录：异步、取消、回调、类型标记、TypedArray、外部内存、Worker/TaskPool |
| [VALIDATION-0.5.md](docs/VALIDATION-0.5.md) | 各项能力的验证范围（0.4 见 [VALIDATION-0.4.md](docs/VALIDATION-0.4.md)） |

### 与 napi-mbt 的关系

[napi-mbt](https://github.com/unmbt/napi-mbt) 是面向 Node.js 的 MoonBit 绑定工具，通用绑定的覆盖面比 MoonOHOS 广。但它的 MoonBit 代码只在 JS 线程上运行，后台计算依靠启动 Node 子进程；它也不支持交叉编译，产物是 npm 包。这些在鸿蒙上都无法使用。MoonOHOS 的胶水层为移动端 UI 应用设计，MoonBit 在后台线程执行；本项目不追求通用绑定的广度，主要投入在系统能力、图形和工程集成上。逐项依据见 [COMPARISON.md](docs/COMPARISON.md)。

## 环境

| 组件 | 要求 | 说明 |
|---|---|---|
| MoonBit | moonc **≥ 0.10.20** | 已测试 Moon `0.1.20261104`、moonc `v0.10.20+65efd5b93`；更新版本可用，`doctor` 标为 untested。0.10.18 及更早版本不支持 `#derive(...)` 写法 |
| 主机 | Windows x64（完整验证）；Linux、macOS（CI 覆盖 CLI 与库） | CLI 是 MoonBit Native 程序，Windows 需 MSVC C++ Build Tools，其他平台需 cc/clang |
| HarmonyOS SDK | API **≥ 26** | DevEco Studio 自带，或 command-line-tools；`build`、`har` 需要，`init`/`check`/`inspect`/`plan`/`verify` 不需要 |
| 目标 ABI | `arm64-v8a`、`x86_64` | 已在 x86_64 模拟器（API 26）运行；ARM64 真机尚未验证 |

工具链不满足要求时命令停止并给出修复提示，不修改全局开发环境。运行 `moonohos doctor --sdk <SDK> --json` 查看每一项。

## 快速开始

CLI 和平台模块已发布到 Mooncakes：`shop1111/moonohos`、`shop1111/moonohos_ohos`。下面的 `DEVECO` 是 DevEco Studio 安装目录（Windows 如 `C:\Program Files\Huawei\DevEco Studio`，macOS 为 `/Applications/DevEco-Studio.app`，Linux 为 command-line-tools 目录）。

```bash
moon install shop1111/moonohos/cmd/moonohos        # 或在本仓库中：moon build --target native --release cmd/moonohos
moonohos init textkit --package alice/textkit       # 生成 MoonBit 模块、清单和 HAR 工程
cd textkit
moonohos check                                      # 不需要 SDK：严格编译生成的包装层
moonohos build --sdk "$DEVECO/sdk" --out _build/dist
moonohos har --dist _build/dist --module harmony/textkit --assemble --app --deveco "$DEVECO"
```

`--app` 同时构建 `harmony/entry` 演示应用（未签名调试 HAP），页面调用同步 `greet` 和可取消的异步 `count_words`；在 DevEco Studio 打开 `harmony/` 签名后即可运行。

每个命令都支持 `--help` 和 `--json`；失败时输出分类错误码（如 `toolchain`、`interface`、`config`）和下一步建议。

生成的工程：

```text
textkit/
  moon.work                 # 工作区；--ohos 时加入本地 ohos 平台模块
  moonohos.json             # 桥接清单（version 2）
  core/                     # MoonBit 库：同步 greet，异步可取消 count_words（使用 HiLog）
  harmony/                  # Hvigor 工程
    textkit/                # HAR 模块：Index.ets 重导出原生模块
    entry/                  # 演示应用：以本地依赖使用上面的 HAR
```

应用接入 HAR：

```json
{"dependencies": {"@alice/textkit": "file:../textkit/harmony/textkit/build/default/outputs/default/textkit.har"}}
```

```typescript
import textkit, { CancelToken } from '@alice/textkit';

const token: CancelToken = textkit.createCancelToken();
const words: number = await textkit.count_words(longText, token);  // 工作线程执行
token.cancel();                                                     // 页面退出时取消
```

生成的 `core/moon.mod` 从 Mooncakes 依赖 `shop1111/moonohos_ohos@0.8.0`。修改平台模块时可加 `--ohos <MoonOHOS/ohos>`，让工作区引用本地目录；构建时工作区全部成员被复制到隔离目录，原始文件不被修改。

### 与手工接入的对比

| 步骤 | 手工（NDK + CMake） | MoonOHOS |
|---|---|---|
| 新建工程 | 手写 Node-API 胶水代码、CMake 和 DevEco 工程 | `moonohos init` |
| 编译 | 自己配置 MoonBit 生成的 C 代码、运行时和鸿蒙 clang，分别编两个 ABI | `moonohos build` |
| 原生库进入应用 | 复制两个 ABI 的 `.so` 到 `entry/libs/<abi>/` | `moonohos har` 放入 HAR 模块 |
| 类型声明 | 手写 `index.d.ts` 并复制到 `entry/src/main/cpp/types/` | 自动生成，HAR 内置类型包与 ArkTS 门面 |
| 打包分发 | 自己配置 HAR 模块 | `--assemble` 调用 hvigor 生成 `.har` |
| 其他应用复用 | 重复以上复制 | 一行 `file:` 依赖 |
| 耗时计算 | 自己写 async work，保证 MoonBit 堆不被并发访问 | `"async": true`，带取消 |
| 使用系统能力 | 自己写 MoonBit extern 和 C 中转代码 | 平台包；第三方 C 依赖按描述文件接入 |

## 清单 moonohos.json

version 1 清单保持不变；version 2 增加工作区、句柄、异步和业务错误：

```json
{
  "version": 2,
  "module": "core",
  "package": "moonohos/search",
  "nativeModule": "moonsearch",
  "workspace": "moon.work",
  "handles": [{"name": "SearchIndex", "methods": ["search"]}],
  "enums": [{"name": "Mode", "cases": ["Exact", "Prefix"]}],
  "types": [{"name": "Hit", "fields": [{"name": "path", "type": "String"}, {"name": "score", "type": "Double"}]}],
  "functions": [
    {"name": "build_index", "params": [{"name": "resources", "type": "@rawfile.Manager"}, {"name": "dir", "type": "String"}],
     "return": "SearchIndex", "async": true, "raises": true},
    {"name": "search", "params": [{"name": "index", "type": "SearchIndex"}, {"name": "query", "type": "String"}, {"name": "limit", "type": "Int"}],
     "return": "Array[Hit]", "async": true}
  ]
}
```

| MoonBit | ArkTS | 说明 |
|---|---|---|
| `Int` / `Double` / `Bool` | `number` / `number` / `boolean` | Int 为有限 32 位整数，Double 必须有限 |
| `Int64` | `bigint` | 有符号 64 位，超出范围抛 RangeError，传入 number 抛 TypeError（0.5） |
| `T?` / `Option[T]` | `T \| undefined` | 参数、返回值、数组元素、结构体字段（声明为 `field?: T`，缺失、`undefined`、`null` 都读作 `None`）；不支持嵌套 Option（0.5） |
| 无载荷枚举（`"enums"`） | 字符串字面量联合，如 `'Debug' \| 'Info'` | 未知名称抛 TypeError；清单中的 case 与 `.mbti` 核对（0.5） |
| `Unit`（返回值） | `void` | |
| `String` | `string` | UTF-16 码元原样复制，支持内嵌 NUL 与未配对代理 |
| `Bytes` | `Uint8Array` | 只接受普通、未分离 ArrayBuffer 上的视图，复制 |
| `FixedArray[Double]` / `FixedArray[Float]` / `FixedArray[Int]` / `FixedArray[Int64]` | `Float64Array` / `Float32Array` / `Int32Array` / `BigInt64Array` | 元素存储整块复制（memcpy），接受带偏移的视图；元素类型不符、普通数组、Sendable 或已分离的缓冲区抛 TypeError。NaN、Infinity 原样保留。可用于参数、返回值、结构体字段、数组元素、Option、异步结果和回调参数（0.7） |
| `Array[T]` | `Array<T>` | 稠密、非 Sendable，复制 |
| 结构体 | `interface` | 目标包需 `pub(all) struct`，字段为自有属性，复制 |
| 句柄（`handles`） | 带 `close()`/`isClosed()` 的对象 | MoonBit 值保留在原生侧，不复制；不能嵌套在数组或结构体中。`"methods"` 列出的函数（第一个参数是该句柄）同时成为对象方法：`index.search(q)` 等价于 `search(index, q)`（0.5）。对象带本模块的类型标记，别的原生模块的对象在读取指针前被拒绝（0.7）。`"size"` 指定一个 `(句柄) -> Int` 函数，句柄创建时调用一次，返回的字节数通过 `napi_wrap_enhance` 告知 ArkTS 垃圾回收器（0.7） |
| `@包.类型`（平台适配） | 如 `resourceManager.ResourceManager` | 仅作参数；由描述文件中的适配器获取与释放 |
| 回调 `(T1, T2) -> Unit`（仅作参数） | `(arg0: T1, arg1: T2) => void` | 同步函数在调用期间直接在 UI 线程回调，回调里可以再调用本模块；异步函数在工作线程把参数复制进队列，按顺序回到 UI 线程执行，全部送达后 Promise 才完成。回调抛错时后续回调不再执行，`@task.check()` 观察到取消，调用以该错误失败。调用返回后被保存的闭包再调用会被忽略。参数须是可复制的值（不能是句柄、平台对象或回调），最多 16 个（0.6） |
| `"async": true` | `(..., token?: CancelToken) => Promise<T>` | 工作线程执行 |
| `"raises": true` | 抛出/拒绝 `code = ERR_MOONOHOS_BUSINESS` | MoonBit 函数须声明 `raise`，消息取错误的 `Show` 文本 |

每个模块还导出 `createCancelToken()` 和 `moonohos_diagnostics()`（存活句柄、任务计数、`liveEnvs`、`nativeBytes` 等）。

模块可以在 UI 线程、Worker 和 TaskPool 中分别加载（0.7）：每个 ArkTS 环境有自己的模块状态，句柄和任务属于创建它们的环境，Worker 销毁时只关闭它自己的句柄、取消它自己的任务。所有环境共用一个 MoonBit 运行时，调用 MoonBit 时互斥（见 [ASYNC-THREADING.md](docs/ASYNC-THREADING.md)）。

函数必须是所选包公开的普通函数，参数、顺序、返回类型和 `raise` 与清单一致。参数或返回值含数组、结构体或 Option 的调用，每次转换最多嵌套 32 层、1,048,576 个元素/字段、复制 64 MiB，超限抛出 RangeError；其余调用中的 String、Bytes 和 TypedArray 只受 32 位长度限制；缺少参数或类型错误抛出 TypeError。MoonBit `panic` 会终止进程。不支持泛型、`#value` 结构体、可选或标记参数、带载荷的枚举、有返回值的回调。

## 命令

```text
moonohos init <dir> [--name <module>] [--package owner/name] [--ohos <path>] [--json]
moonohos build --sdk <SDK> [--config moonohos.json] [--abi arm64-v8a,x86_64] [--out <dir>] [--dry-run] [--cache] [--json]
moonohos har --dist <package> --module <HAR module> [--assemble --deveco <DevEco Studio>] [--json]
moonohos doctor [--sdk <SDK>] [--json]
moonohos check | inspect | plan [--config moonohos.json] [--json]
moonohos verify --out <package> [--json]
moonohos <command> --help
```

- `build` 默认构建两个 ABI，输出目录必须不存在；`--dry-run` 只验证配置和工具链；`--cache` 按源码、依赖、清单、编译器、运行时、SDK 与生成器内容计算缓存键，命中前验证整个包，损坏条目改名保留后重建。
- `har` 先 `verify` 包，再把库、类型包、NOTICE、来源记录（`moonohos-har.json`）和生成的 `src/main/ets/generated/Native.ets` 写入 HAR 模块；`--assemble` 依次运行 DevEco 的 ohpm install 与 hvigor `assembleHar`，报告 `.har` 的 SHA256。
- `check` 严格编译临时包装包；`inspect` 输出接口摘要；`plan` 输出有序构建阶段；`verify` 无需 SDK，核对清单、SHA256、类型包、CMake 导入、ELF64 架构、段和动态依赖。
- 成功退出 0，参数错误退出 2，诊断或构建失败退出 3；`--json` 输出单个结构化报告，`diagnostics[].code` 是错误类别，`context` 是修复建议。外部进程以参数数组启动并带超时，阶段日志写入工作目录，分发包不含机器相关日志。

## 产物

```text
dist/
  libs/{arm64-v8a,x86_64}/lib<module>.so
  types/lib<module>/{index.d.ts,oh-package.json5}
  cmake/MoonOHOS.cmake
  manifest.json            # moonohos-build-v2：文件 SHA256、导出（async/raises）、句柄、Native 依赖
  NOTICE.NativeSDK.txt  NOTICE.MoonBit.txt  README.md
```

编译器只生成 C；MoonOHOS 用同版本运行时源码、生成的适配层、C++ 生命周期运行时和 Native 依赖源码，以 SDK Clang/CMake/Ninja 交叉编译，C++ 标准库静态链接。动态库只允许依赖 `libace_napi.z.so`、libc/libm/libdl 与清单声明的白名单 NDK 库。

## 离线文档检索示例

- [examples/search/core](examples/search/core)：MoonBit 检索模块。ASCII 单词与汉字单字/双字分词、倒排索引、BM25 排序、摘要；通过 `@rawfile` 读取打包文档，`@hilog` 记录进度，`@task` 在建索引时检查取消。
- [examples/search/harmony/search](examples/search/harmony/search)：HAR 模块，`SearchSession` 封装打开、取消、搜索与关闭。
- [examples/search-app](examples/search-app)：独立 Stage 应用，只依赖 `search.har`。

```powershell
.\scripts\build_search.ps1                 # CLI 构建 → HAR → 生成 2000 篇合成文档 → HAP
.\scripts\verify_search_device.ps1         # 模拟器上运行脚本化场景两次
```

原 `examples/harmony` 保留为类型转换回归应用。

## 验证

脚本从环境变量 `DEVECO_STUDIO` 读取 DevEco Studio 目录（未设置时尝试默认安装位置）。

```powershell
moon fmt; moon check --target native --deny-warn; moon test --target native --deny-warn; moon info --target native
python scripts\verify_containers.py async_core async_bridge.cpp
python scripts\verify_cli.py --sdk "$env:DEVECO_STUDIO\sdk"
python scripts\verify_integration.py "$env:DEVECO_STUDIO\sdk"
.\scripts\verify_init_flow.ps1
.\scripts\verify_device.ps1 -Hdc "$env:DEVECO_STUDIO\sdk\default\openharmony\toolchains\hdc.exe"
```

宿主测试在 MSVC AddressSanitizer 下运行实际生成的 MoonBit C 代码和桥接回调，使用 Node-API 替身（async work 在真实线程执行）；设备脚本在模拟器上安装应用并读取 HiLog 标记。

| CI | 内容 |
|---|---|
| Windows（固定工具链） | 格式、严格检查、测试、接口一致性、CLI 构建、打包、代码量门槛、宿主 ASan |
| Linux、macOS | 格式、严格检查、框架/平台模块/示例测试、接口一致性、CLI 构建、无 SDK 的 init → check → inspect → plan |
| 最新 MoonBit | 用最新发布的工具链检查和测试，提前发现不兼容（不阻塞合并） |

SDK、HAP 与模拟器检查在本机执行。各层证明范围见 [VALIDATION-0.7.md](docs/VALIDATION-0.7.md)（模拟器运行）和 [VALIDATION-0.5.md](docs/VALIDATION-0.5.md)。

## 路线图

已完成：0.4 鸿蒙运行时、平台包与 HAR 分发；0.5 Int64、Option、无载荷枚举、句柄方法、`deviceinfo`/`netconn`/`vibrator`、`init` 演示应用、Linux/macOS CLI；0.6 ArkTS 回调；0.7 句柄类型标记、TypedArray、外部内存上报、Worker/TaskPool 加载。

接下来按层推进（欢迎在 issue 中讨论优先级）：

1. **鸿蒙运行时**：在模拟器上验证 Int64、Option、枚举和平台包。借鉴 napi-mbt 设计的四项补强（句柄类型标记、外部内存上报、每个环境独立的状态、TypedArray）已完成，并在模拟器上运行（0.7）。不追求通用绑定的完整度。
2. **系统能力**：绑定生成器、句柄、回调和 14 个模块已完成（0.8）。下一步扩大模块覆盖（文件、加解密、多媒体等），并在 ARM64 真机上验证。
3. **图形**：XComponent 与 Native Drawing，MoonBit 绘制 2D 画面、处理触摸事件，附示例应用。
4. **工程集成**：Hvigor 插件，在 DevEco 中直接构建 MoonBit 模块；发布 HAR 到 ohpm；纯 MoonBit 的 Mooncakes 包一键转为 HAR。
5. **其他**：ARM64 真机验证、中英文档站。

## 参与贡献

欢迎提交问题和 PR，见 [CONTRIBUTING.md](CONTRIBUTING.md)；版本变化见 [CHANGELOG.md](CHANGELOG.md)，安全问题见 [SECURITY.md](SECURITY.md)。

## 许可

MoonOHOS 源码使用 Apache-2.0。分发动态库时保留两份 NOTICE，并补充业务库自身的许可证。第三方组件说明见 [THIRD_PARTY.md](THIRD_PARTY.md)。

参考：[MoonBit FFI](https://docs.moonbitlang.com/en/latest/language/ffi.html)、[HarmonyOS Node-API 开发流程](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/use-napi-process)。
