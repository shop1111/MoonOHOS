///|
test "environment facts distinguish absence from incompatible versions" {
  assert_true(
    @moonohos.environment_fact(
      "moon", "0.1.20260920 (hash)", "0.1.20260920", true,
    ).passed(),
  )
  assert_false(
    @moonohos.environment_fact("moon", "latest", "0.1.20260920", true).passed(),
  )
  assert_false(@moonohos.environment_fact("sdk", "", "", false).passed())
  assert_eq(@moonohos.runtime_files().length(), 6)
  assert_eq(@moonohos.sdk_candidates("中文 SDK").last(), Some("中文 SDK"))
}
