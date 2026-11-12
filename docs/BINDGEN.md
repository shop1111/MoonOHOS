# 系统能力绑定生成（0.8）

`moonohos bindgen` 读取 HarmonyOS SDK 的 C 头文件，生成可以直接在 MoonBit 中调用的包。它和手写平台包（`hilog`、`rawfile` 等）使用同一套机制：MoonBit 声明 + C 桩函数 + `moonohos.native.json` 描述文件。`moonohos build` 会自动交叉编译桩函数，并链接描述文件里声明的系统库。

## 用法

```text
moonohos bindgen --spec ohos/sys/display/moonohos.bindgen.json --sdk "<DevEco Studio>/sdk" [--out <dir>] [--json]
```

清单示例：

```json
{
  "schema": "moonohos-bindgen-v1",
  "package": "shop1111/moonohos_ohos/sys/display",
  "name": "display",
  "headers": ["window_manager/oh_display_manager.h"],
  "prefixes": ["OH_NativeDisplayManager_"]
}
```

| 字段 | 含义 |
|---|---|
| `headers` | `sysroot/usr/include` 下的头文件，只绑定在这些文件里声明的函数（被它们间接包含的 `unistd.h` 等不算） |
| `prefixes` | 只绑定以这些前缀开头的函数；MoonBit 函数名去掉前缀后转为 snake_case（`GetDefaultDisplayWidth` → `get_default_display_width`） |
| `exclude` | 跳过的函数名 |
| `libraries` | 只在这些系统库中查找导出（0.9）。多个库导出同一批符号时需要指定，例如 GL 函数也由内部库 `libGLv4.so` 导出，`sys/gles` 指定 `libGLESv3.so` |
| `stringBuffer` | `char *` 输出和 `const char *` 结果使用的缓冲区大小（默认 256 字节，结果超出时截断） |

生成的文件：`<name>.mbt`、`<name>_stub.c`、`moon.pkg`、`moonohos.native.json`、`BINDINGS.md`（逐个列出已绑定和跳过的函数及原因）。不要手改这些文件，重新生成即可；同目录下自己写的测试文件不会被覆盖。

## 工作方式

1. 用 SDK 自带的 clang 解析头文件：`clang --target=x86_64-linux-ohos --sysroot=<SDK> -Xclang -ast-dump=json`。类型来自编译器，不靠自写的 C 解析器；typedef、匿名枚举、枚举常量的值（含 `1 << 3` 这类表达式）都以编译器计算的结果为准。
2. 扫描 SDK 中两个 ABI 的 `usr/lib/<triple>/*.so` 的动态符号表，确定每个函数由哪个系统库导出。两个 ABI 都导出、且库名相同才绑定，否则记为"not exported"。例如 `napi_adjust_external_memory` 虽然在头文件里，但库不导出，就会这样记录。
3. 按参数形态生成代码（见下表）。所有输出都写进 MoonBit 预先分配的 `FixedArray`/`Bytes`，C 桩函数不分配也不释放 MoonBit 对象。
4. 桩函数里，真实调用只在 `MOONOHOS_TARGET_OHOS` 下编译。宿主上的回退规则：普通函数返回 0 值；返回错误码的函数返回 801（不支持），MoonBit 侧会抛出 `SysError`。这样包可以在宿主上运行测试。

## 类型对应

| C | MoonBit |
|---|---|
| `int8/16/32_t`、`int`、`char`（标量） | `Int` |
| `uint32_t`、`unsigned` | `UInt` |
| `int64_t`、`long`（LP64） | `Int64` |
| `uint64_t`、`size_t`、`unsigned long` | `UInt64` |
| `float` / `double` / `bool` | `Float` / `Double` / `Bool` |
| 枚举 | 生成的枚举，带 `Other(Int)` 保存未命名的值，以及 `to_raw`、`from_raw`、`c_name` |
| 字段全为上述类型或 `char[N]`/`uint8_t[N]` 的结构体 | `pub(all) struct`，`char[N]` 对应 `String`（UTF-8），`uint8_t[N]` 对应 `Bytes` |

