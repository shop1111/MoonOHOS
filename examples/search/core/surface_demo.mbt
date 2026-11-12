///|
/// XComponent drawing (0.9): ArkTS hands over the surface id, MoonBit opens
/// the window and draws one frame per VSync, with Native Drawing on a canvas
/// bound to the window buffer, or (`surface_mode(false)`) on a CPU pixel
/// array that is copied in. The compositor scales the buffer to the
/// component's size.
priv struct Scene {
  surface : @surface.Surface
  vsync : @surface.VSync
  mut canvas : @surface.Canvas
  mut rows : FixedArray[UInt]
  paints : Paints
  touches : Array[(Int, Int)]
  mut running : Bool
  mut native : Bool
  mut presented : Int
  mut drawing_frames : Int
  mut cpu_frames : Int
  mut first_ts : Int64
  mut last_ts : Int64
  mut buffer : String
  mut error : String
}

///|
/// Native Drawing objects reused across frames.
priv struct Paints {
  mut background : @drawing.OH_Drawing_Brush
  ball : @drawing.OH_Drawing_Brush
  touch : @drawing.OH_Drawing_Brush
  text : @drawing.OH_Drawing_Brush
  font : @drawing.OH_Drawing_Font
}

///|
let scenes : Array[Scene] = []

///|
let touch_total : Array[Int] = [0]

///|
fn[T] need(value : T?, what : String) -> T raise {
  match value {
    Some(value) => value
    None => fail(what + " returned NULL")
  }
}

///|
fn solid(color : UInt) -> @drawing.OH_Drawing_Brush raise {
  let brush = need(@drawing.brush_create(), "brush_create")
  @drawing.brush_set_anti_alias(brush, true)
  @drawing.brush_set_color(brush, color)
  brush
}

///|
/// A vertical linear gradient over `height` pixels. The shader takes color
/// and position arrays, generated from `const uint32_t *colors, const float
/// *pos, uint32_t size`.
fn gradient_brush(height : Int) -> @drawing.OH_Drawing_Brush raise {
  let brush = need(@drawing.brush_create(), "brush_create")
  let shader = need(
    @drawing.shader_effect_create_linear_gradient(
      need(@drawing.point_create(0, 0), "point_create"),
      need(@drawing.point_create(0, f(height)), "point_create"),
      [0xFF101840U, 0xFF1040A0U, 0xFF30A0C0U],
      [0, 0.6, 1],
      Clamp,
    ),
    "shader_effect_create_linear_gradient",
  )
  @drawing.brush_set_shader_effect(brush, shader)
  brush
}

///|
fn Paints::new(height : Int) -> Paints raise {
  let font = need(@drawing.font_create(), "font_create")
  @drawing.font_set_text_size(font, f(height / 7))
  {
    background: gradient_brush(height),
    ball: solid(0xFFFFC400U),
    touch: solid(0xFF40E080U),
    text: solid(0xFFFFFFFFU),
    font,
  }
}

///|
/// Position and radius of the ball, bouncing across the canvas (1.5 s per
/// crossing).
fn ball(width : Int, height : Int, ts : Int64) -> (Int, Int, Int) {
  let radius = height / 6
  let span = width - 2 * radius
  let phase = (ts / 1_000_000L % 3000L).to_int()
  let travel = if phase < 1500 { phase } else { 3000 - phase }
  let x = radius + span * travel / 1500
  let bounce = if travel < 750 { travel } else { 1500 - travel }
  let y = height - radius - (height - 2 * radius) * bounce / 750
  (x, y, radius)
}

///|
fn fill(
  canvas : @drawing.OH_Drawing_Canvas,
  brush : @drawing.OH_Drawing_Brush,
  draw : () -> Unit raise,
) -> Unit raise {
  @drawing.canvas_attach_brush(canvas, brush)
  draw()
  @drawing.canvas_detach_brush(canvas)
}

