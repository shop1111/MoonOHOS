///|
test "logger validates domain and tag" {
  let logger = @hilog.Logger::new(0x4d4f, "MoonOHOS")
  assert_eq(logger.domain, 0x4d4f)
  logger.info("100% safe: %s %d %{public}s are plain text")
  logger.debug("nul \u{0} is escaped")
  assert_true(logger.is_loggable(Info))
  for
    attempt in [
      () => @hilog.Logger::new(-1, "x"),
      () => @hilog.Logger::new(0x10000, "x"),
      () => @hilog.Logger::new(1, ""),
      () => @hilog.Logger::new(1, "a".repeat(32)),
    ] {
    let message = try {
      attempt() |> ignore
      "accepted"
    } catch {
      e => e.to_string()
    }
    assert_true(message.has_prefix("hilog "))
  }
}
