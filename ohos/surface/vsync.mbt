///|
/// A VSync receiver (`OH_NativeVSync`): `request_frame` runs a MoonBit
/// closure once, at the next display refresh, on the VSync thread. The
/// thread enters the MoonOHOS gate first, so the closure may touch the same
/// state as exported functions. Request the next frame from inside the
/// callback to keep an animation running.
pub type VSync

///|
#borrow(name, code)
extern "C" fn vsync_open_raw(
  name : Bytes,
  length : Int32,
  code : FixedArray[Int32],
) -> VSync = "moonohos_ohos_vsync_open"

///|
#borrow(vsync)
extern "C" fn vsync_live_raw(vsync : VSync) -> Int32 = "moonohos_ohos_vsync_live"

///|
#borrow(vsync)
extern "C" fn vsync_close_raw(vsync : VSync) = "moonohos_ohos_vsync_close"

///|
#borrow(vsync)
extern "C" fn vsync_requested_raw(vsync : VSync) -> Int64 = "moonohos_ohos_vsync_requested"

///|
extern "C" fn vsync_delivered_raw() -> Int64 = "moonohos_ohos_vsync_delivered"

///|
#borrow(vsync, period)
extern "C" fn vsync_period_raw(
  vsync : VSync,
  period : FixedArray[Int64],
) -> Int32 = "moonohos_ohos_vsync_period"

///|
#borrow(vsync, callback)
extern "C" fn vsync_request_raw(
  vsync : VSync,
  tramp : FuncRef[((Int64) -> Unit, Int64) -> Unit],
  callback : (Int64) -> Unit,
) -> Int32 = "moonohos_ohos_vsync_request"

///|
/// Creates a receiver; `name` identifies it in system traces.
pub fn VSync::open(name : String) -> VSync raise SurfaceError {
  let bytes = @utf8.encode(name + "\u{0}")
  let code : FixedArray[Int32] = [0]
  let vsync = vsync_open_raw(bytes, bytes.length() - 1, code)
  if code[0] != 0 {
    raise Failed("OH_NativeVSync_Create", code[0])
  }
  vsync
}

///|
pub fn VSync::is_open(self : VSync) -> Bool {
  vsync_live_raw(self) != 0
}

///|
/// Releases the receiver. A frame requested but not yet delivered may not
/// run any more.
pub fn VSync::close(self : VSync) -> Unit {
  vsync_close_raw(self)
}

///|
/// Frames requested through this receiver.
pub fn VSync::requested(self : VSync) -> Int64 {
  vsync_requested_raw(self)
}

///|
/// Frame callbacks run so far, all receivers together.
pub fn delivered_frames() -> Int64 {
  vsync_delivered_raw()
}

///|
/// Refresh period in nanoseconds. The SDK knows it only after the first
/// frame callback.
pub fn VSync::period(self : VSync) -> Int64 raise SurfaceError {
  if !self.is_open() {
    raise Closed("period")
  }
  let period : FixedArray[Int64] = [0L]
  let code = vsync_period_raw(self, period)
  if code != 0 {
    raise Failed("OH_NativeVSync_GetPeriod", code)
  }
  period[0]
}

///|
/// Runs `callback(timestamp_ns)` once at the next frame.
pub fn VSync::request_frame(
  self : VSync,
  callback : (Int64) -> Unit,
) -> Unit raise SurfaceError {
  if !self.is_open() {
    raise Closed("request_frame")
  }
  let code = vsync_request_raw(self, fn(f, t) { f(t) }, callback)
  if code != 0 {
    raise Failed("OH_NativeVSync_RequestFrame", code)
  }
}
