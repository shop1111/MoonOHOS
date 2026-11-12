# XComponent 图形（0.9）

`shop1111/moonohos_ohos/surface` 让 MoonBit 在 ArkUI 的 XComponent 上绘制画面：ArkTS 把 XComponent 的 surface id 交给 MoonBit，MoonBit 打开对应的 NativeWindow，每帧绘制并提交；帧节奏由 VSync 回调驱动，触摸事件从 ArkTS 转发过来。绘制有两条路径：

- **Native Drawing**：`surface.draw(canvas => ...)` 把生成的 `sys/drawing` 画布直接绑定到窗口缓冲区，用画刷、路径、文字、渐变等绘制，不复制像素。
- **CPU 像素数组**：在 MoonBit 的 `Canvas`（或任意 `FixedArray[UInt]`）里逐像素绘制，`present` 复制到缓冲区。验证记录见 [VALIDATION-0.9.md](VALIDATION-0.9.md)。

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
let brush = @drawing.brush_create().unwrap()
@drawing.brush_set_anti_alias(brush, true)
@drawing.brush_set_color(brush, 0xFFFFC400U) // ARGB

fn frame(ts : Int64) -> Unit {
  try {
    ignore(surface.draw(canvas => {
      @drawing.canvas_clear(canvas, 0xFF101840U)
      @drawing.canvas_attach_brush(canvas, brush)
      @drawing.canvas_draw_circle(canvas, @drawing.point_create(180, 100).unwrap(), 30)
      @drawing.canvas_detach_brush(canvas)
    }))
    vsync.request_frame(frame) // 下一帧
  } catch {
    error => println(error) // SurfaceError，或绘制函数的 SysError
  }
}
```

CPU 路径把 `surface.draw(...)` 换成在 `@surface.Canvas` 上绘制后 `surface.present_canvas(canvas)`。

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
| `Surface::draw(render)` | 申请缓冲区，以 RGBA 8888、预乘 alpha、缓冲区自身的 stride 创建位图和 Native Drawing 画布，调用 `render(canvas)` 后提交。画布只在 `render` 内有效，返回后再用抛 `@drawing.SysError::Closed`；`render` 抛出的错误在提交（可能只画了一部分的）帧之后重新抛出 |
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

## Native Drawing 的对接

`sys/drawing` 由 `moonohos bindgen` 从 16 个 `native_drawing/` 头文件生成（322 个函数，见 `ohos/sys/drawing/BINDINGS.md`）。画布、画刷、画笔、路径、字体、文字块、着色器都是句柄：由 Create 产生、配对 Destroy 的归 MoonBit 所有，回收时自动释放。

生成器不处理 `void *`，所以“画布画到窗口缓冲区”由 `surface` 包手写：`draw` 在 C 里用 `OH_Drawing_BitmapCreateFromPixels` 把映射后的缓冲区包成位图，创建画布并绑定，然后构造一个与生成包句柄布局相同的外部对象（载荷首字段是 SDK 指针）交给 MoonBit。`render` 返回后，句柄被置为失效，画布和位图随即销毁，缓冲区解除映射并提交。这依赖生成句柄的内存布局，`surface` 的宿主测试会检查：surface 构造的句柄在 drawing 包里是有效的，置为失效后 drawing 的函数抛 `Closed`。

为了生成渐变，0.9 给生成器加了一种形态：连续的 `const E *` 后跟长度参数（如 `const uint32_t *colors, const float *pos, uint32_t size`）生成为共享长度的 `FixedArray` 参数，见 [BINDGEN.md](BINDGEN.md)。

## OpenGL ES（`gl` 包）

`shop1111/moonohos_ohos/gl` 用同样的 surface id 创建 EGL 窗口表面和 OpenGL ES 3 上下文（RGBA 8888），缓冲区跟随组件尺寸：

```moonbit
let gl = @gl.GlSurface::open(surface_id)
let vsync = @surface.VSync::open("demo-gl")

