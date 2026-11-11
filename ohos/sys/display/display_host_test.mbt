///|
/// On the host the generated stub does not call the SDK: error-code functions
/// report 801, which this SDK enum names DEVICE_NOT_SUPPORTED.
test "display error codes surface as SysError on the host" {
  let error = try {
    @display.get_default_display_width() |> ignore
    None
  } catch {
    Failed(function, name, code) => Some((function, name, code))
    Closed(_) => None
  }
  assert_eq(
    error,
    Some(
      (
        "OH_NativeDisplayManager_GetDefaultDisplayWidth", "DISPLAY_MANAGER_ERROR_DEVICE_NOT_SUPPORTED",
        801,
      ),
    ),
  )
  assert_false(@display.is_foldable())
}

///|
test "handles and listeners fail cleanly on the host" {
  // Creating a display handle reports 801 instead of returning a dead handle.
  let created = try {
    @display.create_primary_display() |> ignore
    0
  } catch {
    Failed(_, _, code) => code
    Closed(_) => -2
  }
  assert_eq(created, 801)
  // A failed registration releases its callback slot: more attempts than the
  // eight slots still reach the SDK call.
  for _ in 0..<20 {
    let code = try {
      @display.register_display_change_listener(_ => ()) |> ignore
      0
    } catch {
      Failed(_, _, code) => code
      Closed(_) => -2
    }
    assert_eq(code, 801)
  }
}
