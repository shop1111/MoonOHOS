# 与 napi-mbt、ohos-rs 的对照

检索日期：2026-11-10。以下内容来自公开文档与源码阅读，未构建或运行对方工具；需要在设备上确认的项目单独标注。

| 对象 | 版本 | 来源 |
|---|---|---|
| unmbt/napi-mbt | v0.3.7（Mooncakes），源码提交 `29f6590`（2026-10-31） | [仓库](https://github.com/unmbt/napi-mbt/tree/29f6590) |
| ohos-rs | 主仓库分支 `ohos` 提交 `bd359d5`（2026-08-14）；绑定仓库 `ohos-native-bindings` 提交 `7970b17`（2026-11-09） | [ohos-rs](https://github.com/ohos-rs/ohos-rs/tree/ohos)、[ohos-native-bindings](https://github.com/ohos-rs/ohos-native-bindings) |
| HarmonyOS SDK | API 26（DevEco Studio 26） | `native/sysroot/usr/include` 下的 Node-API 头文件 |

## 结论

- **napi-mbt 是面向 Node.js 的通用绑定工具**，胶水层覆盖面比 MoonOHOS 广：类、返回给 JS 的闭包、底层 JS 值操作、ArrayBuffer/TypedArray/零复制、迭代器、流、AbortSignal、带类型的线程安全函数，并按 Node-API 版本分级。
- **它的执行模型不适合鸿蒙 UI 应用**：MoonBit 代码只在 JS 线程上运行，后台计算要靠启动 Node 子进程；它也不做交叉编译，产物是 npm 包。这三点在鸿蒙上都用不了，详见下文。
- **MoonOHOS 的胶水层为移动端设计**：`"async": true` 的 MoonBit 代码在后台线程执行，界面线程不被占用；交叉编译出 `arm64-v8a`/`x86_64` 两个 ABI；产物是 HAR。
- **MoonOHOS 不在通用绑定的广度上与 napi-mbt 竞争。** 胶水层只补移动端需要的部分，并借鉴 napi-mbt 的成熟设计（见“借鉴计划”）。新的投入放在胶水层之上：系统能力、图形和工程集成。这三层是 ohos-rs 的主体，MoonBit 生态中还没有对应实现。

## napi-mbt 在鸿蒙上的可用性

逐项核对 napi-mbt `29f6590` 与 HarmonyOS SDK API 26：

| 项目 | 结果 | 依据 |
|---|---|---|
| Node-API 函数 | 基本兼容 | 它在 N-API 8 及以下调用的函数，鸿蒙头文件中都有声明（`js_native_api.h` 默认 `NAPI_VERSION 8`）。缺少 5 个 N-API 9/10 函数（`node_api_symbol_for`、`node_api_create_syntax_error`、`node_api_create_property_key_utf8`、`node_api_create_external_string_latin1`、`node_api_create_buffer_from_arraybuffer`），它本身按版本开关控制 |
| libuv | 头文件和库都有 | 鸿蒙 NDK 提供 `uv.h`、`libuv.so` 和 `napi_get_uv_event_loop`。它的异步运行时靠 libuv 定时器驱动，在鸿蒙 UI 线程上的行为需要在设备上确认 |
| 模块注册 | 需在设备上确认 | 它导出 `napi_register_module_v1`（`napi_glue.c:139`）；MoonOHOS 使用 `NAPI_MODULE`，在构造函数中调用 `napi_module_register`，这种写法已在模拟器上运行过 |
| 交叉编译 | 不支持 | 目标平台与本机不同时直接报错（`cmd/napi-mbt-cli/build.mbt:17-21`）；编译器靠探测本机的 MSVC/gcc/clang，产物校验只识别 Windows、Linux、macOS（`cmd/napi-mbt-cli/distribution.mbt`）|
| 分发 | 面向 npm | 生成 CJS/ESM 加载器、`engines.node` 和 npm 平台包（README、`docs/support.md`）。鸿蒙使用 `import x from 'libx.so'`、`types/` 声明包和 HAR |
| 后台执行 MoonBit | 不支持 | 见下一节 |
| 类型声明 | 部分不兼容 | 底层 API 生成 `unknown` 类型（`generator/types.mbt:115-119`）；ArkTS 不允许在 `.ets` 中使用 `any`/`unknown` |
| 工具链 | 版本锁定不同 | 锁定 moonc 0.10.17、`moonbitlang/async` 0.22.5（`docs/support.md`、`moon.mod`）；MoonOHOS 使用 moonc 0.10.20、async 0.21.0 |

### 执行模型：MoonBit 代码在哪个线程上运行

| 方式 | napi-mbt | 在鸿蒙上 |
|---|---|---|
| 内置异步（`moonbitlang/async`） | 在 JS 线程上调度；文档说明 CPU 密集的 MoonBit 代码仍会占住 JS 线程（`docs/async-adapter.md`） | JS 线程就是 UI 线程，计算期间界面卡顿 |
| 原生任务（`nativeTasks`） | 在 Node-API 工作线程执行，但只能运行 C 代码，不能接触 MoonBit 值和引用计数（`docs/native-tasks.md`） | 业务逻辑必须用 C 写 |
| 工作进程（`workerTasks`） | 启动 Node 子进程运行 MoonBit（`docs/workers.md`） | 鸿蒙应用中没有 Node 程序，也不能以这种方式启动子进程 |
| MoonOHOS `"async": true` | MoonBit 在 Node-API 工作线程执行，进程门保证同一时刻只有一个线程运行 MoonBit；支持取消、回调投递和环境销毁清理（[ASYNC-THREADING.md](ASYNC-THREADING.md)） | 设计目标就是这个场景 |

两者的线程安全原则相同：MoonBit 堆对象和引用计数在同一时刻只被一个线程访问，napi-mbt 用每个 addon 一把递归锁（`docs/classes-callbacks.md`），MoonOHOS 用可重入的进程门。区别在于 MoonOHOS 允许持锁的线程是后台线程，napi-mbt 只允许 JS 线程。

## 能力对照

| 层次 | 能力 | napi-mbt（29f6590） | ohos-rs | MoonOHOS 0.7 |
|---|---|---|---|---|
| 胶水层 | 目标宿主 | Node.js（Windows、Linux、macOS），只在本机编译 | HarmonyOS / OpenHarmony | HarmonyOS API 26，交叉编译 `arm64-v8a`/`x86_64` |
| | 接口来源 | Tree-sitter 解析 MoonBit 源码 | Rust 宏 | `moonohos.json` 清单，并与 `.mbti` 核对 |
| | 类型 | 标量、Int64/UInt64、String、Bytes、Option、数组、结构体、枚举、Map、JSON、TypedArray/ArrayBuffer/DataView、类、闭包、底层 JS 值 | 完整 napi-rs 类型系统 | 标量、Int64（bigint）、String、Bytes、数组、结构体、Option、无载荷枚举、带方法的句柄、平台适配参数、ArkTS 回调参数；0.7 增加 Float64Array/Float32Array/Int32Array/BigInt64Array |
| | 后台执行 | 见上节 | 工作线程 `Task`、tokio | 后台线程执行 MoonBit，`CancelToken` 取消 |
| | 回调 | 闭包、线程安全函数 | ThreadsafeFunction | 同步直接调用；异步经线程安全函数按序投递，全部送达后 Promise 才完成 |
| | 资源生命周期 | 类 `dispose()`、GC 兜底、环境清理 | `napi_wrap` + Drop、环境清理 | 句柄 `close()`、终结器兜底、环境清理、诊断计数 |
| 系统能力 | 鸿蒙 API | 无 | 40 个绑定包（另有 43 个底层 sys 包），包括 arkui、camera、drawing、sensor、xcomponent 等 | 6 个手写平台包，加上 0.8 由 `moonohos bindgen` 从 SDK 头文件生成的 14 个 `sys/*` 包（160 个函数，含句柄与回调） |
| | 依赖 C 的 MoonBit 库 | 支持（本机编译器） | 不适用 | `moonohos.native.json` 描述源码、库和 ABI，校验后交叉编译 |
| 图形 | XComponent / 绘图 | 无 | xcomponent、drawing、native_window 等 | `surface` 包（0.9）：NativeWindow、VSync、CPU 绘制；Native Drawing 与 GLES 待做 |
| 工程集成 | 初始化 | `init` 生成 npm 风格 addon | `ohrs init --package` 生成 Cargo 工程与 HAR 模板 | `moonohos init` 生成 MoonBit 模块、清单、HAR 工程和演示应用 |
| | 分发 | npm 平台包 | `ohrs artifact` 打包 HAR | `moonohos har` 调用 hvigor `assembleHar` |
| | 产物校验 | 构建记录与摘要、ELF 依赖检查 | 未见 | SHA256 清单、ELF 架构/段/依赖检查 |

## 借鉴计划

### 来自 napi-mbt（设计借鉴，MIT 协议）

| napi-mbt 的做法 | MoonOHOS 计划 | 状态 |
|---|---|---|
| 对象类型标记（`napi_type_tag_object`） | 句柄和 `CancelToken` 带本模块的标记，别的原生模块（含另一个 MoonOHOS 模块）的对象在读取指针前被拒绝 | 已完成，模拟器验证（系统 ResourceManager 冒充句柄被拒） |
| 外部内存上报（`napi_adjust_external_memory`） | HarmonyOS 不导出该接口，改用鸿蒙的 `napi_wrap_enhance`：清单为句柄声明 `"size"` 函数，创建时把字节数随包装一起告知 ArkTS 垃圾回收器 | 已完成（0.7） |
| 每个环境独立的实例数据（`napi_set_instance_data`） | 每个环境的状态作为回调数据绑定在导出函数上（不依赖实例数据是否按模块区分）；模块可在 Worker/TaskPool 中加载，诊断给出 `liveEnvs` | 已完成（0.7） |
| TypedArray 复制规则：严格校验类型，拒绝已分离和共享内存 | `FixedArray[Double/Float/Int/Int64]` ↔ `Float64Array/Float32Array/Int32Array/BigInt64Array`，整块复制 | 已完成（0.7） |

只借鉴设计，不复制代码；实现时在源码注释中注明出处。

### 来自 ohos-rs（已采用）

| ohos-rs 做法 | MoonOHOS 的对应实现 |
|---|---|
| `ohrs init --package` 同时生成语言工程与 HAR 模板 | `moonohos init` 采用相同的 HAR 结构，另外生成 Hvigor 工程外壳和演示应用 |
| `ohrs build` 输出 `dist/<abi>/lib*.so` 与合并的 `index.d.ts` | `libs/<abi>` + `types/` 分发包 |
| `ohrs artifact` 打包 HAR | `moonohos har` 把库、类型包、NOTICE 和来源记录放入 HAR 模块，由 hvigor 打包 |
| resource_manager 绑定在 Drop 时释放 | RawFile 适配器在 JS 线程获取，调用或任务结束后释放；MoonBit 侧只借用 |
| hilog 绑定使用 `OH_LOG_Print` | 同一接口；消息作为 `%{public}s` 参数传入，不当作格式串 |

### 来自 ohos-rs（计划借鉴）

| ohos-rs 做法 | MoonOHOS 计划 |
|---|---|
| `*-sys` 包由 SDK 头文件生成，上层包手写安全封装 | 头文件绑定生成器：解析 SDK 头文件，生成 MoonBit 声明和 C 中转代码，再手写安全封装 |
| xcomponent、drawing、native_window 包 | MoonBit 通过 XComponent 渲染 2D 图形并处理触摸 |

以上均为设计借鉴，没有复制对方代码。MoonOHOS 的 CLI、代码生成器、C++ 生命周期运行时、平台包和示例均为本项目实现。

## 尚未核实

- napi-mbt 的模块注册方式和 libuv 定时器在鸿蒙设备上的实际行为（未在设备上运行它）。
- ohos-rs 各包的许可证（仓库显示 NOASSERTION）。
- Mooncakes 搜索按分页进行，可能有遗漏；在本次检索范围内，未发现其他 MoonBit 的 HarmonyOS 框架。
