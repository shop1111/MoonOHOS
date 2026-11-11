///|
/// Packs a color for RGBA 8888 buffers: the bytes in memory are r, g, b, a
/// (HarmonyOS devices are little-endian). Components are clamped to 0..255.
pub fn rgba(r : Int32, g : Int32, b : Int32, a~ : Int32 = 255) -> UInt32 {
  fn clamp(v : Int32) -> UInt32 {
    (if v < 0 { 0 } else if v > 255 { 255 } else { v }).reinterpret_as_uint()
  }

  (clamp(a) << 24) | (clamp(b) << 16) | (clamp(g) << 8) | clamp(r)
}

///|
/// The red, green, blue and alpha components of a packed color.
pub fn components(color : UInt32) -> (Int32, Int32, Int32, Int32) {
  (
    (color & 0xFFU).reinterpret_as_int(),
    ((color >> 8) & 0xFFU).reinterpret_as_int(),
    ((color >> 16) & 0xFFU).reinterpret_as_int(),
    (color >> 24).reinterpret_as_int(),
  )
}

///|
/// A MoonBit-side pixel buffer to draw into and hand to
/// `Surface::present_canvas`. Coordinates outside it are clipped.
pub struct Canvas {
  width : Int32
  height : Int32
  pixels : FixedArray[UInt32]
}

///|
pub fn Canvas::new(width : Int32, height : Int32) -> Canvas {
  let width = if width < 0 { 0 } else { width }
  let height = if height < 0 { 0 } else { height }
  { width, height, pixels: FixedArray::make(width * height, rgba(0, 0, 0)), }
}

///|
pub fn Canvas::width(self : Canvas) -> Int32 {
  self.width
}

///|
pub fn Canvas::height(self : Canvas) -> Int32 {
  self.height
}

///|
/// The pixel array, rows of `width` packed colors.
pub fn Canvas::pixels(self : Canvas) -> FixedArray[UInt32] {
  self.pixels
}

///|
pub fn Canvas::clear(self : Canvas, color : UInt32) -> Unit {
  self.pixels.fill(color)
}

///|
/// The color at (x, y), or `None` outside the canvas.
pub fn Canvas::get(self : Canvas, x : Int32, y : Int32) -> UInt32? {
  if x < 0 || y < 0 || x >= self.width || y >= self.height {
    None
  } else {
    Some(self.pixels[y * self.width + x])
  }
}

///|
pub fn Canvas::set(self : Canvas, x : Int32, y : Int32, color : UInt32) -> Unit {
  if x >= 0 && y >= 0 && x < self.width && y < self.height {
    self.pixels[y * self.width + x] = color
  }
}

///|
pub fn Canvas::fill_rect(
  self : Canvas,
  x : Int32,
  y : Int32,
  w : Int32,
  h : Int32,
  color : UInt32,
) -> Unit {
  let x0 = if x < 0 { 0 } else { x }
  let y0 = if y < 0 { 0 } else { y }
  let x1 = if x + w > self.width { self.width } else { x + w }
  let y1 = if y + h > self.height { self.height } else { y + h }
  for row in y0..<y1 {
    let base = row * self.width
    for col in x0..<x1 {
      self.pixels[base + col] = color
    }
  }
}

///|
/// Fills the disc of radius `r` centered at (cx, cy).
pub fn Canvas::fill_circle(
  self : Canvas,
  cx : Int32,
  cy : Int32,
  r : Int32,
  color : UInt32,
) -> Unit {
  guard r >= 0 else { return }
  let y0 = if cy - r < 0 { 0 } else { cy - r }
  let y1 = if cy + r >= self.height { self.height - 1 } else { cy + r }
  for row in y0..<=y1 {
    let dy = row - cy
    // Widest dx with dx^2 + dy^2 <= r^2.
    let mut dx = r
    while dx * dx + dy * dy > r * r {
      dx = dx - 1
    }
    self.fill_rect(cx - dx, row, 2 * dx + 1, 1, color)
  }
}
