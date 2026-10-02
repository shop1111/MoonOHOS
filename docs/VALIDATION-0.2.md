# MoonOHOS 0.2 验证记录

验证日期：2026-10-03。Moon `0.1.20260920 (914d7da)`、moonc `v0.10.14+7d59c7ec9`、DevEco Native SDK API 26（`26.0.0.105`）、Windows x64。设备为 Pura 90 Pro x86_64 模拟器。

## 实际结果

| 检查 | 结果 | 证据 |
|---|---|---|
| 生成器 | 8 项测试通过，格式、严格 Native 检查及接口生成通过 | `contract_test.mbt`、`pkg.generated.mbti` |
| 示例核心库 | 2 项测试通过，严格 Native 检查通过 | `examples/core/core_test.mbt` |
| 编译 | arm64-v8a、x86_64 均生成 ELF 动态库 | `_build/moonohos/work-11/` |
| ELF | 目标架构正确，含 Node-API 注册及 Sendable 查询符号；无 Windows DLL 或共享 C++ 运行库依赖 | `work-11/elf-*.log` |
| 宿主 ASan | 标量与引用桥接检查通过；10000 轮重复调用后存活分配增量为零 | `_build/host-asan-v0.2/result.log` |
| 类型组合 | String/Bytes 与 Int、Double、Bool、Unit、引用返回及无参数常量返回均执行通过；10000 轮无分配增量 | `_build/host-asan-v0.2/matrix_bridge/result.log` |
| 干净构建 | 中文和空格路径下 11 项集成检查通过，原始业务源码不变 | `_build/integration/run-8fr7lpn4/results.json` |
| HAP | Hvigor 构建成功，包含两个 ABI 的 `.so` | `examples/harmony/entry/build/default/outputs/default/entry-default-unsigned.hap` |
| x86_64 实际运行 | 页面显示 42、中文与 Uint8Array；13 项标量及 14 项引用检查通过；1000 轮调用和两次进程重启通过 | `_build/validation-v0.2/` |
| ARM64 真机 | 未运行，只有构建验证 | 不推断运行成功 |

两种 ELF 的动态依赖均为 `libdeviceinfo_ndk.z.so`、`libace_napi.z.so`、`libc.so`。接入包保持 SDK 路径无泄漏，manifest 清单版本仍为 v1，新增 `moonohosVersion: "0.2.0"`；CLI 的 `runtime=not_run` 与独立设备验收记录分别解释。

## 编码与内存证据

编译探针和真实生成代码确认：引用参数借用；返回输入本体时增加引用计数。宿主测试直接检查动态 String/Bytes 返回同一地址后引用计数为 2，释放返回引用后为 1，再释放输入引用；每个 callback 都核对运行时存活分配与调用前一致。

字符串覆盖空串、中文、emoji、内嵌 NUL、未配对的高低代理码元、拼接和 65536 码元文本。字节覆盖空数组、全部 256 个字节值、65536 字节数据、子数组偏移、拼接及输入/返回数组独立性。宿主检查额外覆盖 ArrayBuffer、DataView、其他 TypedArray、共享/Sendable 与分离缓冲区、超限长度及错误的后续参数。

测试对各 Node-API 操作逐项注入普通失败和 pending exception，包括返回值创建失败；用仅在宿主替身中启用的 failpoint 模拟 C++ 输入/结果缓冲区分配异常。运行时 C 单元的 malloc/free 在宿主编译时被计数，不改变分发库。ASan 检测越界和释放错误；分配计数补充其泄漏检查边界。上述错误注入不是鸿蒙设备上的异常注入结果。

## 设备记录

```text
10-03 03:08:16.431  6582  6582 I A00000/MoonOHOS: MOONOHOS_RUNTIME_PASS version=0.2.0 add=42 scalar_checks=13 reference_checks=14 repeated_calls=1000
10-03 03:08:19.422  6684  6684 I A00000/MoonOHOS: MOONOHOS_RUNTIME_PASS version=0.2.0 add=42 scalar_checks=13 reference_checks=14 repeated_calls=1000
```

验证脚本成功标记为 `DEVICE_RUNTIME_PASS restarts=2`。日志、每次重启记录和直接采集的 `page.jpeg` 位于 `_build/validation-v0.2/`。用于公开核对的 [运行日志](evidence/v0.2/runtime.log)、[设备截图](evidence/v0.2/page.jpeg) 和 [HAP 校验值](evidence/v0.2/hap-sha256.json) 随源码仓库保存。

已安装并验收的未签名 HAP SHA256：

```text
1B546AC4E729349CEAAC94EFE6E71DBE2EC8278D37520AF363BCBAF2340C1831
```

首次模拟器启动存在安装传输超时，恢复 HDC 连接并完成冷启动后安装成功。第一次即时日志采集未获取第二次启动的成功标记，但页面检查已经通过；现将成功标记延迟到启动日志流量平息后发出，重新安装同一最终版本并完成两次重启的独立记录。脚本每条 hdc 命令最多等待 45 秒，失败不会伪装为通过。

## 复现与保留

按 README 构建 CLI、Native 接入包和示例 HAP。运行 `verify_host.py` 检查主示例，运行 `verify_integration.py` 检查干净构建与类型组合，模拟器连接后运行 `verify_device.ps1`。

当前接入包位于 `_build/moonohos/dist/`。0.1 的 Native 包保留在 `_build/moonohos/dist-v0.1/`，首版 HAP、截图与日志保留在 `_build/validation/`，原验证文档未改写。

本记录不承诺旧 SDK、ARM64 真机、零复制、多线程或 OpenHarmony 产品兼容性。同步 MoonBit panic 和运行时分配失败仍可能终止应用进程。
