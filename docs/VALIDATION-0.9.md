# MoonOHOS 0.9（开发中）验证记录：XComponent 图形

记录日期：2026-11-12。工具链：moonc `v0.10.20+65efd5b93`、HarmonyOS SDK API 26。设计和用法见 [XCOMPONENT.md](XCOMPONENT.md)，0.8 的记录见 [VALIDATION-0.8.md](VALIDATION-0.8.md)。

## 第一阶段：surface 包

新增手写平台包 `shop1111/moonohos_ohos/surface`：从 XComponent 的 surface id 打开 NativeWindow，CPU 绘制并提交，VSync 驱动帧回调，纯 MoonBit 的 `Canvas`。

| 检查 | 结果 |
|---|---|
| `ohos` 宿主测试（新增 5 个：surface id 解析和越界、宿主上打开返回 801、颜色字节顺序、画布裁剪、按 stride 复制） | 17 / 17 |
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

## 未验证

- ARM64 真机：只在 x86_64 模拟器运行；ARM64 只做了编译和链接。
- 帧率瓶颈（绘制、复制或缓冲区队列）没有分析；更大的缓冲区和真机上的帧率未测。
- Native Drawing、EGL/OpenGL ES 尚未接入。
