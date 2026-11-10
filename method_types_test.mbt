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

///|
test "wrapped objects carry a type tag unique to the module" {
  let first = method_project("\"size\"").generate().native
  let renamed = @moonohos.parse_project(
      (
        #|{"version":2,"module":"core","package":"a/core","nativeModule":"other","handles":[{"name":"Index"}],"functions":[{"name":"open","params":[],"return":"Index"}]}
      ),
    ).generate().native
  let tag = fn(native : String) -> String raise {
    guard native.find("static const napi_type_tag tag = {") is Some(start) else {
      fail("module tag missing")
    }
    "\{native[start:start + 80]}"
  }
  assert_true(first.contains("napi_type_tag_object(env, result, &ModuleTag())"))
  assert_true(
    first.contains("napi_check_object_type_tag(env, value, &ModuleTag(), &own)"),
  )
  assert_true(tag(first) != tag(renamed))
}

///|
fn sized_project(
  size : String,
) -> @moonohos.Project raise @moonohos.ConfigError {
  @moonohos.parse_project(
    "{\"version\":2,\"module\":\"core\",\"package\":\"a/core\",\"nativeModule\":\"demo\",\"handles\":[{\"name\":\"Index\",\"size\":\"" +
    size +
    "\"}],\"functions\":[{\"name\":\"bytes\",\"params\":[{\"name\":\"index\",\"type\":\"Index\"}],\"return\":\"Int\"},{\"name\":\"label\",\"params\":[{\"name\":\"index\",\"type\":\"Index\"}],\"return\":\"String\"},{\"name\":\"open\",\"params\":[],\"return\":\"Index\"},{\"name\":\"open_later\",\"params\":[],\"return\":\"Index\",\"async\":true}]}",
  )
}

///|
test "declared handle sizes are sampled under the gate and wrapped with napi_wrap_enhance" {
  let native = sized_project("bytes").generate().native
  // Sync and async producers both sample the size right after the call.
  assert_true(
    native.contains(
      "handle_size = static_cast<size_t>(std::max<int32_t>(0, moonohos_bytes(handle_result)));",
    ),
  )
  assert_true(
    native.contains(
      "task->handle_size = static_cast<size_t>(std::max<int32_t>(0, moonohos_bytes(task->handle_result)));",
    ),
  )
  assert_true(native.contains("result, task.handle_size)"))
  assert_true(native.contains("napi_wrap_enhance(env, result, wrapped.get()"))
  assert_true(
    sized_project("bytes").generate().declarations.contains(
      "nativeBytes: number",
    ),
  )
  // Without a declared size nothing is sampled.
  let plain = method_project("").generate().native
  assert_false(plain.contains("handle_size = static_cast"))
}

///|
test "size functions must be synchronous (Handle) -> Int" {
  for name in ["label", "open", "open_later", "missing"] {
    let rejected = try {
      sized_project(name).generate() |> ignore
      false
    } catch {
      Invalid(message) => message.contains("handles.Index: size " + name)
    }
    assert_true(rejected)
  }
}
