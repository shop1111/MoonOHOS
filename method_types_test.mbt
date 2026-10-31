///|
fn method_project(extra : String) -> @moonohos.Project raise {
  @moonohos.parse_project(
    "{\"version\":2,\"module\":\"core\",\"package\":\"a/core\",\"nativeModule\":\"demo\",\"handles\":[{\"name\":\"Index\",\"methods\":[" +
    extra +
    "]}],\"functions\":[{\"name\":\"search\",\"params\":[{\"name\":\"index\",\"type\":\"Index\"},{\"name\":\"q\",\"type\":\"String\"}],\"return\":\"Array[String]\",\"async\":true},{\"name\":\"size\",\"params\":[{\"name\":\"index\",\"type\":\"Index\"}],\"return\":\"Int\"},{\"name\":\"open\",\"params\":[],\"return\":\"Index\"}]}",
  )
}

///|
test "handle methods appear on the interface and forward this" {
  let generated = method_project("\"search\", \"size\"").generate()
  assert_true(
    generated.declarations.contains(
      "export interface Index {\n  close(): void;\n  isClosed(): boolean;\n  search(q: string, token?: CancelToken): Promise<Array<string>>;\n  size(): number;\n}",
    ),
  )
  // Module functions stay available.
  assert_true(
    generated.declarations.contains(
      "export const size: (index: Index) => number;",
    ),
  )
  assert_true(generated.native.contains("{\"size\", nullptr, Method_size,"))
  assert_true(generated.native.contains("argv[0] = self;"))
  assert_true(
    generated.native.contains("return AttachMethods(env, kind, result, state);"),
  )
}

///|
test "methods must name functions taking the handle first" {
  for bad in ["\"open\"", "\"missing\"", "\"close\"", "\"size\", \"size\"", "1"] {
    let rejected = try {
      method_project(bad).validate()
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
}
