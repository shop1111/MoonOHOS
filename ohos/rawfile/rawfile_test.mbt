///|
test "host manager reads, lists and validates resource paths" {
  let manager = @rawfile.host_manager("rawfile/testdata")
  assert_eq(@rawfile.read_text(manager, "hello.txt"), "MoonOHOS host fixture\n")
  assert_eq(@rawfile.read_text(manager, "docs/a.md"), "离线检索\n")
  assert_eq(@rawfile.list(manager, "docs"), ["a.md", "b.md"])
  assert_true(@rawfile.list(manager, "").contains("hello.txt"))
  for path in ["../moon.mod", "/etc/hosts", "docs//a.md", "missing.txt", ""] {
    let message = try {
      @rawfile.read(manager, path) |> ignore
      "read"
    } catch {
      e => e.to_string()
    }
    assert_true(
      message.has_prefix("invalid rawfile path") ||
      message.has_prefix("rawfile not found"),
    )
  }
}
