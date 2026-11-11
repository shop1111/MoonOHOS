///|
/// On the host the generated stub does not call the SDK: error-code functions
/// report 801, which this SDK enum names DEVICE_NOT_SUPPORTED.
test "display error codes surface as SysError on the host" {
  let error = try {
    @display.get_default_display_width() |> ignore
    None
  } catch {
    Failed(function, name, code) => Some((function, name, code))
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
