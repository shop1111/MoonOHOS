///|
test "vibrate validates duration and forwards usage" {
  @vibrator.vibrate(120, usage=Touch)
  let (duration, usage, before) = @vibrator.host_observations()
  assert_eq(duration, 120)
  assert_eq(usage, 5)
  @vibrator.cancel()
  let (_, _, after) = @vibrator.host_observations()
  assert_eq(after, before + 1)
  for bad in [0, -5, 60001] {
    let message = try {
      @vibrator.vibrate(bad)
      ""
    } catch {
      e => e.to_string()
    }
    assert_true(message.has_prefix("vibration duration"))
  }
}
