# MoonOHOS

MoonOHOS 将 MoonBit 核心逻辑编译为 HarmonyOS Native 模块。ArkTS 负责 UI 和系统交互，MoonBit 负责算法、计算和业务核心。

0.2 提供 MoonBit 实现的构建 CLI、标量及 String/Bytes 接口生成器和可打开的 Stage 示例应用。所有函数都是同步接口，耗时任务应等待后续异步支持。

首版验收记录保留在 [0.1 验证记录](docs/VALIDATION.md)，新类型的结果单独记录在 [0.2 验证记录](docs/VALIDATION-0.2.md)。ARM64 真机运行尚未验证。

## 验证环境

- Windows x64，Moon `0.1.20260920`，moonc `v0.10.14`。
- DevEco Studio 26，内置 HarmonyOS SDK API 26。
- 编译目标 `arm64-v8a`、`x86_64`；ARM64 真机和旧 SDK 兼容性分别验证。
- CLI 在 Windows 上由 Moon 自动选择 MSVC 构建，需要安装 C++ Build Tools；鸿蒙模块使用 SDK Clang/CMake/Ninja。

当前实现固定以上版本，版本检查不通过时停止，不自动升级工具链或修改全局开发环境。

## 快速开始

源码仓库：[shop1111/MoonOHOS](https://github.com/shop1111/MoonOHOS)。Mooncakes 模块为 `shop1111/moonohos@0.2.0`，使用上述固定工具链可安装 CLI：

```powershell
moon install shop1111/moonohos/cmd/moonohos@0.2.0
moonohos --version
```

CLI 本身通过 Native 后端构建。HarmonyOS SDK 仍需在本地安装，并通过 `--sdk` 提供。完整示例及验证脚本请从源码仓库获取。

在项目根目录执行 PowerShell：

```powershell
moon update
moon build --target native --release --deny-warn cmd/moonohos
$taskCli = '.\_build\native\release\build\cmd\moonohos\moonohos.exe'
& $taskCli build --sdk 'D:\apps\DevEco Studio\sdk'
.\scripts\build_example.ps1 -DevEco 'D:\apps\DevEco Studio'
```

`--sdk` 接受 DevEco 的 `sdk` 目录、OpenHarmony SDK 组件目录或 Native 目录；这里的 OpenHarmony 是 DevEco 内置组件名称，不代表已经验证独立 OpenHarmony 产品。

在 DevEco 打开 `examples/harmony`，运行 `EntryAbility`。页面显示 `42`、中文文本和 Uint8Array，并自动检查标量、引用类型和重复调用。日志标签是 `MoonOHOS`，成功标记是 `MOONOHOS_RUNTIME_PASS`。`scripts/build_example.ps1` 生成未签名 HAP；目标设备是否允许安装需按设备实际规则处理，脚本不设置签名。

## 接入已有 MoonBit 库

创建 `moonohos.json`：

```json
{
  "version": 1,
  "module": "./my-core",
  "package": "username/my-core",
  "nativeModule": "moonohos",
  "functions": [
    {
      "name": "add",
      "params": [{"name": "left", "type": "Int"}, {"name": "right", "type": "Int"}],
      "return": "Int"
    }
  ]
}
```

函数必须是所选包公开的普通函数，参数、顺序和返回类型必须与清单完全一致。`package` 必须属于 `module` 指向的模块；模块内子包也可选。

```powershell
& $taskCli build --config .\moonohos.json --sdk 'D:\apps\DevEco Studio\sdk' --abi x86_64 --out .\native-package
& $taskCli build --config .\moonohos.json --sdk 'D:\apps\DevEco Studio\sdk' --dry-run
```

路径均相对清单文件解析，包含 `--out` 和相对形式的 `--sdk`。默认构建两个 ABI，默认输出 `_build/moonohos/dist`。输出目录必须不存在；重复构建请使用新的目录或先自行清理旧产物。`--dry-run` 验证配置和工具链并打印步骤，不创建输出。

| MoonBit | C 适配边界 | ArkTS |
|---|---|---|
| `Int` | `int32_t` | `number`，有限整数，范围 −2147483648…2147483647 |
| `Double` | `double` | `number`，参数和返回值必须有限 |
| `Bool` | `int32_t` | `boolean` |
| `Unit` 返回值 | `void` | `void` |
| `String` | `moonbit_string_t`，内部固定版本 ABI | `string`，UTF-16 码元原样复制 |
| `Bytes` | `moonbit_bytes_t`，内部固定版本 ABI | `Uint8Array`，复制视图范围 |

缺少参数或类型错误抛出 `TypeError`，无效数值抛出 `RangeError`；额外参数与普通 JavaScript 调用一致，被忽略。Int 运算遵循 MoonBit 的 32 位回绕语义。Node-API 操作失败抛出 Error，已有 pending exception 保留。MoonBit panic 可能终止应用进程，不能当作可捕获的业务错误。

String 支持空串、中文、emoji、内嵌 NUL 和未配对代理码元，按明确长度转换，不经过 UTF-8。Bytes 只接受普通、未分离 ArrayBuffer 上的 Uint8Array，包括 `subarray()`；不接受 ArrayBuffer、DataView、Uint8ClampedArray、其他 TypedArray 或共享缓冲区。返回数组拥有独立内存，修改它不会改变输入。长度超过 `INT32_MAX` 或容量计算溢出抛出 RangeError，错误对象或分离缓冲区抛出 TypeError。

输入先复制到 C++ 缓冲区，再在锁内分配 MoonBit 对象；调用完成后复制结果并分别释放输入和返回值引用，解锁后创建 ArkTS 返回值。固定编译器导出函数借用参数、返回一个持有的引用；即便返回输入本体，也分别释放两份引用。C++ 分配异常转换为 Error；MoonBit panic 和运行时分配失败可能终止进程。C 头文件用于内部适配，不承诺跨 MoonBit 版本的引用类型 ABI。

不支持 Array/Struct、泛型、可选或标记参数、`raise`、回调、异步接口和额外 Native stub。也拒绝所选模块及其依赖内的 Native stub/pre-build hook。纯 MoonBit 依赖仍通过 Moon 正常解析；本地工作区依赖需要先改为可解析的模块依赖。支持 `moon.mod` 和旧 `moon.mod.json`，源目录必须在模块内部，不复制嵌套模块及符号链接。

清单仍为 version 1，函数参数及 return 使用 `"String"`、`"Bytes"`，可与标量类型任意组合。例如生成后：

```typescript
import native from 'libmoonohos.so';
const text: string = native.join_text('你好，', 'MoonBit 🌙');
const bytes: Uint8Array = native.echo_bytes(new Uint8Array([0, 127, 255]));
```

## 产物接入

```text
dist/
  libs/arm64-v8a/libmoonohos.so
  libs/x86_64/libmoonohos.so
  types/libmoonohos/index.d.ts
  types/libmoonohos/oh-package.json5
  cmake/MoonOHOS.cmake
  manifest.json
  README.md
  NOTICE.NativeSDK.txt
  NOTICE.MoonBit.txt
```

将 `libs/<abi>/*.so` 放入应用的 `entry/libs/<abi>/`，将类型包放入 `entry/src/main/cpp/types/`。在 `entry/oh-package.json5` 中声明：

```json
{"dependencies":{"libmoonohos.so":"file:./src/main/cpp/types/libmoonohos"}}
```

运行 `ohpm install`，在 ArkTS 中导入 `libmoonohos.so`。如果需要在自己的 CMake 中引用动态库，可包含 `cmake/MoonOHOS.cmake`；该导入本身不会将动态库打进 HAP。实际接入方式见示例工程。

编译器只生成 C，MoonOHOS 使用同版本的五个运行时源码和头文件重新交叉编译。C 适配层将编译器的 Unit 整数返回值规范为 void；Node-API 层串行初始化和调用。C++ 标准库静态链接，避免需要另行分发 `libc++_shared.so`。不执行生成程序的 `main`，不混入 Windows 运行时对象。

`manifest.json` 的 `moonohosVersion` 记录生成器版本；`runtime=not_run` 表示 CLI 没有执行鸿蒙应用。构建日志、编译命令和暂存源码保留于清单旁的 `_build/moonohos/work-*`，失败时可用于定位；分发包不包含 SDK 绝对路径。

分发动态库时保留两份 NOTICE，并补充业务库自身的许可证。MoonOHOS 源码使用 Apache-2.0；第三方组件说明见 [THIRD_PARTY.md](THIRD_PARTY.md)。

## 验证

```powershell
moon fmt
moon check --target native --deny-warn
moon test --target native --deny-warn
moon info --target native
python scripts\verify_manual.py 'D:\apps\DevEco Studio\sdk'
python scripts\verify_host.py
python scripts\verify_integration.py 'D:\apps\DevEco Studio\sdk'
.\scripts\verify_device.ps1 -Hdc 'D:\apps\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe'
```

手写 fixture 验证最初的 Int 链路。宿主测试用 MSVC AddressSanitizer 执行实际生成的 MoonBit C 代码和 Node-API callback，覆盖 UTF-16、字节视图、返回输入本体、错误类型、范围错误、逐项 API 失败、pending exception 及注册失败。测试专用 failpoint 模拟输入与结果缓冲区分配异常，运行时 malloc/free 计数核对 10000 轮调用后的存活分配增量为零；这些检测不修改分发库。宿主替身不验证 HarmonyOS 加载器。

集成检查验证中文、空格路径、干净双 ABI 构建、原始源码保持不变和错误配置，并额外构建引用类型与所有返回类型组合的 fixture，执行独立 ASan/分配计数测试。宿主日志位于 `_build/host-asan-v0.2/`。

设备验证脚本需要 PowerShell 7，要求模拟器已经连接，会安装当前示例 HAP、停止并启动示例进程两次，保存新成功日志、页面截图和 HAP SHA256。默认目标为 `127.0.0.1:5555`，可用 `-Target` 指定其他连接；每条 hdc 命令超时 45 秒即失败。证据默认写入 `_build/validation-v0.2/`，保留首版证据。它独立于构建 CLI。

下一阶段：Array/Struct → 异步和线程协议 → MoonBit 调用 HarmonyOS Native API 的 SDK。

参考：[MoonBit FFI](https://docs.moonbitlang.com/en/latest/language/ffi.html)、[HarmonyOS Node-API 开发流程](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/use-napi-process)。
