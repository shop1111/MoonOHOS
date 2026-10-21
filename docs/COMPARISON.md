# 与 napi-mbt、ohos-rs 的对照

检索日期：2026-10-21。以下内容来自公开文档与源码，未运行对方工具；无法确认的项目单独标注。

| 对象 | 版本 | 来源 |
|---|---|---|
| unmbt/napi-mbt | Mooncakes 发布版 0.1.1；源码提交 `76d9e65`（v0.2.1，2026-10-19） | [Mooncakes 0.1.1](https://mooncakes.io/docs/unmbt/napi-mbt@0.1.1)、[usage.md](https://github.com/unmbt/napi-mbt/blob/76d9e65b4cc19d8316f508dd1c8c1548ef4c874f/docs/en/usage.md)、[development.md](https://github.com/unmbt/napi-mbt/blob/76d9e65b4cc19d8316f508dd1c8c1548ef4c874f/docs/en/development.md) |
| ohos-rs | 分支 `ohos`，提交 `bd359d5`（2026-08-14） | [cargo-ohrs](https://github.com/ohos-rs/ohos-rs/tree/ohos/cli/cargo-ohrs)、[ohos-native-bindings](https://github.com/ohos-rs/ohos-native-bindings)、[生态说明源码](https://github.com/ohos-rs/websites) |

## 能力对照

| 能力 | napi-mbt（76d9e65） | ohos-rs | MoonOHOS 0.4 |
|---|---|---|---|
| 语言 | MoonBit | Rust | MoonBit（CLI 与平台包均为 MoonBit） |
| 目标宿主 | Node.js（Windows x64、Linux x64、macOS ARM64），不交叉编译 | HarmonyOS / OpenHarmony | HarmonyOS，SDK API 26，`arm64-v8a`/`x86_64` 交叉编译 |
| 导出分析与声明生成 | Tree-sitter 解析源码，生成 d.ts、加载器 | 宏生成 | 清单 + `.mbti` 核对，生成 d.ts |
| 类型 | Int/Double/Int64/UInt64/String/Bytes/Option/Array/结构体/枚举，类，回调 | 完整 napi-rs 类型系统 | Int/Double/Bool/String/Bytes/Array/结构体、不透明句柄、平台适配参数；**不支持** Option、Int64、枚举、类、回调 |
| 异步 | 修改后的 `moonbitlang/async` 事件循环；MoonBit 代码与引用计数**只在 JS 线程**运行，CPU 密集计算阻塞 JS 线程 | `Task`（libuv 工作线程 compute）、tokio | `napi_create_async_work`：MoonBit 在**工作线程**执行，进程门串行化 MoonBit 堆访问 |
| 取消 | AbortSignal，协作式 | AbortSignal（AsyncTask） | `CancelToken` + `@task.cancelled()`，协作式；执行前取消不进入 MoonBit |
| 实例资源 | 类实例 `dispose()`，GC 只回收 JS 包装 | `napi_wrap` + Drop | 句柄 `close()`；固定中关闭延迟释放；终结器与 env cleanup 兜底；诊断计数 |
| 环境清理 | 有，含异步运行时关闭顺序 | env cleanup hook 关闭 tokio | env cleanup hook 取消令牌、关闭句柄 |
| 平台能力 | 无 HarmonyOS API | 37 个绑定 crate（hilog、resource_manager、xcomponent 等） | `ohos` 模块：hilog、rawfile、task；受控 Native 依赖描述机制 |
| 依赖 C 的 MoonBit 库 | 支持（宿主编译器） | 不适用 | 需 `moonohos.native.json`，源码/库/ABI 校验后交叉编译 |
| 工程初始化 | `init` 生成 npm 风格 addon | `ohrs init --package` 生成 Cargo 工程与 HAR 模板 | `moonohos init` 生成 MoonBit 库、v2 清单、`moon.work` 与 Hvigor HAR 工程 |
| 分发 | npm 平台包 | `ohrs artifact` 打包 `.har`（tar） | `moonohos har` 填充 HAR 模块并调用 hvigor `assembleHar` |
| 产物校验 | 未见对应功能（未核实） | 未见 | SHA256 清单、ELF64 架构/段/依赖检查、v1/v2 清单兼容 |

## 重叠部分

函数与复杂类型的转换、d.ts 生成是 Node-API 绑定工具的共有能力。napi-mbt 在这部分覆盖更广（Int64、Option、枚举、类和回调）。MoonOHOS 把这部分作为底座维护，0.4 没有扩充类型种类，也没有复用 napi-mbt 的代码。

## MoonOHOS 的增量

1. **HarmonyOS 宿主运行时**：MoonBit 在 Node-API 工作线程执行，并处理取消、句柄生命周期和环境退出。napi-mbt 的设计是 MoonBit 只在 JS 线程运行，且只面向 Node.js。证据：[异步与线程模型](ASYNC-THREADING.md)。
2. **MoonBit 访问鸿蒙平台能力**：HiLog、RawFile 和任务取消可以直接在 MoonBit 中调用；第三方 MoonBit 包也能按描述文件携带 C 代码进入 OHOS 动态库。见 [Native 依赖扩展机制](NATIVE-EXTENSIONS.md)。
3. **鸿蒙工程分发**：`init → build → har` 生成可由独立 Stage 应用通过 `file:` 依赖安装的 HAR，不需要手工拼接 CMake、类型包或库目录。
4. **真实应用证据**：离线文档检索示例在模拟器上完成建索引、取消、重新进入和资源归零检查。

## 借鉴 ohos-rs 的部分

| ohos-rs 做法 | MoonOHOS 的对应实现 |
|---|---|
| `ohrs init --package` 同时生成语言工程与 HAR 模板（`oh-package.json5` main 为 Index.ets、`module.json5` type 为 har、Index.ets 默认导出原生模块） | `moonohos init` 采用相同的 HAR 结构，另外生成 Hvigor 工程外壳，以便直接 `assembleHar` |
| `ohrs build` 输出 `dist/<abi>/lib*.so` 与合并的 `index.d.ts` | 沿用 0.3 的 `libs/<abi>` + `types/` 分发包，增加 v2 清单 |
| `ohrs artifact` 把 dist 放入 `package/libs` 后打包 | `moonohos har` 把库、类型包、NOTICE 和来源记录放入 HAR 模块，由 hvigor 打包，生成的 HAR 带 ArkTS 编译产物 |
| resource_manager 绑定：`OH_ResourceManager_InitNativeResourceManager(env, resourceManager)`，Drop 时释放 | RawFile 适配器在 JS 线程获取、调用或任务结束后释放；MoonBit 侧只借用 |
| hilog 绑定：`OH_LOG_Print(LOG_APP, level, domain, tag, …)` | 同一接口；但消息作为 `%{public}s` 参数传入。ohos-hilog-binding 0.2.4 把消息当作格式串，含 `%` 的文本可能被误解析 |
| env cleanup hook 关闭运行时 | 每个环境的清理钩子取消令牌、关闭句柄 |

以上为设计借鉴，没有复制 ohos-rs 代码。MoonOHOS 的 CLI、代码生成器、C++ 生命周期运行时、平台包和示例均为本项目实现。

## 尚未核实

- napi-mbt v0.2.1 是否仍公开 0.1.1 文档中的底层 threadsafe function API。
- ohos-rs 各 crate 的许可证（仓库显示 NOASSERTION）。
- Mooncakes 检索按分页进行，可能遗漏其他相关包；在本次检索范围内未发现其他 MoonBit HarmonyOS Node-API 框架。
