///|
/// Calls into generated system bindings (`shop1111/moonohos_ohos/sys/*`, 0.8)
/// and reports one `name=value` (or `name!error`) line per call. The app logs
/// the lines on the device; calls needing permissions the app does not hold
/// report their error code instead.
fn probe(name : String, run : () -> String raise) -> String {
  try {
    name + "=" + run()
  } catch {
    error => name + "!" + error.to_string()
  }
}

///|
pub fn platform_report() -> Array[String] {
  let report = [
    probe("battery.capacity", () => @battery.get_capacity().to_string()),
    probe("battery.plugged", () => @battery.get_plugged_type().c_name()),
    probe("display.size", () => {
      let width = @display.get_default_display_width()
      let height = @display.get_default_display_height()
      width.to_string() + "x" + height.to_string()
    }),
    probe("display.dpi", () => @display.get_default_display_density_dpi().to_string()),
    probe("display.refresh", () => {
      @display.get_default_display_refresh_rate().to_string()
    }),
    probe("display.rotation", () => {
      @display.get_default_display_rotation().c_name()
    }),
    probe("deviceinfo.os", () => @deviceinfo.get_os_full_name()),
    probe("deviceinfo.model", () => @deviceinfo.get_product_model()),
    probe("deviceinfo.api", () => @deviceinfo.get_sdk_api_version().to_string()),
    probe("syscap.hitrace", () => {
      @syscap.can_i_use("SystemCapability.HiviewDFX.HiTrace").to_string()
    }),
    probe("syscap.fake", () => {
      @syscap.can_i_use("SystemCapability.MoonOHOS.NotAThing").to_string()
    }),
    probe("accesstoken.vibrate", () => {
      @accesstoken.check_self_permission("ohos.permission.VIBRATE").to_string()
    }),
    probe("timeservice.zone", () => @timeservice.get_time_zone()),
    probe("qos.roundtrip", () => {
      let set = @qos.set_thread_qos(QosUserInitiated)
      let (code, level) = @qos.get_thread_qos()
      let reset = @qos.reset_thread_qos()
      "set=" +
      set.to_string() +
      ",get=" +
      code.to_string() +
      ":" +
      level.c_name() +
      ",reset=" +
      reset.to_string()
    }),
    probe("hitrace.chain", () => {
      let id = @hitrace.begin_chain("moonsearch", 0)
      let valid = @hitrace.is_id_valid(id)
      @hitrace.start_trace("moonsearch.platform")
      @hitrace.finish_trace()
      @hitrace.end_chain()
      "valid=" + valid.to_string() + ",chain=" + id.chain_id.to_string()
    }),
    probe("hidebug.memory", () => {
      let memory = @hidebug.get_system_mem_info()
      "total_kb=" +
      memory.total_mem.to_string() +
      ",available_kb=" +
      memory.available_mem.to_string()
    }),
    probe("wifi.enabled", () => @wifi.is_wifi_enabled().to_string()),
    probe("bluetooth.state", () => {
      @bluetooth.get_bluetooth_switch_state().c_name()
    }),
    probe("osaccount.name", () => @osaccount.get_name()),
  ]
  report
}
