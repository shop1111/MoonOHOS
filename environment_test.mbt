///|
test "environment facts distinguish absence from incompatible versions" {
  assert_true(
    @moonohos.environment_fact(
      "moon", "0.1.20261028 (hash)", "0.1.20261028", true,
    ).passed(),
  )
  assert_false(
    @moonohos.environment_fact("moon", "latest", "0.1.20261028", true).passed(),
  )
  assert_false(@moonohos.environment_fact("sdk", "", "", false).passed())
  assert_eq(@moonohos.runtime_files().length(), 6)
  assert_eq(@moonohos.sdk_candidates("中文 SDK").last(), Some("中文 SDK"))
}

///|
test "version floors accept newer releases and reject older ones" {
  let floor = ">= " + @moonohos.minimum_moonc_version
  let fact = (actual : String) => {
    @moonohos.environment_fact("moonc", actual, floor, true).passed()
  }
  assert_false(fact("v0.10.14+7d59c7ec9 (2026-09-18)"))
  assert_false(fact("v0.10.15+0000000 (2026-10-01)"))
  assert_false(fact("v0.10.18+6c83a7f62 (2026-10-28)"))
  assert_true(fact("v0.10.20+65efd5b93 (2026-11-05)"))
  assert_true(fact("v0.11.0+1234567"))
  assert_true(fact("v1.0.0"))
  assert_false(fact("moonc: command not found"))
  assert_false(
    @moonohos.environment_fact("moonc", "v0.10.20", floor, false).passed(),
  )
}

///|
test "parse_version reads tool banners and bare API levels" {
  @debug.debug_inspect(
    @moonohos.parse_version("moonc v0.10.18+6c83a7f62 (2026-10-28)"),
    content="Some((0, 10, 18))",
  )
  @debug.debug_inspect(
    @moonohos.parse_version("moon 0.1.20261028 (e1e1f15 2026-10-28)"),
    content="Some((0, 1, 20261028))",
  )
  @debug.debug_inspect(
    @moonohos.parse_version("26"),
    content="Some((26, 0, 0))",
  )
  @debug.debug_inspect(
    @moonohos.parse_version("API 27 (beta)"),
    content="Some((27, 0, 0))",
  )
  @debug.debug_inspect(@moonohos.parse_version("no digits"), content="None")
  assert_true(@moonohos.version_at_least("27", "26"))
  assert_false(@moonohos.version_at_least("25", "26"))
}

///|
test "required environment floors the compiler and SDK, not the Moon CLI" {
  let required = Map::from_array(@moonohos.required_environment())
  assert_eq(required.get("moon"), Some(""))
  assert_eq(
    required.get("moonc"),
    Some(">= " + @moonohos.minimum_moonc_version),
  )
  assert_true(
    @moonohos.version_at_least(
      @moonohos.tested_environment()[1].1,
      @moonohos.minimum_moonc_version,
    ),
  )
}

///|
test "packages built by older supported compilers stay verifiable" {
  assert_true(@moonohos.package_moonc_supported("v0.10.18+6c83a7f62"))
  assert_true(@moonohos.package_moonc_supported("v0.10.16+abcdef0"))
  assert_false(@moonohos.package_moonc_supported("v0.10.14+7d59c7ec9"))
  assert_false(@moonohos.moonc_supported("v0.10.18+6c83a7f62"))
}

///|
test "tool banners drop feature-flag lines" {
  assert_eq(
    @moonohos.tool_banner(
      "moon 0.1.20261104 (940aa18 2026-11-04)\r\n\r\nFeature flags enabled: rr_moon_mod\r\n",
    ),
    "moon 0.1.20261104 (940aa18 2026-11-04)",
  )
  assert_eq(
    @moonohos.tool_banner("\nv0.10.20+65efd5b93 (2026-11-05)\n"),
    "v0.10.20+65efd5b93 (2026-11-05)",
  )
  assert_eq(@moonohos.tool_banner(""), "")
}
