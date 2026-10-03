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

///|
test "shared record DAG remains bounded and checks cached height at use site" {
  let records : Array[Json] = [
    { "name": "Level0", "fields": [{ "name": "value", "type": "Int" }] },
  ]
  for level in 1..<32 {
    let child = "Level" + (level - 1).to_string()
    records.push({
      "name": "Level" + level.to_string(),
      "fields": [
        { "name": "left", "type": child },
        { "name": "right", "type": child },
      ],
    })
  }
  let declarations = records.to_json().stringify()
  let project = graph(declarations, "Level31")
  project.validate()
  assert_eq(project.record_order().length(), 32)
  assert_true(
    try {
      graph(declarations, "Array[Level31]").validate()
      false
    } catch {
      _ => true
    },
  )
}
