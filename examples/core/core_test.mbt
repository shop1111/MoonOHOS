///|
test "core operations" {
  assert_eq(@demo.add(20, 22), 42)
  assert_eq(@demo.add(-2, 1), -1)
  assert_eq(@demo.scale(1.5, 2.0), 3.0)
  assert_eq(@demo.negate(true), false)
  @demo.ping()
}

///|
test "text and binary references" {
  assert_eq(@demo.echo_text("中文😀\u0000尾"), "中文😀\u0000尾")
  assert_eq(@demo.join_text("中文", "😀"), "中文😀")
  assert_eq(@demo.echo_bytes(b"\x00\xff"), b"\x00\xff")
  assert_eq(@demo.concat_bytes(b"\x00", b"\xff"), b"\x00\xff")
  assert_eq(@demo.describe_bytes("bytes=", b"\x00\xff"), "bytes=2")
}
