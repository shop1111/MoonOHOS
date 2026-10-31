///|
/// Network query failed with the NDK error code, e.g. 201 when the app lacks
/// `ohos.permission.GET_NETWORK_INFO`.
pub(all) suberror NetConnError {
  QueryFailed(Int32)
}

///|
pub impl Show for NetConnError with fn output(self, logger) {
  match self {
    QueryFailed(code) =>
      logger.write_string(
        "netconn query failed with code " +
        code.to_string() +
        (if code == 201 {
          " (missing ohos.permission.GET_NETWORK_INFO)"
        } else {
          ""
        }),
      )
  }
}

///|
#borrow(out)
extern "C" fn query_raw(which : Int32, out : FixedArray[Int32]) -> Int32 = "moonohos_netconn_query"

///|
extern "C" fn host_set_raw(has_default : Int32, metered : Int32, error : Int32) = "moonohos_netconn_host_set"

///|
fn query(which : Int32) -> Bool raise NetConnError {
  let out : FixedArray[Int32] = FixedArray::make(1, 0)
  let code = query_raw(which, out)
  if code != 0 {
    raise QueryFailed(code)
  }
  out[0] != 0
}

///|
/// Whether the device currently has a default (active) network.
pub fn has_default_network() -> Bool raise NetConnError {
  query(0)
}

///|
/// Whether the default network is metered (e.g. cellular). Large downloads
/// should usually wait for an unmetered network.
pub fn is_metered() -> Bool raise NetConnError {
  query(1)
}

///|
/// Host builds only: sets what the fallback reports. No effect on HarmonyOS.
pub fn set_host_state(
  has_default~ : Bool,
  metered~ : Bool,
  error~ : Int32 = 0,
) -> Unit {
  host_set_raw(
    if has_default {
      1
    } else {
      0
    },
    if metered {
      1
    } else {
      0
    },
    error,
  )
}

///|
pub extend NetConnError with Show::{to_string, output}
