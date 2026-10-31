///|
/// Why the device vibrates; the system applies the matching user setting.
pub(all) enum Usage {
  Unknown
  Alarm
  Ring
  Notification
  Communication
  Touch
  Media
  PhysicalFeedback
  SimulatedReality
}

///|
fn Usage::code(self : Usage) -> Int32 {
  match self {
    Unknown => 0
    Alarm => 1
    Ring => 2
    Notification => 3
    Communication => 4
    Touch => 5
    Media => 6
    PhysicalFeedback => 7
    SimulatedReality => 8
  }
}

///|
pub(all) suberror VibratorError {
  InvalidDuration(Int32)
  /// NDK error code, e.g. 201 without `ohos.permission.VIBRATE`.
  Failed(Int32)
}

///|
pub impl Show for VibratorError with fn output(self, logger) {
  match self {
    InvalidDuration(ms) =>
      logger.write_string(
        "vibration duration must be 1..60000 ms: " + ms.to_string(),
      )
    Failed(code) =>
      logger.write_string(
        "vibrator failed with code " +
        code.to_string() +
        (if code == 201 { " (missing ohos.permission.VIBRATE)" } else { "" }),
      )
  }
}

///|
extern "C" fn play_raw(duration : Int32, usage : Int32) -> Int32 = "moonohos_vibrator_play"

///|
extern "C" fn cancel_raw() -> Int32 = "moonohos_vibrator_cancel"

///|
extern "C" fn host_last_raw(which : Int32) -> Int32 = "moonohos_vibrator_host_last"

///|
/// Vibrates for `duration_ms` milliseconds (1..60000).
pub fn vibrate(
  duration_ms : Int32,
  usage~ : Usage = Unknown,
) -> Unit raise VibratorError {
  if duration_ms < 1 || duration_ms > 60000 {
    raise InvalidDuration(duration_ms)
  }
  let code = play_raw(duration_ms, usage.code())
  if code != 0 {
    raise Failed(code)
  }
}

///|
/// Stops any vibration started by this app.
pub fn cancel() -> Unit raise VibratorError {
  let code = cancel_raw()
  if code != 0 {
    raise Failed(code)
  }
}

///|
/// Host builds only: (last duration, last usage code, cancel count).
pub fn host_observations() -> (Int32, Int32, Int32) {
  (host_last_raw(0), host_last_raw(1), host_last_raw(2))
}

///|
pub extend VibratorError with Show::{to_string, output}
