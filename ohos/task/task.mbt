///|
extern "C" fn cancelled_raw() -> Int = "moonohos_task_cancelled"

///|
extern "C" fn host_set_raw(value : Int) -> Unit = "moonohos_task_host_set"

///|
pub(all) suberror Cancelled

///|
pub impl Show for Cancelled with fn output(_, logger) {
  logger.write_string("task cancelled")
}

///|
/// True when the ArkTS caller cancelled the CancelToken of the running async
/// task. Synchronous calls are never cancelled. Poll it in long loops.
pub fn cancelled() -> Bool {
  cancelled_raw() != 0
}

///|
/// Raises `Cancelled` when the current task was cancelled.
pub fn check() -> Unit raise Cancelled {
  if cancelled() {
    raise Cancelled
  }
}

///|
/// Simulates cancellation in host tests; it has no effect inside a bridge.
pub fn host_set_cancelled(value : Bool) -> Unit {
  host_set_raw(if value { 1 } else { 0 })
}

///|
pub extend Cancelled with Show::{to_string, output}
