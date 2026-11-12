# MoonOHOS 0.9 验证记录：XComponent 图形

记录日期：2026-11-12。工具链：moonc `v0.10.20+65efd5b93`、HarmonyOS SDK API 26。设计和用法见 [XCOMPONENT.md](XCOMPONENT.md)，0.8 的记录见 [VALIDATION-0.8.md](VALIDATION-0.8.md)。0.9.0 于同日发布。

## 第一阶段：surface 包

新增手写平台包 `shop1111/moonohos_ohos/surface`：从 XComponent 的 surface id 打开 NativeWindow，CPU 绘制并提交，VSync 驱动帧回调，纯 MoonBit 的 `Canvas`。

| 检查 | 结果 |
|---|---|
| `ohos` 宿主测试（第一阶段新增 5 个：surface id 解析和越界、宿主上打开返回 801、颜色字节顺序、画布裁剪、按 stride 复制） | 17 / 17 |
| `verify_bindings.py`（默认检查范围加入 `ohos/surface`）：两个 ABI 以 `-Wall -Wextra -Werror` 编译桩函数，以 `--no-undefined` 链接 `libnative_window.so`、`libnative_vsync.so` | 通过 |
| `examples/search`（新增宿主测试：宿主上 `surface_attach` 返回 801、错误的 id、未打开时的触摸和报告） | 通过 |
| 检索示例 `moonohos build` + HAP 构建（两个系统库加入白名单） | 通过 |

## 模拟器

Pura 90 Pro 模拟器（x86_64，API 26）。检索页面顶部加了一个 XComponent。MoonBit 以组件三分之一的分辨率画渐变背景、弹跳的小球、触摸点和帧计数条，每个 VSync 提交一帧。验证脚本在 `MOONSEARCH_SURFACE_WAIT` 时点击组件中心并截图，3 秒后应用比较前后两次报告。两轮都通过：

```text
MOONSEARCH_SURFACE_ATTACH attached=360x200
MOONSEARCH_SURFACE_CHANGED 1144x420 resized=381x140
MOONSEARCH_SURFACE_CHANGED 2648x420 resized=883x140      （横屏）
MOONSEARCH_SURFACE_CHANGED 1144x420 resized=381x140      （竖屏）
MOONSEARCH_SURFACE_TOUCH count=1
MOONSEARCH_SURFACE pass frames=122 fps=40.7 buffer=381x140 touches=1      （第二轮：135 帧，45.0）
MOONSEARCH_SURFACE_CLOSED released=true ... frames=461,window_frames=461,vsync_requested=462,vsync_delivered=461,period_ns=16000000,error=,closed=true
```

- **画面**：截图（`evidence/v0.9/surface-page.jpeg`）中组件被 MoonBit 画的内容填满：渐变背景、黄色小球、点击位置的绿色圆点、底部的帧计数条。圆形没有变形，说明缓冲区尺寸随组件比例调整。
- **帧**：3 秒测量窗口内 40.7 / 45.0 帧/秒（刷新周期 16 ms）；每一帧都成功提交，`frames`、`window_frames` 和 VSync 送达次数一致，申请次数多 1（最后一次申请在关闭前尚未送达）。
- **触摸**：脚本用 `uinput` 点击后，ArkTS 的 `onTouch` 把归一化坐标传给 MoonBit，下一帧在该位置画出圆点。
- **生命周期**：页面离开时关闭窗口和 VSync（`closed=true`），随后的 `onSurfaceDestroyed` 得到 `attached=false`；第二次进入页面重新打开，没有残留。
- **与进程门的关系**：整轮的平均帧率只有 19–21（第一次进入）和 9–10（第二次进入），因为后台建大索引的 MoonBit 任务持有进程门，帧回调要等待。测量窗口内没有后台任务，帧率正常。见 XCOMPONENT.md 的“线程与进程门”。

已有的检索、取消、Worker、TaskPool、系统能力和回调场景同时通过（`SEARCH_DEVICE_PASS runs=2`）。

## 发现并修正

| 现象 | 原因 | 修正 |
|---|---|---|
| 第一次运行：旋转之后画面只占左上角，其余为黑色，缓冲区报告为 1144x420 | 组件尺寸变化时，ArkUI 把缓冲区尺寸重置为组件的像素尺寸 | `present` 在申请缓冲区前比较尺寸，不一致时重新设置 |
| 示例导出 `surface_resize` 后编译失败：`conflicting types for 'moonohos_surface_resize'` | 桥接把导出函数生成为 `moonohos_<名称>`，和 surface 包的 C 函数重名 | surface 包的符号改为 `moonohos_ohos_surface_*`；其他手写包的同类风险待在桥接层解决 |

证据：`evidence/v0.9/surface-device-run-1.log`、`surface-device-run-2.log`、`surface-page.jpeg`。

## 第二阶段：Native Drawing（2026-11-12）

`moonohos bindgen` 生成 `sys/drawing`：16 个 `native_drawing/` 头文件，绑定 322 个函数，跳过 17 个（无类型指针 `void *`、长度不明的常量数组、返回所有权不明的指针）。`surface` 包新增 `draw`，把画布直接绑定到窗口缓冲区。

| 检查 | 结果 |
|---|---|
| 生成器单元测试（新增：共享长度的常量数组输入、16 位元素不生成、与桩函数局部变量同名的参数） | 通过 |
| 重新生成全部 15 个包：只有 `sys/drawing` 是新的，`sys/hidebug` 的参数 `object` 改为 `object_`，其余不变 | 482 / 32 |
| `verify_bindings.py`：16 个包（含 drawing 和 surface）两个 ABI，`-Werror` 编译、`--no-undefined` 链接 | 通过 |
| `ohos` 宿主测试（新增：surface 构造的画布句柄在 drawing 包里有效，失效后 drawing 函数抛 `Closed`） | 通过 |
| 检索示例宿主测试、`moonohos build` + HAP 构建 | 通过 |

