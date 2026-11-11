///|
/// XComponent drawing (0.9): ArkTS hands over the surface id, MoonBit opens
/// the window, draws into a small canvas and presents one frame per VSync.
/// The compositor scales the buffer to the component's size.
priv struct Scene {
  surface : @surface.Surface
  vsync : @surface.VSync
  mut canvas : @surface.Canvas
  mut rows : FixedArray[UInt]
  touches : Array[(Int, Int)]
  mut running : Bool
  mut presented : Int
  mut first_ts : Int64
  mut last_ts : Int64
  mut buffer : String
  mut error : String
}

///|
let scenes : Array[Scene] = []

///|
let touch_total : Array[Int] = [0]

///|
fn Scene::draw(self : Scene, ts : Int64) -> Unit {
  let canvas = self.canvas
  let width = canvas.width()
  let height = canvas.height()
  for y in 0..<height {
    canvas.fill_rect(0, y, width, 1, self.rows[y])
  }
  // A ball bouncing across the canvas, 1.5 s per crossing.
  let radius = height / 6
  let span = width - 2 * radius
  let phase = (ts / 1_000_000L % 3000L).to_int()
  let travel = if phase < 1500 { phase } else { 3000 - phase }
  let x = radius + span * travel / 1500
  let bounce = if travel < 750 { travel } else { 1500 - travel }
  let y = height - radius - (height - 2 * radius) * bounce / 750
  canvas.fill_circle(x, y, radius, @surface.rgba(255, 196, 0))
  for touch in self.touches {
    canvas.fill_circle(
      touch.0,
      touch.1,
      radius / 2,
      @surface.rgba(64, 224, 128),
    )
  }
  // Frame counter: a bar that fills every 64 frames.
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
  self.draw(ts)
  try {
    let presented = self.surface.present_canvas(self.canvas)
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
/// animation. Replaces an earlier scene.
pub fn surface_attach(
  surface_id : String,
  width : Int,
  height : Int,
) -> String {
  ignore(surface_detach())
  try {
    let surface = @surface.Surface::open(surface_id, width~, height~)
    let vsync = @surface.VSync::open("moonsearch")
    let rows = gradient(height)
    let scene = {
      surface,
      vsync,
      canvas: @surface.Canvas::new(width, height),
      rows,
      touches: [],
      running: true,
      presented: 0,
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
/// becomes `width` x `height` and drawing starts over on a new canvas.
pub fn surface_resize(width : Int, height : Int) -> String {
  guard scenes.last() is Some(scene) else { return "attached=false" }
  guard width > 0 && height > 0 else { return "resize!empty" }
  try {
    scene.surface.resize(width, height)
    scene.canvas = @surface.Canvas::new(width, height)
    scene.rows = gradient(height)
    scene.touches.clear()
    "resized=" + width.to_string() + "x" + height.to_string()
  } catch {
    error => "resize!" + error.to_string()
  }
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
