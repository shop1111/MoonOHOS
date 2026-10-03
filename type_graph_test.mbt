///|
fn graph(
  records : String,
  argument : String,
) -> @moonohos.Project raise @moonohos.ConfigError {
  @moonohos.parse_project(
    "{\"version\":1,\"module\":\"core\",\"package\":\"a/core\",\"nativeModule\":\"demo\",\"types\":" +
    records +
    ",\"functions\":[{\"name\":\"echo\",\"params\":[{\"name\":\"value\",\"type\":\"" +
    argument +
    "\"}],\"return\":\"" +
    argument +
    "\"}]}",
  )
}

///|
test "acyclic dependency order and sharing" {
  let p = graph(
    "[{\"name\":\"Outer\",\"fields\":[{\"name\":\"items\",\"type\":\"Array[Inner]\"}]},{\"name\":\"Inner\",\"fields\":[{\"name\":\"label\",\"type\":\"String\"}]}]",
    "Outer",
  )
  p.validate()
  assert_eq(p.record_order().map(r => r.name).join(","), "Inner,Outer")
  assert_eq(
    p.reachable_types().map(t => t.moon_name()).join(","),
    "String,Inner,Array[Inner],Outer",
  )
  assert_eq(@moonohos.conversion_limits().bytes, 67108864)
}

///|
test "recursive record and unknown record rejected" {
  for
    p in [
      graph(
        "[{\"name\":\"Node\",\"fields\":[{\"name\":\"next\",\"type\":\"Array[Node]\"}]}]",
        "Node",
      ),
      graph("[]", "Missing"),
    ] {
    assert_true(
      try {
        p.validate()
        false
      } catch {
        _ => true
      },
    )
  }
}

///|
test "depth boundary and Unit result" {
  let mut kind = "Int"
  for _ in 0..<32 {
    kind = "Array[" + kind + "]"
  }
  graph("[]", kind).validate()
  assert_true(
    try {
      graph("[]", "Array[" + kind + "]").validate()
      false
    } catch {
      _ => true
    },
  )
}
