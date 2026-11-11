///|
/// Errors of the surface package. `Failed` carries the operation and the
/// SDK error code (801 on the host, where no window can be opened).
pub(all) suberror SurfaceError {
  Failed(String, Int32)
  /// The surface or VSync handle was closed (or never opened).
  Closed(String)
  /// The surface id from ArkTS is not a decimal 64-bit number.
  BadSurfaceId(String)
}

///|
pub impl Show for SurfaceError with fn output(self, logger) {
  match self {
    Failed(what, code) =>
      logger.write_string(what + " failed with code " + code.to_string())
    Closed(what) => logger.write_string(what + ": handle is closed")
    BadSurfaceId(id) => logger.write_string("not a surface id: " + id)
  }
}

///|
pub extend SurfaceError with Show::{to_string, output}

///|
/// An XComponent surface opened as a NativeWindow for CPU drawing. Buffers
/// are RGBA 8888. The window is released by `close` or, failing that, when
/// MoonBit drops the last reference.
pub type Surface

///|
#borrow(code)
extern "C" fn surface_open_raw(
  id : UInt64,
  width : Int32,
  height : Int32,
  code : FixedArray[Int32],
) -> Surface = "moonohos_ohos_surface_open"

///|
#borrow(surface)
extern "C" fn surface_live_raw(surface : Surface) -> Int32 = "moonohos_ohos_surface_live"

///|
#borrow(surface)
extern "C" fn surface_frames_raw(surface : Surface) -> Int64 = "moonohos_ohos_surface_frames"

///|
#borrow(surface)
extern "C" fn surface_close_raw(surface : Surface) = "moonohos_ohos_surface_close"

///|
#borrow(surface)
extern "C" fn surface_resize_raw(
  surface : Surface,
  width : Int32,
  height : Int32,
) -> Int32 = "moonohos_ohos_surface_resize"

///|
#borrow(surface, size)
extern "C" fn surface_size_raw(
  surface : Surface,
  size : FixedArray[Int32],
) -> Int32 = "moonohos_ohos_surface_size"

///|
#borrow(surface, pixels, info)
extern "C" fn surface_present_raw(
  surface : Surface,
  pixels : FixedArray[UInt32],
  width : Int32,
  height : Int32,
  info : FixedArray[Int32],
) -> Int32 = "moonohos_ohos_surface_present"

///|
#borrow(dst, src)
extern "C" fn blit_raw(
  dst : FixedArray[UInt32],
  dst_stride : Int32,
  dst_width : Int32,
  dst_height : Int32,
  src : FixedArray[UInt32],
  width : Int32,
  height : Int32,
) = "moonohos_ohos_surface_blit_test"

///|
/// Parses the decimal surface id that ArkTS returns from
/// `XComponentController.getXComponentSurfaceId()` (or receives in
/// `onSurfaceCreated`).
pub fn parse_surface_id(text : String) -> UInt64 raise SurfaceError {
  if text.length() == 0 || text.length() > 20 {
    raise BadSurfaceId(text)
  }
  let mut value : UInt64 = 0
  for char in text {
    let digit = char.to_int() - '0'.to_int()
    if digit < 0 || digit > 9 {
      raise BadSurfaceId(text)
    }
    let next = value * 10UL + digit.to_uint64()
    // Wrapped around: more than 2^64 - 1.
    if next / 10UL != value {
      raise BadSurfaceId(text)
    }
    value = next
  }
  value
}

///|
/// Opens the surface with the given id. With `width` and `height` the
/// window hands out buffers of that size, which the compositor scales to
/// the component; otherwise buffers follow the XComponent's surface size.
pub fn Surface::open(
  surface_id : String,
  width~ : Int32 = 0,
  height~ : Int32 = 0,
) -> Surface raise SurfaceError {
  let id = parse_surface_id(surface_id)
  let code : FixedArray[Int32] = [0]
  let surface = surface_open_raw(id, width, height, code)
  if code[0] != 0 {
    raise Failed("OH_NativeWindow_CreateNativeWindowFromSurfaceId", code[0])
  }
  surface
}

