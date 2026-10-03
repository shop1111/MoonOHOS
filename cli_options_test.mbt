///|
test "CLI options retain defaults and constrain flags" {
  let options = @moonohos.parse_cli(["build", "--sdk", "中文 SDK", "--cache"])
  assert_eq(options.config, "moonohos.json")
  assert_eq(options.output, "_build/moonohos/dist")
  assert_true(options.cache)
  assert_eq(options.abis.length(), 2)
  for
    args in [
      ["build"],
      ["check", "--sdk", "x"],
      ["verify", "--config", "x"],
      ["build", "--sdk", "x", "--abi", "x86_64,x86_64"],
      ["inspect", "--json", "--json"],
      ["plan", "--abi"],
    ] {
    assert_true(
      (try @moonohos.parse_cli(args) catch {
        _ => None
      } noraise {
        _ => Some(())
      })
      is None,
    )
  }
  assert_true(@moonohos.parse_cli(["check", "--json"]).json)
  assert_eq(@moonohos.parse_cli([]).command, @moonohos.Help)
}

///|
test "diagnostics use stable text and JSON exit codes" {
  let diagnostic : @moonohos.Diagnostic = {
    stage: "interface",
    code: "signature",
    message: "mismatch",
    context: ["fn f"],
  }
  assert_true(diagnostic.render().contains("fn f"))
  assert_true(
    @moonohos.failure_report("check", diagnostic).stringify().contains("3"),
  )
  assert_true(
    @moonohos.failure_report("check", diagnostic, parameter=true)
    .stringify()
    .contains("2"),
  )
}