fn frame(ts : Int64) -> Unit {
  try {
    ignore(gl.frame((w, h) => {
      @gles.clear_color(0.06, 0.09, 0.25, 1)
      @gles.clear(@gl.COLOR_BUFFER_BIT)
      // program、顶点数组见 examples/search/core/gl_demo.mbt
    }))
    vsync.request_frame(frame)
  } catch {
    error => println(error)
  }
}
```

- **上下文与线程**：`frame` 在调用线程上 `eglMakeCurrent`，把视口设为表面尺寸，调用 `render(width, height)`，`eglSwapBuffers`，再释放上下文。所以帧可以在 VSync 线程上渲染，ArkTS 线程上的导出函数也能调用 `frame`，不存在“上下文绑在哪个线程”的问题。GL 调用只能在 `render` 里进行。
- **GL 函数**：不带指针的 135 个函数由生成的 `sys/gles` 提供（`@gles.clear_color`、`@gles.draw_arrays`、`@gles.get_shaderiv` 等）。带指针的常用调用由 `gl` 包手写：`shader_source`、`compile_shader`、`link_program`（失败时带信息日志抛出）、`gen_buffer`/`gen_vertex_array`/`gen_texture`/`gen_framebuffer` 及对应的删除、`buffer_data_floats`、`vertex_attrib_pointer`（只支持缓冲区偏移，不支持客户端数组）、`uniform_matrix`、`read_pixels`、`get_integers`。头文件里的 `GL_*` 是宏，不在 AST 中，常用的列在 `gl` 包里（`@gl.TRIANGLES`、`@gl.FLOAT` 等）。
- **释放**：`close` 或回收时销毁上下文、EGL 表面和窗口；EGL display 不终止，因为同一进程的其他表面共用它。
- 同一个 XComponent 不能同时用 EGL 和 CPU/Native Drawing 两种方式提交；示例为 GL 单独放了一个组件。

## 实现中发现的问题

- **组件尺寸变化会重置缓冲区尺寸。** 旋转屏幕后，ArkUI 把窗口的缓冲区尺寸改回组件的像素尺寸，固定尺寸的画面只画在左上角，其余为黑色。现在 `present` 在申请缓冲区前检查尺寸，不一致时重新设置。
- **GL 头文件暴露了生成器的两个越界风险。** `glGenBuffers(GLsizei n, GLuint *buffers)` 被生成为 `gen_buffers(n) -> UInt`，n 大于 1 时会写出单值缓冲区；`glGetIntegerv(pname, GLint *)` 对 `GL_VIEWPORT` 写入 4 个值。生成器现在把长度参数之后的输出指针视为数组、不生成；按 pname 返回多个值的函数在清单中排除。同时发现 GL 符号由多个库导出，生成器选中了内部库 `libGLv4.so`，为此清单新增 `libraries` 字段。
- **保留字。** `glStencilFunc` 的参数 `ref` 是 moonc 的保留字，`--deny-warn` 下编译失败；生成器的关键字表补充了保留字。
- **生成的参数名会和桩函数的局部变量重名。** `OH_Drawing_BrushSetColor4f(brush, a, r, g, b, ...)` 的参数 `r` 与桩函数保存返回值的 `r` 冲突，`-Werror` 编译失败。生成器现在给这类参数加 `_`。
- **导出函数的 C 符号会和平台包冲突。** 桥接把导出函数 `f` 生成为 C 符号 `moonohos_f`。示例导出 `surface_resize` 时，和 surface 包自己的 `moonohos_surface_resize` 重名，编译失败。surface 包的符号已改为 `moonohos_ohos_surface_*` / `moonohos_ohos_vsync_*`。`hilog`、`rawfile`、`task` 包的符号（如 `moonohos_rawfile_read`）仍有同样的风险，需要在桥接层统一解决。

## 后续

- **文字排版**：`drawing_text_typography.h` 等段落排版接口尚未生成，目前只能用字体和文字块画单行文字。
- **纹理与图片**：`glTexImage2D` 等带像素指针的调用尚未提供，图片解码也未接入。
- 帧率：模拟器上 Native Drawing / CPU（381x140 缓冲区）和 GL（1144x315）在不同轮次分别为 40–60 帧/秒，波动未分析，可能与模拟器负载有关；更大的缓冲区和 ARM64 真机未测。