### 模拟器

检索示例改用 Native Drawing 绘制每一帧：三段线性渐变背景（生成的 `shader_effect_create_linear_gradient`，颜色和位置数组）、抗锯齿的小球和触摸点、白色文字“MoonBit · Native Drawing · 帧号”（字体 + 文字块）、帧计数条。测量窗口为 4 秒：前 3 秒用 Native Drawing（期间脚本点击并截图），最后 1 秒切到 CPU 路径，两条路径都要有帧。两轮都通过：

```text
MOONSEARCH_SURFACE pass frames=217 fps=54.3 drawing=155 cpu=62 buffer=381x140 touches=1      （第一轮）
MOONSEARCH_SURFACE pass frames=223 fps=55.8 drawing=163 cpu=60 buffer=381x140 touches=1      （第二轮）
```

截图（`evidence/v0.9/drawing-page.jpeg`）中可以看到文字、渐变（底部为青色，与 CPU 路径的纯蓝渐变不同）、小球和点击位置的圆点。整轮的结果和第一阶段一致：每帧都成功提交，页面离开时释放（`released=true`），后台建大索引时帧回调等待进程门。

第一次截图的时机太晚：脚本发现等待标记、点击、截图共用了 2 秒以上，截到的是切换后的 CPU 画面。把 Native Drawing 阶段延长到 3 秒、点击后的等待从 0.8 秒缩短到 0.3 秒后，截图落在 Native Drawing 阶段。

模拟器启动 15 秒后的第一次运行失败：页面在第一轮建完大索引后被关闭（`MOONSEARCH_PAGE_CLOSED round=1` 出现在内存探针中途），此前只画了 2 帧。随后连续两次、共四轮都通过。0.8 验证时也遇到过模拟器刚开机时的第一次运行异常；这次没有查到页面被关闭的原因，记为未解决。

证据：`evidence/v0.9/drawing-device-run-1.log`、`drawing-device-run-2.log`、`drawing-page.jpeg`。

## 第三阶段：OpenGL ES（2026-11-12）

`sys/gles` 由 `GLES3/gl3.h` 生成（135 个函数，跳过 92 个），手写的 `gl` 包负责 EGL 上下文和带指针的 GL 调用。

| 检查 | 结果 |
|---|---|
| 生成器单元测试（新增：长度参数之后的输出指针不生成、保留字 `ref` 加 `_`、清单的 `libraries` 字段） | 通过 |
| 重新生成全部 16 个包：已有包均无变化 | 617 / 124 |
| `verify_bindings.py`：18 个包（16 个生成包和 surface、gl）两个 ABI，`-Werror` 编译、`--no-undefined` 链接 `libEGL.so`、`libGLESv3.so` | 通过 |
| `ohos` 宿主测试（新增 `gl`：宿主上打开返回 801、错误 id、读像素和查询的结果长度、常量值） | 通过 |
| 检索示例宿主测试、`moonohos build` + HAP 构建 | 通过 |

审查生成结果时发现并修正的问题见 XCOMPONENT.md：`gen_buffers(n)` 等会越界写的绑定（改为不生成）、按 pname 返回多值的查询（排除）、GL 符号被解析到内部库 `libGLv4.so`（新增 `libraries`）、保留字参数 `ref`。

### 模拟器

检索页面新增第二个 XComponent，MoonBit 用 OpenGL ES 3 画一个按顶点着色、每 4 秒转一圈的三角形，着色器里按宽高比校正形状。每帧用 `glReadPixels` 读回中心像素：三角形的重心在原点，中心颜色应是红、绿、蓝三个顶点颜色的平均值（约 85/85/85），与背景色（16/24/64）明显不同。两个绘制区各有一个 VSync 接收器，回调都经进程门串行执行。

```text
MOONSEARCH_GL pass frames=230 fps=57.5 size=1144x315 center=85/85/85/255     （宽高比校正前，两轮）
MOONSEARCH_GL pass frames=155 fps=38.8 size=1144x315 center=85/86/85/255     （校正后第一轮）
MOONSEARCH_GL pass frames=171 fps=42.8 size=1144x315 center=85/85/84/255     （校正后第二轮）
MOONSEARCH_GL_CLOSED released=true ... frames=669,swapped=669,...,closed=true
```

- 读回的中心像素与理论值一致，说明三角形确实由 GL 画出，而不是只清了屏。
- 每帧都成功交换（`frames` 与 `swapped` 相等），没有 GL 错误；页面离开时销毁上下文和窗口。
- 同一时间 Native Drawing 区为 46–60 帧/秒。两次运行之间帧率差别较大（GL 39–58），波动未分析。
- 截图：`evidence/v0.9/gl-page.jpeg`。

模拟器启动 10 秒后的第一次运行，应用安装成功但没有启动（日志里只有桌面刷新图标的记录），重新运行后连续四轮通过。

证据：`evidence/v0.9/gl-device-run-1.log`、`gl-device-run-2.log`、`gl-page.jpeg`。

## 未验证

- ARM64 真机：只在 x86_64 模拟器运行；ARM64 只做了编译和链接。
- 帧率瓶颈（绘制、复制或缓冲区队列）没有分析；更大的缓冲区和真机上的帧率未测。
- 322 个 drawing 函数中在设备上调用过的约 20 个；135 个 gles 函数中 18 个，加上 `gl` 包的着色器、缓冲区、顶点属性和读像素。
- 纹理、帧缓冲、深度测试等 GL 功能未在设备上运行。
- 模拟器刚开机时第一次运行的两种异常（页面被提前关闭；应用未启动）的原因。