| C 参数或返回值 | 生成的 MoonBit |
|---|---|
| 值、枚举、结构体按值或 `const T *` | 普通参数 |
| `const char *` | `String` 参数 |
| `const uint8_t *` + 长度 | `Bytes` 参数，长度自动填入 |
| 连续的 `const E *`（E 为 32/64 位整数、`float`、`double`）后跟名称含 size/count/len 的整数 | 每个指针一个 `FixedArray[E]` 参数，长度取第一个数组，其余数组长度不同时 `abort`（0.9，如渐变的 `colors`、`pos`） |
| 非 const 标量指针 `T *` | 输出参数，变为返回值的一部分 |
| `char *` + 长度（按值，或长度本身是指针） | 输出 `String` |
| 非 const 结构体指针 | 函数名含 Get/Init/Query 时是纯输出，否则既是参数也是返回值（如 `set_chain_id(id, ..) -> HiTraceId`） |
| 返回名称含 Err/Result、且 0 表示成功的枚举 | 失败时抛出 `SysError::Failed(C 函数名, 常量名, 错误码)` |
| `const char *` 返回值 | `String`（复制，NULL 为空串） |

多个输出组成元组：`get_display_position(display_id) -> (Int, Int) raise SysError`。

## 句柄（0.8 第二阶段）

以下结构体会生成成句柄：以 `T **` 输出的、以 `T *` 返回的、作为回调参数的，以及没有平铺定义却通过指针使用的（不透明或含嵌套）。MoonBit 侧是 `pub type T`，底层是 MoonBit 外部对象，里面保存 SDK 指针。

- **所有权**：头文件里有一个只接收 `T *` 的 Destroy/Release/Free/Delete 函数时，由 Create/Acquire/Open/New 函数产生的句柄归 MoonBit 所有。可以显式调用销毁函数，比如 `destroy_display(d)`；仍未销毁就被垃圾回收时，终结器会调用同一个函数。其余句柄由 SDK 持有。
- **使用检查**：`T::is_live()` 可以查询句柄是否有效。以句柄为参数的函数会先检查，已销毁就抛 `SysError::Closed`，不会把已释放的指针交给 SDK。销毁函数成功后会把句柄置为失效。
- **字段读取**：结构体有完整定义时，为标量、枚举、`char[N]`、`uint8_t[N]` 字段生成读取方法，例如 `display.width()`、`display.name()`。
- **数组输出**：`E **data, <int> *length`（如传感器的 `GetData`）复制成 `FixedArray[E]`。
- **可空返回**：返回 `T *` 且没有错误码的函数，返回 `T?`；SDK 返回 NULL 时得到 `None`。

## 回调（0.8 第二阶段）

函数指针参数变为 MoonBit 闭包，例如 `register_display_change_listener(callback : (UInt64) -> Unit)`、`sensor_subscriber_set_callback(subscriber, callback : (Sensor_Event) -> Unit)`。

- **跳板函数**：鸿蒙的这类回调大多没有用户数据参数，所以每个回调位置生成 8 个 C 跳板函数，用跳板本身区分是哪一次注册。8 个都占用时，注册会抛 `SysError`。
- **闭包的生命周期**：闭包由 C 侧持有一份引用，下面两种情况会释放：
  - `RegisterX` 有对应的 `UnregisterX`：以返回的监听索引为键，注销成功后释放。
  - 回调设置在某个句柄上，比如传感器订阅者：句柄销毁或被回收时释放；重复设置会替换旧闭包。
  - 两种都不满足的回调不生成，因为没人能释放闭包。
- **线程**：回调可能在 SDK 线程上触发。跳板函数先进入 MoonOHOS 的进程门（桥接导出的 `moonohos_gate_enter/leave`），再调用 MoonBit。
- **回调参数**：
  - 标量和枚举照常转换。
  - `const char *` 复制成 `String`。
  - 结构体指针变成句柄，回调返回后自动失效，因为对象归 SDK 所有。
- **注意**：如果某个 SDK 的注销函数会等待正在执行的回调结束，在 MoonBit 里调用这个注销函数可能死锁，因为调用方持有进程门、回调线程在等进程门。模拟器上的显示和传感器接口没有出现这种情况。

## 不生成的形态（记入 BINDINGS.md）

