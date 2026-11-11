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

///|
/// Handles (0.8): create the primary display, read it through generated
/// getters, destroy it, then check that a destroyed handle refuses use.
pub fn platform_handles() -> Array[String] {
  [
    probe("handle.primary", () => {
      let display = @display.create_primary_display()
      let line = "id=" +
        display.id().to_string() +
        ",name=" +
        display.name() +
        ",size=" +
        display.width().to_string() +
        "x" +
        display.height().to_string() +
        ",alive=" +
        display.is_alive().to_string()
      @display.destroy_display(display)
      let after = try {
        display.width() |> ignore
        "usable"
      } catch {
        Closed(_) => "closed"
        Failed(_, name, _) => name
      }
      line + ",after_destroy=" + after + ",live=" + display.is_live().to_string()
    }),
    probe("handle.subscriber", () => {
      // Owned handles dropped without destroy are released by the finalizer.
      let mut made = 0
      for _ in 0..<50 {
        if @sensor.create_subscriber() is Some(_) {
          made += 1
        }
      }
      "created_and_dropped=" + made.to_string()
    }),
  ]
}

///|
/// Events delivered by callbacks; callbacks run on SDK threads inside the
/// MoonOHOS gate, so plain MoonBit state is safe here.
let platform_events : Array[String] = []

///|
let display_listeners : Array[UInt] = []

///|
let light_sensor : Array[
  (
    @sensor.Sensor_SubscriptionId,
    @sensor.Sensor_SubscriptionAttribute,
    @sensor.Sensor_Subscriber,
  ),
] = []

///|
/// Callbacks (0.8): a display-change listener and an ambient-light sensor
/// subscription, both delivering into MoonBit closures.
pub fn platform_listen_start() -> Array[String] {
  platform_events.clear()
  [
    probe("listen.display", () => {
      let index = @display.register_display_change_listener(id => {
        platform_events.push("display:" + id.to_string())
      })
      display_listeners.push(index)
      "index=" + index.to_string()
    }),
    probe("listen.light", () => {
      guard @sensor.create_subscription_id() is Some(id) else { "no id" }
      guard @sensor.create_subscription_attribute() is Some(attribute) else {
        "no attribute"
      }
      guard @sensor.create_subscriber() is Some(subscriber) else {
        "no subscriber"
      }
      let typed = @sensor.sensor_subscription_id_set_type(id, SensorTypeAmbientLight)
      let interval = @sensor.sensor_subscription_attribute_set_sampling_interval(
        attribute, 100000000L,
      )
      let callback = @sensor.sensor_subscriber_set_callback(subscriber, event => {
        let (code, data) = @sensor.sensor_event_get_data(event) catch {
          _ => (-1, [])
        }
        platform_events.push(
          "light:" +
          code.to_string() +
          ":" +
          (if data.length() > 0 { data[0].to_string() } else { "-" }),
        )
      })
      @sensor.subscribe(id, attribute, subscriber)
      light_sensor.push((id, attribute, subscriber))
      "set_type=" +
      typed.to_string() +
      ",interval=" +
      interval.to_string() +
      ",callback=" +
      callback.to_string() +
      ",subscribed=true"
    }),
  ]
}

///|
/// Unregisters and destroys what `platform_listen_start` created and
/// reports the events the callbacks collected.
pub fn platform_listen_stop() -> Array[String] {
  let report = []
  for index in display_listeners {
    report.push(
      probe("unlisten.display", () => {
        @display.unregister_display_change_listener(index)
        "ok"
      }),
    )
  }
  display_listeners.clear()
  for entry in light_sensor {
    let (id, attribute, subscriber) = entry
    report.push(
      probe("unlisten.light", () => {
        @sensor.unsubscribe(id, subscriber)
        let destroyed = @sensor.destroy_subscriber(subscriber) +
          @sensor.destroy_subscription_attribute(attribute) +
          @sensor.destroy_subscription_id(id)
        "destroyed=" + destroyed.to_string()
      }),
    )
  }
  light_sensor.clear()
  let display_events = platform_events.filter(e => e.has_prefix("display:"))
  let light_events = platform_events.filter(e => e.has_prefix("light:"))
  report.push("events.display=" + display_events.length().to_string())
  report.push("events.light=" + light_events.length().to_string())
  report.push(
    "events.first=" +
    platform_events[:platform_events.length().min(4)].to_owned().join("|"),
  )
  report
}