///|
/// One frame with Native Drawing, on the canvas bound to the window buffer.
fn Scene::draw_native(
  self : Scene,
  canvas : @drawing.OH_Drawing_Canvas,
  ts : Int64,
) -> Unit raise {
  let width = self.canvas.width()
  let height = self.canvas.height()
  let paints = self.paints
  fill(canvas, paints.background, () => {
    let all = need(
      @drawing.rect_create(0, 0, f(width), f(height)),
      "rect_create",
    )
    @drawing.canvas_draw_rect(canvas, all)
  })
  let (x, y, radius) = ball(width, height, ts)
  fill(canvas, paints.ball, () => {
    let center = need(
      @drawing.point_create(f(x), f(y)),
      "point_create",
    )
    @drawing.canvas_draw_circle(canvas, center, f(radius))
  })
  fill(canvas, paints.touch, () => {
    for touch in self.touches {
      let center = need(
        @drawing.point_create(f(touch.0), f(touch.1)),
        "point_create",
      )
      @drawing.canvas_draw_circle(canvas, center, f(radius / 2))
    }
  })
  fill(canvas, paints.text, () => {
    let label = "MoonBit · Native Drawing · " + self.presented.to_string()
    let blob = need(
      @drawing.text_blob_create_from_string(
        label,
        paints.font,
        TextEncodingUtf8,
      ),
      "text_blob_create_from_string",
    )
    @drawing.canvas_draw_text_blob(
      canvas,
      blob,
      f(height / 12),
      f(height / 5),
    )
    // Frame counter: a bar that fills every 64 frames.
    let bar = (self.presented % 64 + 1) * width / 64
    let rect = need(
      @drawing.rect_create(
        0,
        f(height - 4),
        f(bar),
        f(height),
      ),
      "rect_create",
    )
    @drawing.canvas_draw_rect(canvas, rect)
  })
}

///|
/// One frame on the CPU canvas, copied into the buffer by `present`.
fn Scene::draw_cpu(self : Scene, ts : Int64) -> Unit {
  let canvas = self.canvas
  let width = canvas.width()
  let height = canvas.height()
  for y in 0..<height {
    canvas.fill_rect(0, y, width, 1, self.rows[y])
  }
  let (x, y, radius) = ball(width, height, ts)
  canvas.fill_circle(x, y, radius, @surface.rgba(255, 196, 0))
  for touch in self.touches {
    canvas.fill_circle(
      touch.0,
      touch.1,
      radius / 2,
      @surface.rgba(64, 224, 128),
    )
  }
  let bar = (self.presented % 64 + 1) * width / 64
  canvas.fill_rect(0, height - 4, bar, 4, @surface.rgba(255, 255, 255))
}

///|
fn Scene::frame(self : Scene, ts : Int64) -> Unit {
  guard self.running && self.surface.is_open() else { return }
  if self.presented == 0 {
    self.first_ts = ts
  }
  self.last_ts = ts
  try {
    let presented = if self.native {
      let presented = self.surface.draw(canvas => {
        self.draw_native(canvas, ts)
      })
      self.drawing_frames += 1
      presented
    } else {
      self.draw_cpu(ts)
      let presented = self.surface.present_canvas(self.canvas)
      self.cpu_frames += 1
      presented
    }
    self.presented += 1
    self.buffer = presented.width.to_string() +
      "x" +
      presented.height.to_string() +
      ",stride=" +
      presented.stride.to_string()
    self.vsync.request_frame(t => self.frame(t))
  } catch {
    error => {
      self.error = error.to_string()
      self.running = false
    }
  }
}

///|
/// Opens the surface with a `width` x `height` buffer and starts the
/// animation (Native Drawing). Replaces an earlier scene.
pub fn surface_attach(
  surface_id : String,
  width : Int,
  height : Int,
) -> String {
  ignore(surface_detach())
  try {
    let surface = @surface.Surface::open(surface_id, width~, height~)
    let vsync = @surface.VSync::open("moonsearch")
    let scene = {
      surface,
      vsync,
      canvas: @surface.Canvas::new(width, height),
      rows: gradient(height),
      paints: Paints::new(height),
      touches: [],
      running: true,
      native: true,
      presented: 0,
      drawing_frames: 0,
      cpu_frames: 0,
      first_ts: 0L,
      last_ts: 0L,
      buffer: "",
      error: "",
    }
    scenes.push(scene)
    vsync.request_frame(t => scene.frame(t))
    "attached=" + width.to_string() + "x" + height.to_string()
  } catch {
    error => "attach!" + error.to_string()
  }
}

