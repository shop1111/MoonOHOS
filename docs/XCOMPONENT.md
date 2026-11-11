# XComponent 图形（0.9）

`shop1111/moonohos_ohos/surface` 让 MoonBit 在 ArkUI 的 XComponent 上绘制画面：ArkTS 把 XComponent 的 surface id 交给 MoonBit，MoonBit 打开对应的 NativeWindow，在 CPU 上画进自己的像素数组，每帧复制到窗口缓冲区并提交；帧节奏由 VSync 回调驱动，触摸事件从 ArkTS 转发过来。验证记录见 [VALIDATION-0.9.md](VALIDATION-0.9.md)。

## 为什么用 surface id

XComponent 有两种对接原生代码的方式：

| 方式 | 做法 | 取舍 |
|---|---|---|
| `libraryname` | 系统加载指定的 .so，在它的 Node-API 初始化里塞一个 `OH_NativeXComponent`，原生侧注册 surface 和触摸回调 | 和 MoonOHOS 桥接的模块注册流程耦合；一个 XComponent 只能对应一个库 |
| surface id（API 12+） | `XComponentController` 的 `onSurfaceCreated(surfaceId)` 把 id 交给任意原生函数，原生侧用 `OH_NativeWindow_CreateNativeWindowFromSurfaceId` 打开窗口 | 只多一个普通的导出函数，不改桥接；生命周期和触摸留在 ArkTS，容易看懂 |

MoonOHOS 采用后者：surface 包只依赖 `libnative_window.so` 和 `libnative_vsync.so`，不需要改动桥接或构建流程。

## 用法

MoonBit（核心模块导出这些函数）：

```moonbit
let surface = @surface.Surface::open(surface_id, width=360, height=200)
let vsync = @surface.VSync::open("demo")
let canvas = @surface.Canvas::new(360, 200)

fn frame(ts : Int64) -> Unit {
  canvas.clear(@surface.rgba(16, 24, 64))
  canvas.fill_circle(180, 100, 30, @surface.rgba(255, 196, 0))
  ignore(surface.present_canvas(canvas)) // 失败时抛 SurfaceError
  vsync.request_frame(frame) // 下一帧
}
```

ArkTS：

```ts
class MoonSurfaceController extends XComponentController {
  onSurfaceCreated(surfaceId: string): void { native.surface_attach(surfaceId, 360, 200); }
  onSurfaceChanged(surfaceId: string, rect: SurfaceRect): void {
    native.surface_resize(Math.round(rect.surfaceWidth / 3), Math.round(rect.surfaceHeight / 3));
  }
  onSurfaceDestroyed(surfaceId: string): void { native.surface_detach(); }
}

XComponent({ type: XComponentType.SURFACE, controller: this.controller })
  .onTouch((e: TouchEvent) => native.surface_touch(e.touches[0].x / width, e.touches[0].y / height))
```

完整示例：`examples/search/core/surface_demo.mbt` 和 `examples/search-app/.../SurfacePanel.ets`。

## API

| API | 说明 |
|---|---|
| `Surface::open(id, width?, height?)` | 解析十进制 surface id，打开窗口，设置 CPU 读写用途和 RGBA 8888 格式。给了尺寸时缓冲区固定为该尺寸，由合成器缩放到组件大小；不给时跟随组件的 surface 尺寸 |
| `Surface::present(pixels, width, height)` / `present_canvas(canvas)` | 申请缓冲区，等待释放 fence（最多 3 秒），映射内存，按 stride 逐行复制（超出部分裁掉），提交整块区域；返回缓冲区实际的宽、高、stride |
| `Surface::resize(w, h)`、`size()`、`frames()`、`close()`、`is_open()` | 关闭后再调用抛 `Closed`；未关闭就被回收时，终结器释放窗口 |
| `VSync::open(name)`、`request_frame(callback)`、`period()`、`close()` | `callback(timestamp_ns)` 只执行一次，在下一次刷新时于 VSync 线程上调用；要持续动画就在回调里再申请下一帧 |
| `Canvas` | 纯 MoonBit 的像素数组：`clear`、`set`/`get`、`fill_rect`、`fill_circle`，坐标越界自动裁剪。宿主上可测试 |
| `rgba(r, g, b, a?)`、`components(color)` | 颜色在内存中的字节顺序是 r、g、b、a（设备为小端） |
| `parse_surface_id`、`blit` | 供测试使用：id 解析、与 `present` 相同的按 stride 复制 |

错误：`SurfaceError::Failed(操作, 错误码)`（宿主上为 801）、`Closed(操作)`、`BadSurfaceId(文本)`。

## 线程与进程门

VSync 回调在系统的 VSync 线程上执行，先进入 MoonOHOS 的进程门（桥接导出的 `moonohos_gate_enter/leave`）再调用 MoonBit，所以回调里可以直接读写导出函数用到的全局状态，不用加锁。代价是：其他线程上的 MoonBit 代码（例如后台建索引的异步任务）持有进程门时，帧回调要等它释放。示例在建大索引的几秒里帧率从 40 多降到 10 左右，界面本身（ArkTS）不受影响。需要稳定帧率的应用，应把长时间的 MoonBit 计算拆成小段，或者在动画期间不运行它。

帧申请不会让 `VSync` 句柄保持存活：如果在回调里释放了最后一个引用，不会在 SDK 自己的回调中销毁 VSync 对象。已申请但尚未送达的帧，在 `close` 之后可能不再执行。

## 实现中发现的问题

- **组件尺寸变化会重置缓冲区尺寸。** 旋转屏幕后，ArkUI 把窗口的缓冲区尺寸改回组件的像素尺寸，固定尺寸的画面只画在左上角，其余为黑色。现在 `present` 在申请缓冲区前检查尺寸，不一致时重新设置。
- **导出函数的 C 符号会和平台包冲突。** 桥接把导出函数 `f` 生成为 C 符号 `moonohos_f`。示例导出 `surface_resize` 时，和 surface 包自己的 `moonohos_surface_resize` 重名，编译失败。surface 包的符号已改为 `moonohos_ohos_surface_*` / `moonohos_ohos_vsync_*`。`hilog`、`rawfile`、`task` 包的符号（如 `moonohos_rawfile_read`）仍有同样的风险，需要在桥接层统一解决。

## 后续

- **Native Drawing**：用 `moonohos bindgen` 生成 `sys/drawing`（画布、画笔、路径、文字都是 Create/Destroy 句柄），画布直接绑定到窗口缓冲区，替代逐像素绘制。
- **EGL / OpenGL ES**：在同一个 NativeWindow 上创建 EGL 表面，供需要 GPU 的应用使用。
- 帧率：模拟器上 381x140 的缓冲区约 40–45 帧/秒，还没有分析瓶颈在绘制、复制还是缓冲区队列；ARM64 真机未测。
