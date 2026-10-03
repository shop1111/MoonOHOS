///|
test "package paths and checksums reject traversal and corruption" {
  for path in ["../x", "/x", "C:/sdk", "a\\x", "a//b", "a/./b"] {
    assert_true(
      (try @moonohos.validate_package_path(path) catch {
        _ => false
      } noraise {
        _ => true
      }) ==
      false,
    )
  }
  let file = @moonohos.package_file("libs/x86_64/libdemo.so", b"abc")
  file.verify(b"abc")
  assert_true(
    try file.verify(b"abd") catch {
      _ => true
    } noraise {
      _ => false
    },
  )
  assert_true(
    try @moonohos.inspect_elf(b"MZ") catch {
      _ => true
    } noraise {
      _ => false
    },
  )
}
