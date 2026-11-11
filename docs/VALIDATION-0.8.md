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

## 第二阶段：句柄与回调（2026-11-11）

生成器新增句柄（外部对象、Destroy 配对、终结器、字段读取、`Closed` 检查）、数组输出和回调（8 个跳板函数、Register/Unregister 或所属句柄管理生命周期、SDK 线程进入进程门）。重新生成后 14 个包（新增 `sys/sensor`）绑定 160 个函数，跳过 15 个（第一阶段 117 / 31）；显示模块的 35 个函数全部绑定。

| 检查 | 结果 |
|---|---|
| 生成器单元测试（样例 AST 增加句柄创建/销毁、句柄参数、带句柄参数的 Register/Unregister 回调、数组输出、无人释放的回调） | 通过 |
| `verify_bindings.py`：14 个包、两个 ABI，`-Werror` 编译；连同 MoonBit 运行时以 `--no-undefined` 链接 | 通过（`evidence/v0.8/bindings-sdk-compile.log`） |
| `ohos` 宿主测试（新增：宿主上创建句柄返回 801 / `None`，反复失败的注册不会耗尽槽位） | 12 / 12 |
| 12 个 ASan 套件、`verify_cli.py`、`verify_integration.py` | 通过（桥接导出 `moonohos_gate_enter/leave`） |

原型先在宿主上确认两点：`type T` 声明的外部对象在最后一个引用释放时调用终结器；C 保存的闭包可以通过闭合 lambda 形式的 `FuncRef` 跳板之后再调用。

### 发现并修正：CLI 丢弃 `-all-pkgs`

检索示例在 MoonBit 代码里调用 `Float` 的方法，本地 `moon check` 通过，`moonohos build` 却报 `package moonbitlang/core/float is not imported`。原因：CLI 从 `moon build --dry-run` 的计划中取出 moonc 命令自己执行，一直把 `-all-pkgs <all_pkgs.json>` 当作可选的 IDE 元数据丢掉。moonc 0.10.20 要靠这张包表解析 prelude 别名背后的包，而 Moon 只在真正构建时才写这个文件。现在保留这个参数，CLI 和宿主测试用的 emit 程序在执行 moonc 前按 Moon 的格式写出这张表：core 的全部包，加上计划里每个包的 `.mi`。用户工程同样会遇到这个问题。

### 模拟器

检索示例新增 `platform_handles()` 和 `platform_listen_start/stop()`。应用在两者之间先切换横竖屏，再等待 3 秒；这期间验证脚本用模拟器命令把环境光设为 320、再设为 40。两轮都通过（`MOONSEARCH_CALLBACKS pass`）：

```text
handle.primary=id=0,name=UNKNOWN,size=1256x2760,alive=true,after_destroy=closed,live=false
handle.subscriber=created_and_dropped=50
listen.display=index=1
listen.light=set_type=0,interval=0,callback=0,subscribed=true
unlisten.display=ok
unlisten.light=destroyed=0
events.display=2        events.light=36
events.first=light:0:40|display:0|light:0:40|light:0:40      （第二轮）
```

- 句柄：通过生成的字段读取方法拿到主显示器信息；`destroy_display` 之后再读取抛 `Closed`，`is_live` 为 false。
- 终结器：50 个没有显式销毁的传感器订阅者，被回收时由终结器调用 `OH_Sensor_DestroySubscriber`，没有崩溃。设备上无法直接计数，宿主原型验证过终结器的调用次数。
- 显示变化监听：两次旋转各触发一次回调，回调在 SDK 线程上经进程门进入 MoonBit；注销成功后闭包释放。
- 环境光传感器：完整走了 创建订阅 ID / 属性 / 订阅者 → 设置回调 → 订阅 → 在回调里用 `sensor_event_get_data` 读取 `FixedArray[Float]` → 取消订阅 → 销毁 这一流程，3 秒收到约 36 个事件。第二轮读到了脚本设置的 40 lux；第一轮的值是 0，光照命令在那一轮可能没有及时生效。

第一次执行验证脚本时，应用在模拟器刚开机 20 秒后启动，只输出了第一个标记；随后手动启动和正式的两轮都正常。

证据：`evidence/v0.8/callbacks-device-run-1.log`、`callbacks-device-run-2.log`。

## 未验证

- ARM64 真机：只在 x86_64 模拟器运行；ARM64 只做了编译和链接。
- QoS 在支持它的内核上的成功路径。
- 需要权限的接口在授权后的行为：振动、Wi-Fi 详细信息等。
- 160 个绑定函数中约 35 个在设备上调用过（第一阶段 19 个，加上句柄、显示监听和传感器流程），其余只经过编译、链接和宿主测试。
- 回调在 ARM64 真机上的线程行为；SDK 注销函数如果会等待正在执行的回调，可能和进程门死锁（模拟器上没有出现）。
