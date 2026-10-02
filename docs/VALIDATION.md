# 首版验证记录

验证日期：2026-10-03。以下为本机实际执行结果。

## 环境

Moon `0.1.20260920 (914d7da)`；moonc `v0.10.14+7d59c7ec9`；DevEco 内置 Native SDK API 26（组件 `26.0.0.105`）；SDK Clang 15；Windows x64。宿主 CLI 和 AddressSanitizer 检查使用 VS 2022 MSVC。模拟器为 Pura 90 Pro，连接地址 `127.0.0.1:5555`，实际运行架构 x86_64。

## 结果

| 检查 | 观察结果 | 证据 |
|---|---|---|
| MoonBit 生成器 | 7 项测试全部通过；格式、严格 Native 检查和接口生成通过 | `contract_test.mbt`、`pkg.generated.mbti` |
| 示例核心库 | 1 项测试通过；格式和严格 Native 检查通过 | `examples/core/core_test.mbt` |
| 手写最小桥接 | 两个 ABI 动态库编译通过 | `fixtures/manual/_build/` |
| 干净目录复现 | 9 项集成检查通过；中文及空格路径下从复制源码生成两个 ABI；原始源码未改写 | `_build/integration/run-ixb7ppbt/results.json` |
| CLI 错误输入 | 输出目录已存在、未知或重复 ABI、不支持类型、签名不匹配及 Native stub 均返回非零 | 集成检查日志 |
| ELF | ARM64 为 AArch64，x86_64 为 AMD X86-64；Node-API 注册符号存在 | `_build/moonohos/work-8/elf-*.log` |
| 宿主桥接 | 正常标量、负数、Int 边界、错误类型、缺失参数、小数、越界、NaN、Infinity、API 失败与注册失败通过；10000 次调用；ASan 未报告错误 | `_build/host-asan/result.log` |
| HAP | Hvigor 实际构建成功，包含两个 ABI 的 Native 库 | `examples/harmony/entry/build/default/outputs/default/entry-default-unsigned.hap` |
| x86_64 运行 | 真正加载 `.so`，页面显示 42；13 项检查和 1000 次重复调用通过；停止进程后重新启动两次通过 | `_build/validation/runtime.log`、`page.jpeg` |
| ARM64 运行 | 未执行真机运行 | 仅记录编译通过 |

最终 Native 接入包为 `_build/moonohos/dist/`。其 `manifest.json` 的 `runtime=not_run` 描述 CLI 的职责；设备验收记录单独保存，不能由编译结果推断运行通过。

两种动态库的 `DT_NEEDED` 均为 `libdeviceinfo_ndk.z.so`、`libace_napi.z.so`、`libc.so`。没有 Windows DLL 或 `libc++_shared.so` 依赖。分发文件检查未发现本机 SDK 的绝对路径。C++ 运行库采用静态链接；首次采用共享 C++ 运行库时，应用加载失败，改为静态链接后完成实际运行验收。

重启验证保存的成功日志包括不同进程：

```text
10-03 02:29:59.437 15375 15375 I A00000/MoonOHOS: MOONOHOS_RUNTIME_PASS add=42 scalar_checks=13 repeated_calls=1000
10-03 02:30:00.932 15466 15466 I A00000/MoonOHOS: MOONOHOS_RUNTIME_PASS add=42 scalar_checks=13 repeated_calls=1000
```

被安装并验证的未签名 HAP SHA256：

```text
6C154E1B039F00DA794F2B59F175491F58DD9E5D3C6BA6266EB912D7108266D9
```

设备日志会滚动，验证脚本比较最后一条成功日志的时间和进程信息，不能仅按累计行数判断新的运行结果。截图由设备 `snapshot_display` 命令直接采集。

## 复现及边界

按根目录 README 构建 CLI 和 Native 包，然后运行 `scripts/build_example.ps1`。`scripts/verify_integration.py` 在新的目录执行 CLI 构建，可复核无缓存的 Native 链路。设备已连接后运行 `scripts/verify_device.ps1`，独立复核安装、两次进程重启、日志及截图。

错误类型和缺失参数在宿主测试中通过实际生成的 callback 验证，未绕过 ArkTS 类型检查在设备上注入。宿主 Node-API 替身不构成鸿蒙加载器验证；设备上的成功日志与页面截图构成独立运行证据。未签名 HAP 在本机模拟器安装成功，不代表任意设备都接受未签名应用。

首版接口均为同步调用，采用同一动态库内的互斥锁和一次初始化。该行为不构成多线程 SDK 或多动态库共享 MoonBit 对象的支持承诺。没有验证旧版 SDK、ARM64 真机、OpenHarmony 产品兼容性或远程发布。
