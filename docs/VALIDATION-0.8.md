# MoonOHOS 0.8（开发中）验证记录：系统能力绑定

记录日期：2026-11-11。工具链：moonc `v0.10.20+65efd5b93`、HarmonyOS SDK API 26。设计和用法见 [BINDGEN.md](BINDGEN.md)，0.7 的记录见 [VALIDATION-0.7.md](VALIDATION-0.7.md)。

## 生成

`scripts/generate_bindings.py` 从 13 份清单生成 13 个包（`ohos/sys/*`）：绑定 117 个函数，跳过 31 个。每个包的 `BINDINGS.md` 列出了逐个函数的结果和跳过原因。跳过的主要是：

- 回调注册（`Register*Listener`）。
- `Create`/`Destroy` 句柄，以及指向指针的参数。
- 不透明结构体，以及可变参数函数（`OH_HiTrace_Tracepoint`）。
- 一个输出字节缓冲区（`OH_HiTrace_IdToBytes`）。

## 生成器自查时发现并修正的问题

逐个审查生成的签名时发现两处会在设备上出错的绑定，已经修改规则并加了测试：

| 函数 | 问题 | 修正 |
|---|---|---|
| `OH_HiTrace_IdToBytes(const HiTraceId*, uint8_t *pIdArray, int len)` | `uint8_t *` 被当成单个输出值，C 会按 `len` 向 1 字节的局部变量写入，造成栈溢出 | 非 const 的 8 位指针，以及后跟长度参数（len/size/count/num/capacity）的标量指针，都视为数组，不生成 |
| `OH_NativeDisplayManager_DestroyAvailableArea(NativeDisplayManager_Rect*)` | 被当成输入输出结构体，会把一个栈上的副本交给 SDK 释放 | Destroy/Release/Free/Delete 函数的结构体指针参数不生成 |

另外，函数名含 Get/Init/Query 时，非 const 结构体指针改为纯输出，例如 `get_system_mem_info() -> HiDebug_SystemMemInfo`；`QoS` 等混合大小写缩写不再被拆开（`set_thread_qos`）。

## 宿主

| 检查 | 结果 |
|---|---|
| 根模块测试（新增 `bindgen_test.mbt`：AST 读取、typedef 与匿名枚举、按形态绑定、跳过原因、C 桩、命名、清单校验） | 82 / 82 |
| `ohos` 模块 `moon check --deny-warn`（含 13 个生成包）与测试（新增 display、hitrace、deviceinfo 的宿主测试：801 → `SysError`、结构体往返、未知枚举值保留） | 通过，10 / 10 |
| `examples/search`（新增 `platform_report` 宿主测试） | 17 / 17 |

## 真实 SDK 编译与链接

`scripts/verify_bindings.py`：13 个包在 `arm64-v8a` 和 `x86_64` 下，桩函数对着 SDK 头文件以 `-Wall -Wextra -Werror` 编译通过，并以 `-Wl,--no-undefined` 链接到声明的系统库，没有未定义符号（`evidence/v0.8/bindings-sdk-compile.log`）。

检索示例导入 12 个生成包后，`moonohos build` 产出的 `libmoonsearch.so` 依赖这些系统库，CLI 的 ELF 校验通过，HAR/HAP 构建成功。

## 模拟器

检索示例新增 `platform_report()`（`examples/search/core/platform.mbt`），在 Pura 90 Pro 模拟器（x86_64，API 26）上调用 12 个包的 19 个函数。场景连续两轮通过（`MOONSEARCH_PLATFORM pass calls=19 checks=9`）。第一轮的输出：

```text
battery.capacity=100            battery.plugged=PLUGGED_TYPE_NONE
display.size=1256x2760          display.dpi=560   display.refresh=60   display.rotation=DISPLAY_MANAGER_ROTATION_0
deviceinfo.os=OpenHarmony-7.0.0.105   deviceinfo.model=emulator   deviceinfo.api=26
syscap.hitrace=true             syscap.fake=false
accesstoken.vibrate=false       （应用未申请 VIBRATE）
timeservice.zone=Asia/Shanghai
qos.roundtrip=set=-1,get=-1:QOS_BACKGROUND,reset=-1
hitrace.chain=valid=true,chain=761859378313203000
hidebug.memory=total_kb=4025332,available_kb=2695896
wifi.enabled=true               bluetooth.state=BLUETOOTH_STATE_OFF
osaccount.name=user
```

覆盖的形态：
- 返回值和枚举。
- 输出参数，包括带错误码的 `(Int, Int)` 元组。
- `const char *` 入参和返回值。
- `char *` 输出缓冲区：时区、账号名。
- 结构体返回：HiTraceId、内存信息。
- 结构体参数：`is_id_valid`。

QoS：`OH_QoS_SetThreadQoS`、`GetThreadQoS`、`ResetThreadQoS` 都返回 -1。同一时间的系统日志显示，系统服务自己设置 QoS 也失败（`QosManager: Failed to set thread QoS ... ret: -1`，`apply qos failed, errno = 4`），说明是这个模拟器内核不支持线程 QoS，不是绑定问题。探针接受"三个调用全部成功且读回的级别一致"或"全部返回 -1"两种结果；真机上应当是前者，尚未验证。

证据：`evidence/v0.8/search-device-run-1.log`、`search-device-run-2.log`、`search-page.jpeg`。

## 未验证

- ARM64 真机：只在 x86_64 模拟器运行；ARM64 只做了编译和链接。
- QoS 在支持它的内核上的成功路径。
- 需要权限的接口在授权后的行为：振动、Wi-Fi 详细信息等。
- 117 个绑定函数中只有 19 个在设备上调用过，其余只经过编译、链接和宿主测试。