///|
fn gradient(height : Int) -> FixedArray[UInt] {
  FixedArray::makei(height, y => {
    @surface.rgba(16, 24 + 40 * y / height, 64 + 96 * y / height)
  })
}

///|
/// Follows a new component size (from `onSurfaceChanged`): the buffer
/// becomes `width` x `height` and drawing starts over.
pub fn surface_resize(width : Int, height : Int) -> String {
  guard scenes.last() is Some(scene) else { return "attached=false" }
  guard width > 0 && height > 0 else { return "resize!empty" }
  try {
    scene.surface.resize(width, height)
    scene.canvas = @surface.Canvas::new(width, height)
    scene.rows = gradient(height)
    scene.paints.background = gradient_brush(height)
    @drawing.font_set_text_size(scene.paints.font, f(height / 7))
    scene.touches.clear()
    "resized=" + width.to_string() + "x" + height.to_string()
  } catch {
    error => "resize!" + error.to_string()
  }
}

///|
/// Switches between Native Drawing (`true`) and the CPU canvas.
pub fn surface_mode(native : Bool) -> String {
  guard scenes.last() is Some(scene) else { return "attached=false" }
  scene.native = native
  "native=" + native.to_string()
}

///|
/// A touch at (`x`, `y`), each in 0..1 of the component's size.
pub fn surface_touch(x : Double, y : Double) -> Int {
  guard scenes.last() is Some(scene) else { return 0 }
  let width = scene.canvas.width()
  let height = scene.canvas.height()
  scene.touches.push(
    ((x * width.to_double()).to_int(), (y * height.to_double()).to_int()),
  )
  if scene.touches.length() > 8 {
    ignore(scene.touches.remove(0))
  }
  touch_total[0] = touch_total[0] + 1
  touch_total[0]
}

///|
/// `name=value` fields describing the running scene.
pub fn surface_report() -> String {
  guard scenes.last() is Some(scene) else { return "attached=false" }
  let elapsed_ms = (scene.last_ts - scene.first_ts) / 1_000_000L
  let fps = if elapsed_ms > 0L {
    (scene.presented - 1).to_int64() * 1000L / elapsed_ms
  } else {
    0L
  }
  let period = scene.vsync.period() catch { _ => -1L }
  "attached=true,running=" +
  scene.running.to_string() +
  ",buffer=" +
  scene.buffer +
  ",frames=" +
  scene.presented.to_string() +
  ",drawing_frames=" +
  scene.drawing_frames.to_string() +
  ",cpu_frames=" +
  scene.cpu_frames.to_string() +
  ",window_frames=" +
  scene.surface.frames().to_string() +
  ",vsync_requested=" +
  scene.vsync.requested().to_string() +
  ",vsync_delivered=" +
  @surface.delivered_frames().to_string() +
  ",fps=" +
  fps.to_string() +
  ",period_ns=" +
  period.to_string() +
  ",touches=" +
  touch_total[0].to_string() +
  ",error=" +
  scene.error
}

///|
/// Stops the animation and releases the window (from `onSurfaceDestroyed`
/// or when the page goes away). Returns the last report.
pub fn surface_detach() -> String {
  guard scenes.last() is Some(scene) else { return "attached=false" }
  let report = surface_report()
  scene.running = false
  scene.surface.close()
  scene.vsync.close()
  scenes.clear()
  report + ",closed=" + (!scene.surface.is_open()).to_string()
}

///|
fn f(value : Int) -> Float {
  Float::from_int(value)
}
