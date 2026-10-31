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
  assert_eq(@moonohos.parse_cli([]).command, Help)
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

///|
test "help names every command and per-command help lists options" {
  let usage = @moonohos.usage_text("9.9.9")
  for
    name in [
      "init", "build", "har", "doctor", "check", "inspect", "plan", "verify",
    ] {
    assert_true(usage.contains("\n  " + name + " "))
  }
  assert_true(usage.contains("MoonOHOS 9.9.9"))
  let build = @moonohos.parse_cli(["build", "--help"])
  assert_eq(build.command, Help)
  assert_eq(build.help_topic, Some(Build))
  let text = @moonohos.command_help(Build)
  for option in ["--sdk", "--abi", "--out", "--dry-run", "--cache"] {
    assert_true(text.contains(option))
  }
  assert_eq(@moonohos.parse_cli(["help", "har"]).help_topic, Some(Har))
  assert_eq(@moonohos.parse_cli(["--help"]).help_topic, None)
  // `build --help` needs no --sdk, unlike a real build.
  assert_eq(@moonohos.parse_cli(["init", "--help"]).help_topic, Some(Init))
}

///|
test "failure diagnostics derive a code and next-step hints" {
  let toolchain = @moonohos.failure_diagnostic(
    "build", "toolchain: requires moonc >= 0.10.16, found v0.10.14",
  )
  assert_eq(toolchain.code, "toolchain")
  assert_true(toolchain.context[0].contains("doctor"))
  let sdk = @moonohos.failure_diagnostic(
    "build", "toolchain: OHOS Native SDK not found",
  )
  assert_true(sdk.context[0].contains("--sdk"))
  let interface = @moonohos.failure_diagnostic(
    "build", "interface: missing public function add",
  )
  assert_eq(interface.code, "interface")
  assert_eq(interface.context.length(), 2)
  assert_eq(
    @moonohos.failure_diagnostic("build", "OSError(\"realpath\")").code,
    "io",
  )
  let plain = @moonohos.failure_diagnostic("build", "Something odd: happened")
  assert_eq(plain.code, "failed")
  assert_true(plain.context.is_empty())
  assert_true(
    @moonohos.failure_diagnostic("har", "har: module missing")
    .render()
    .contains("har [har]: har: module missing\n  check"),
  )
}

///|
test "package README describes async, errors and handles" {
  let readme = @moonohos.package_readme("demo")
  for
    needle in [
      "libdemo.so", "moonohos har", "CancelToken", "ERR_MOONOHOS_BUSINESS", "close()",
      "NOTICE.MoonBit.txt",
    ] {
    assert_true(readme.contains(needle))
  }
  assert_false(readme.contains("unsupported"))
}