///|
/// Whether the window is still open.
pub fn Surface::is_open(self : Surface) -> Bool {
  surface_live_raw(self) != 0
}

///|
/// Number of frames queued by `present` so far.
pub fn Surface::frames(self : Surface) -> Int64 {
  surface_frames_raw(self)
}

///|
/// Releases the window. Later calls raise `Closed`; closing twice is fine.
pub fn Surface::close(self : Surface) -> Unit {
  surface_close_raw(self)
}

///|
fn Surface::check(self : Surface, what : String) -> Unit raise SurfaceError {
  if !self.is_open() {
    raise Closed(what)
  }
}

///|
/// Sets the size of the buffers the window hands out. A size given here or
/// to `open` is re-applied before every `present`, because ArkUI resets it
/// to the component's size when the surface changes.
pub fn Surface::resize(
  self : Surface,
  width : Int32,
  height : Int32,
) -> Unit raise SurfaceError {
  self.check("resize")
  let code = surface_resize_raw(self, width, height)
  if code != 0 {
    raise Failed("SET_BUFFER_GEOMETRY", code)
  }
}

///|
/// Width and height of the buffers the window hands out.
pub fn Surface::size(self : Surface) -> (Int32, Int32) raise SurfaceError {
  self.check("size")
  let size : FixedArray[Int32] = [0, 0]
  let code = surface_size_raw(self, size)
  if code != 0 {
    raise Failed("GET_BUFFER_GEOMETRY", code)
  }
  (size[0], size[1])
}

///|
/// What `present` found in the buffer it filled.
#derive(Eq)
pub(all) struct Presented {
  width : Int32
  height : Int32
  /// Row length in pixels (at least `width`).
  stride : Int32
}

///|
pub extend Presented with Eq::{equal, not_equal}

///|
/// Copies `pixels` (rows of `width` RGBA 8888 pixels, see `rgba`) into the
/// next buffer of the window and queues it for display. Pixels outside the
/// buffer are clipped; buffer pixels outside `pixels` keep old contents.
pub fn Surface::present(
  self : Surface,
  pixels : FixedArray[UInt32],
  width : Int32,
  height : Int32,
) -> Presented raise SurfaceError {
  self.check("present")
  if width < 0 || height < 0 || width * height > pixels.length() {
    raise Failed("present: pixels shorter than width * height", -1)
  }
  let info : FixedArray[Int32] = [0, 0, 0]
  let code = surface_present_raw(self, pixels, width, height, info)
  if code != 0 {
    raise Failed("OH_NativeWindow_NativeWindowFlushBuffer", code)
  }
  { width: info[0], height: info[1], stride: info[2], }
}

///|
/// Presents a whole canvas.
pub fn Surface::present_canvas(
  self : Surface,
  canvas : Canvas,
) -> Presented raise SurfaceError {
  self.present(canvas.pixels, canvas.width, canvas.height)
}

///|
/// The copy `present` performs, on plain arrays: `src` (rows of `width`)
/// into `dst` (rows of `dst_stride`), clipped to `dst_width` x `dst_height`.
/// Exposed for tests.
pub fn blit(
  dst : FixedArray[UInt32],
  dst_stride : Int32,
  dst_width : Int32,
  dst_height : Int32,
  src : FixedArray[UInt32],
  width : Int32,
  height : Int32,
) -> Unit {
  let w = if width < dst_width { width } else { dst_width }
  let h = if height < dst_height { height } else { dst_height }
  guard w > 0 && h > 0 else { return }
  guard dst_stride >= w &&
    dst_stride * (h - 1) + w <= dst.length() &&
    width * h <= src.length() else {
    abort("blit: arrays shorter than the given geometry")
  }
  blit_raw(dst, dst_stride, dst_width, dst_height, src, width, height)
}