- 可变参数函数；返回值不是 `void` 的回调；带嵌套函数指针的回调。
- 没有对应 Unregister、也不挂在句柄上的回调（闭包没人释放）。
- 指针数组（`T **` 后跟数量，如 `OH_Sensor_GetInfos`）、元素不是数值的输出数组。
- 非 const 的 8 位整数指针，以及后面紧跟长度参数的标量指针：它们是数组缓冲区，按单个值写入会越界。
- 前面有名称像长度的整数参数（`n`、`count`、`size` 等）的非 const 标量指针（0.9）：`glGenBuffers(GLsizei n, GLuint *buffers)` 会写入 n 个值，按单个值生成会越界。
- 输出个数取决于参数取值的函数无法从头文件判断，需要在清单的 `exclude` 中列出。`sys/gles` 排除了 `glGetIntegerv`、`glGetUniformfv` 等 19 个（如 `GL_VIEWPORT` 写入 4 个值），`gl` 包提供了按调用方给定个数读取的 `get_integers`。
- 来源不明的 `char *` 返回值，以及非句柄类型的指针返回值（不知道由谁释放）。
- `void *`（无类型指针，如 `OH_Drawing_BitmapCreateFromPixels` 的像素地址）。窗口缓冲区与画布的对接由 `surface` 包手写完成，见 [XCOMPONENT.md](XCOMPONENT.md)。

参数名与 MoonBit 关键字、保留字（如 `ref`，0.9 补充）或桩函数内部的局部变量（`r`、`object`）重名时，生成的参数名加 `_`（0.9 修正：`OH_Drawing_BrushSetColor4f` 的红色分量 `r` 曾导致编译失败）。

## 校验

- `scripts/verify_bindings.py <sdk>`：对每个 `ohos/sys/*` 包、两个 ABI，用 SDK 的 clang 对着真实头文件以 `-Wall -Wextra -Werror` 编译桩函数，再和按 `moonohos build` 方式编译的 MoonBit 运行时一起，以 `-Wl,--no-undefined` 链接声明的系统库。
- `scripts/generate_bindings.py <sdk>`：重新生成所有包并汇总绑定数量。
- `ohos` 模块的 `moon check --deny-warn` 和宿主测试（CI 中运行）。
- 检索示例的 `platform_report()`、`platform_handles()`、`platform_listen_start/stop()` 在模拟器上调用各包、句柄和回调（见 [VALIDATION-0.8.md](VALIDATION-0.8.md)）。

系统库必须在 `system_library_allowlist()` 中，`moonohos build` 才会链接。`bindgen --json` 的 `notAllowlisted` 字段列出不在白名单里的库。

## 模块

| 包 | 头文件 | 绑定 / 跳过 |
|---|---|---|
| `sys/accesstoken` | `accesstoken/ability_access_control.h` | 1 / 0 |
| `sys/battery` | `BasicServicesKit/ohbattery_info.h` | 2 / 0 |
| `sys/bluetooth` | `ConnectivityKit/bluetooth/oh_bluetooth.h` | 1 / 0 |
| `sys/deviceinfo` | `deviceinfo.h` | 27 / 0 |
| `sys/display` | `window_manager/oh_display_manager.h` | 35 / 0 |
| `sys/drawing`（0.9） | `native_drawing/` 下 16 个头文件：canvas、bitmap、brush、pen、path、rect、round_rect、point、color、matrix、font、typeface、text_blob、shader_effect、types、error_code | 322 / 17 |
| `sys/gles`（0.9） | `GLES3/gl3.h`（`libraries` 指定 `libGLESv3.so`，排除 19 个按 pname 返回多个值的查询函数） | 135 / 92 |
| `sys/hidebug` | `hidebug/hidebug.h` | 23 / 8 |
| `sys/hitrace` | `hitrace/trace.h` | 32 / 2 |
| `sys/osaccount` | `BasicServicesKit/os_account.h` | 2 / 0 |
| `sys/qos` | `qos/qos.h` | 6 / 1 |
| `sys/sensor` | `sensors/oh_sensor.h`、`sensors/oh_sensor_type.h` | 23 / 4 |
| `sys/syscap` | `syscap_ndk.h` | 1 / 0 |
| `sys/timeservice` | `BasicServicesKit/time_service.h` | 1 / 0 |
| `sys/vibrator` | `sensors/vibrator.h` | 3 / 0 |
| `sys/wifi` | `ConnectivityKit/wifi/oh_wifi.h` | 3 / 0 |
| 合计 16 个包 | | 617 / 124 |

第一阶段（不含句柄和回调）是 13 个包、117 / 31。
