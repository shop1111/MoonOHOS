# MoonOHOS：面向 HarmonyOS 的 MoonBit Native 模块开发框架

开发者用 MoonBit 编写可复用的 Native 模块；MoonOHOS 负责鸿蒙宿主适配、系统能力扩展、构建与打包，最终以 HAR 形式通过 ArkTS 接口接入应用。ArkTS 负责界面和系统交互，MoonBit 负责检索、解析、计算等业务核心。

0.4 在 0.3 的接口生成与双 ABI 构建底座之上，新增：

- **鸿蒙运行时**：异步导出在 Node-API 工作线程执行 MoonBit，支持 `CancelToken` 取消；MoonBit 对象可作为句柄交给 ArkTS，关闭、回收和环境退出时释放。
- **平台能力**：`ohos` 模块让 MoonBit 直接使用 HiLog、RawFile 和任务取消；第三方 MoonBit 包可按描述文件携带 C 代码进入 HarmonyOS 动态库。
- **工程分发**：`moonohos init` 生成工程，`moonohos har` 生成 HAR，独立 Stage 应用通过 `file:` 依赖即可使用，无需手工拼接 CMake、类型包和库目录。
- **真实示例**：离线文档检索应用，覆盖资源读取、工作线程建索引、取消、离开页面释放和 HAR 消费。

| 层次 | 内容 | 文档 |
|---|---|---|
| 接口生成 | Int/Double/Bool/String/Bytes/Array/结构体的双向转换，d.ts 生成，清单与 `.mbti` 核对 | 本文“清单” |
| 鸿蒙运行时 | 进程门、工作线程任务、取消、句柄生命周期、env cleanup、诊断计数 | [ASYNC-THREADING.md](docs/ASYNC-THREADING.md) |
| 平台扩展 | `moonohos.native.json` 受控依赖；`hilog`、`rawfile`、`task` 平台包 | [NATIVE-EXTENSIONS.md](docs/NATIVE-EXTENSIONS.md) |
| 工程分发 | `init`、`build`、`har`、`verify`；SHA256 与 ELF 校验 | 本文“命令” |

与 napi-mbt、ohos-rs 的功能对照和借鉴关系见 [COMPARISON.md](docs/COMPARISON.md)。验证结果见 [VALIDATION-0.4.md](docs/VALIDATION-0.4.md)。

## 环境

- Windows x64，Moon `0.1.20260920`，moonc `v0.10.14+7d59c7ec9`，Core `0.10.14+7d59c7ec9`，async `0.21.0`；CLI 由 Moon 调用 MSVC 构建，需要 C++ Build Tools。
- DevEco Studio 26（HarmonyOS SDK API 26、hvigor、ohpm）；目标 ABI `arm64-v8a`、`x86_64`。
- 工具链版本固定，检查不通过时停止，不修改全局开发环境。已在 x86_64 模拟器（API 26）验证，ARM64 真机尚未验证。

## 快速开始

CLI 和平台模块已发布到 Mooncakes：`shop1111/moonohos@0.4.0`、`shop1111/moonohos_ohos@0.4.0`。

```powershell
moon install shop1111/moonohos/cmd/moonohos@0.4.0     # 或在源码仓库中 moon build --target native --release cmd/moonohos
moonohos init textkit --package alice/textkit
moonohos build --config textkit\moonohos.json --sdk 'D:\apps\DevEco Studio\sdk' --out _build/dist
moonohos har --dist textkit\_build\dist --module textkit\harmony\textkit --assemble --deveco 'D:\apps\DevEco Studio'
```

生成的工程：

