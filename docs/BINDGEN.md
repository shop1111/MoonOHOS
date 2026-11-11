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
| 非 const 标量指针 `T *` | 输出参数，变为返回值的一部分 |
| `char *` + 长度（按值，或长度本身是指针） | 输出 `String` |
| 非 const 结构体指针 | 函数名含 Get/Init/Query 时是纯输出，否则既是参数也是返回值（如 `set_chain_id(id, ..) -> HiTraceId`） |
| 返回名称含 Err/Result、且 0 表示成功的枚举 | 失败时抛出 `SysError::Failed(C 函数名, 常量名, 错误码)` |
| `const char *` 返回值 | `String`（复制，NULL 为空串） |

多个输出组成元组：`get_display_position(display_id) -> (Int, Int) raise SysError`。

## 不生成的形态（记入 BINDINGS.md）

- 回调（函数指针）、可变参数函数。
- 指向指针的参数、返回指针的函数，以及不透明结构体（`Create`/`Destroy` 这类句柄）。
- Destroy/Release/Free/Delete 函数的结构体指针参数：指针来自 SDK，传入副本会释放不属于 C 的内存。
- 非 const 的 8 位整数指针，以及后面紧跟长度参数的标量指针：它们是数组缓冲区，按单个值写入会越界。
- 来源不明的 `char *` 返回值（不知道由谁释放）。

前三类计划作为句柄和回调支持（与 0.6 的 ArkTS 回调、0.4 的句柄机制对接），后两类需要清单里补充语义说明。

## 校验

- `scripts/verify_bindings.py <sdk>`：对每个 `ohos/sys/*` 包、两个 ABI，用 SDK 的 clang 对着真实头文件以 `-Wall -Wextra -Werror` 编译桩函数，再以 `-Wl,--no-undefined` 链接声明的系统库。
- `scripts/generate_bindings.py <sdk>`：重新生成所有包并汇总绑定数量。
- `ohos` 模块的 `moon check --deny-warn` 和宿主测试（CI 中运行）。
- 检索示例的 `platform_report()` 在模拟器上调用各包（见 [VALIDATION-0.8.md](VALIDATION-0.8.md)）。

系统库必须在 `system_library_allowlist()` 中，`moonohos build` 才会链接。`bindgen --json` 的 `notAllowlisted` 字段列出不在白名单里的库。

## 首批模块

| 包 | 头文件 | 绑定 / 跳过 |
|---|---|---|
| `sys/accesstoken` | `accesstoken/ability_access_control.h` | 1 / 0 |
| `sys/battery` | `BasicServicesKit/ohbattery_info.h` | 2 / 0 |
| `sys/bluetooth` | `ConnectivityKit/bluetooth/oh_bluetooth.h` | 1 / 0 |
| `sys/deviceinfo` | `deviceinfo.h` | 27 / 0 |
| `sys/display` | `window_manager/oh_display_manager.h` | 21 / 14 |
| `sys/hidebug` | `hidebug/hidebug.h` | 18 / 13 |
| `sys/hitrace` | `hitrace/trace.h` | 31 / 3 |
| `sys/osaccount` | `BasicServicesKit/os_account.h` | 2 / 0 |
| `sys/qos` | `qos/qos.h` | 6 / 1 |
| `sys/syscap` | `syscap_ndk.h` | 1 / 0 |
| `sys/timeservice` | `BasicServicesKit/time_service.h` | 1 / 0 |
| `sys/vibrator` | `sensors/vibrator.h` | 3 / 0 |
| `sys/wifi` | `ConnectivityKit/wifi/oh_wifi.h` | 3 / 0 |
| 合计 13 个包 | | 117 / 31 |