```text
textkit/
  moon.work                 # 工作区；--ohos 时加入本地 ohos 平台模块
  moonohos.json             # 桥接清单（version 2）
  core/                     # MoonBit 库：同步 greet，异步可取消 count_words（使用 HiLog）
  harmony/                  # Hvigor 工程
    textkit/                # HAR 模块：Index.ets 重导出原生模块
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

生成的 `core/moon.mod` 从 Mooncakes 依赖 `shop1111/moonohos_ohos@0.4.0`。修改平台模块时可加 `--ohos <MoonOHOS/ohos>`，让工作区引用本地目录；构建时工作区全部成员被复制到隔离目录，原始文件不被修改。

### 与 0.3 手工接入的对比

| 步骤 | 0.3 | 0.4 |
|---|---|---|
| 新建工程 | 手写 MoonBit 模块、清单、DevEco 工程 | `moonohos init` |
| 原生库进入应用 | 复制两个 ABI 的 `.so` 到 `entry/libs/<abi>/` | `moonohos har` 放入 HAR 模块 |
| 类型声明 | 复制类型包到 `entry/src/main/cpp/types/`，手写本地依赖 | HAR 内置类型包与 ArkTS 门面 |
| 打包分发 | 无 | `--assemble` 调用 hvigor 生成 `.har` |
| 其他应用复用 | 重复以上复制 | 一行 `file:` 依赖 |
| 耗时计算 | 只能同步调用，阻塞 UI | 异步导出 + 取消 |
| 使用系统能力 | 不支持（拒绝所有 Native stub） | HiLog、RawFile、任务取消；受控扩展 |

## 清单 moonohos.json

version 1 清单保持不变；version 2 增加工作区、句柄、异步和业务错误：

```json
{
  "version": 2,
  "module": "core",
  "package": "moonohos/search",
  "nativeModule": "moonsearch",
  "workspace": "moon.work",
  "handles": [{"name": "SearchIndex"}],
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
| `Unit`（返回值） | `void` | |
| `String` | `string` | UTF-16 码元原样复制，支持内嵌 NUL 与未配对代理 |
| `Bytes` | `Uint8Array` | 只接受普通、未分离 ArrayBuffer 上的视图，复制 |
| `Array[T]` | `Array<T>` | 稠密、非 Sendable，复制 |
| 结构体 | `interface` | 目标包需 `pub(all) struct`，字段为自有属性，复制 |
| 句柄（`handles`） | 带 `close()`/`isClosed()` 的对象 | MoonBit 值保留在原生侧，不复制；不能嵌套在数组或结构体中 |
| `@包.类型`（平台适配） | 如 `resourceManager.ResourceManager` | 仅作参数；由描述文件中的适配器获取与释放 |
| `"async": true` | `(..., token?: CancelToken) => Promise<T>` | 工作线程执行 |
| `"raises": true` | 抛出/拒绝 `code = ERR_MOONOHOS_BUSINESS` | MoonBit 函数须声明 `raise`，消息取错误的 `Show` 文本 |

每个模块还导出 `createCancelToken()` 和 `moonohos_diagnostics()`。

函数必须是所选包公开的普通函数，参数、顺序、返回类型和 `raise` 与清单一致。每次转换最多嵌套 32 层、1,048,576 个元素/字段、复制 64 MiB，超限抛出 RangeError；缺少参数或类型错误抛出 TypeError。MoonBit `panic` 会终止进程。不支持泛型、`#value` 结构体、可选或标记参数、Option、Int64、枚举、类和回调。

## 命令

```powershell
& $cli init <dir> [--name <module>] [--package owner/name] [--ohos <path>] [--json]
& $cli build --config moonohos.json --sdk <SDK> [--abi arm64-v8a,x86_64] [--out <dir>] [--dry-run] [--cache] [--json]
& $cli har --dist <package> --module <HAR module> [--assemble --deveco <DevEco Studio>] [--json]
& $cli doctor --sdk <SDK> --json
& $cli check | inspect | plan --config moonohos.json --json
& $cli verify --out <package> --json
```

- `build` 默认构建两个 ABI，输出目录必须不存在；`--dry-run` 只验证配置和工具链；`--cache` 按源码、依赖、清单、编译器、运行时、SDK 与生成器内容计算缓存键，命中前验证整个包，损坏条目改名保留后重建。
- `har` 先 `verify` 包，再把库、类型包、NOTICE、来源记录（`moonohos-har.json`）和生成的 `src/main/ets/generated/Native.ets` 写入 HAR 模块；`--assemble` 依次运行 DevEco 的 ohpm install 与 hvigor `assembleHar`，报告 `.har` 的 SHA256。
- `check` 严格编译临时包装包；`inspect` 输出接口摘要；`plan` 输出有序构建阶段；`verify` 无需 SDK，核对清单、SHA256、类型包、CMake 导入、ELF64 架构、段和动态依赖。
- 成功退出 0，参数错误退出 2，诊断或构建失败退出 3；`--json` 输出单个结构化报告。外部进程以参数数组启动并带超时，阶段日志写入工作目录，分发包不含机器相关日志。

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

```powershell
moon fmt; moon check --target native --deny-warn; moon test --target native --deny-warn; moon info --target native
python scripts\verify_containers.py async_core async_bridge.cpp
python scripts\verify_cli.py --sdk 'D:\apps\DevEco Studio\sdk'
python scripts\verify_integration.py 'D:\apps\DevEco Studio\sdk'
.\scripts\verify_init_flow.ps1
.\scripts\verify_device.ps1 -Hdc 'D:\apps\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe'
```

宿主测试在 MSVC AddressSanitizer 下运行实际生成的 MoonBit C 代码和桥接回调，使用 Node-API 替身（async work 在真实线程执行）；设备脚本在模拟器上安装应用并读取 HiLog 标记。Windows CI 执行格式、严格检查、测试、接口一致性、CLI 构建、打包、代码量门槛和宿主 ASan；SDK、HAP 与模拟器检查在本机执行。各层证明范围见 [VALIDATION-0.4.md](docs/VALIDATION-0.4.md)。

## 许可

MoonOHOS 源码使用 Apache-2.0。分发动态库时保留两份 NOTICE，并补充业务库自身的许可证。第三方组件说明见 [THIRD_PARTY.md](THIRD_PARTY.md)。

参考：[MoonBit FFI](https://docs.moonbitlang.com/en/latest/language/ffi.html)、[HarmonyOS Node-API 开发流程](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/use-napi-process)。
