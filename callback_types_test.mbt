///|
fn callback_project(
  functions : String,
) -> @moonohos.Project raise @moonohos.ConfigError {
  @moonohos.parse_project(
    "{\"version\":2,\"module\":\"core\",\"package\":\"a/core\",\"nativeModule\":\"demo\",\"types\":[{\"name\":\"Step\",\"fields\":[{\"name\":\"done\",\"type\":\"Int\"}]}],\"functions\":[" +
    functions +
    "]}",
  )
}

///|
fn callback_rejected(functions : String, expected : String) -> Bool {
  try {
    callback_project(functions).validate()
    false
  } catch {
    Invalid(message) => message.contains(expected)
  }
}

///|
test "callback grammar in manifests and interfaces" {
  let kind = @moonohos.parse_type_expr("(String, Array[Int?]) -> Unit")
  assert_eq(kind.moon_name(), "(String, Array[Int?]) -> Unit")
  assert_eq(
    kind.ark_name(),
    "(arg0: string, arg1: Array<number | undefined>) => void",
  )
  assert_eq(@moonohos.parse_type_expr("()->Unit").moon_name(), "() -> Unit")
  assert_true(kind.is_opaque())
  let returns = try {
    @moonohos.parse_type_expr("(Int) -> Int") |> ignore
    false
  } catch {
    Invalid(message) => message.contains("must return Unit")
  }
  assert_true(returns)
  let interface = @moonohos.parse_package_interface(
    (
      #|pub fn each(String, (String, Int32) -> Unit) -> Int32
      #|pub fn bad((Int32) -> Int32) -> Unit
      #|pub fn raising((Int32) -> Unit raise) -> Unit
    ),
  )
  assert_true(interface.functions[0].unsupported is None)
  assert_eq(
    interface.functions[0].params[1].moon_name(),
    "(String, Int) -> Unit",
  )
  assert_true(interface.functions[1].unsupported is Some(_))
  assert_true(interface.functions[2].unsupported is Some(_))
}

///|
test "callbacks are checked against the package interface" {
  let p = callback_project(
    (
      #|{"name":"each","params":[{"name":"text","type":"String"},{"name":"visit","type":"(String, Int) -> Unit"}],"return":"Int"}
    ),
  )
  let step = "pub(all) struct Step {\n  done : Int32\n}\n"
  p.verify_interface(
    step + "pub fn each(String, (String, Int32) -> Unit) -> Int32",
  )
  let mismatch = try {
    p.verify_interface(step + "pub fn each(String, (String) -> Unit) -> Int32")
    false
  } catch {
    Invalid(message) => message.contains("signature mismatch")
  }
  assert_true(mismatch)
}

///|
test "callbacks are only function parameters with copyable arguments" {
  assert_true(
    callback_rejected(
      (
        #|{"name":"f","params":[],"return":"(Int) -> Unit"}
      ),
      "only supported as function parameters",
    ),
  )
  assert_true(
    callback_rejected(
      (
        #|{"name":"f","params":[{"name":"cbs","type":"Array[(Int) -> Unit]"}],"return":"Unit"}
      ),
      "only supported as function parameters",
    ),
  )
  assert_true(
    callback_rejected(
      (
        #|{"name":"f","params":[{"name":"cb","type":"((Int) -> Unit) -> Unit"}],"return":"Unit"}
      ),
      "nested callbacks",
    ),
  )
  let handle = try {
    @moonohos.parse_project(
      (
        #|{"version":2,"module":"core","package":"a/core","nativeModule":"demo","handles":[{"name":"Index"}],"functions":[{"name":"f","params":[{"name":"cb","type":"(Index) -> Unit"}],"return":"Unit"}]}
      ),
    ).validate()
    false
  } catch {
    Invalid(message) => message.contains("cannot be a callback argument")
  }
  assert_true(handle)
}

///|
test "sync callbacks run during the call; async ones are queued" {
  let p = callback_project(
    (
      #|{"name":"each","params":[{"name":"text","type":"String"},{"name":"visit","type":"(Step, Int?) -> Unit"}],"return":"Int"},
      #|{"name":"work","params":[{"name":"n","type":"Int"},{"name":"on_progress","type":"(Int) -> Unit"}],"return":"Int","async":true}
    ),
  )
  let generated = p.generate()
  assert_true(
    generated.declarations.contains(
      "export const each: (text: string, visit: (arg0: Step, arg1: number | undefined) => void) => number;",
    ),
  )
  assert_true(
    generated.declarations.contains(
      "(n: number, on_progress: (arg0: number) => void, token?: CancelToken) => Promise<number>",
    ),
  )
  // The business function receives a closure that lowers its arguments.
  assert_true(
    generated.wrapper.contains(
      "#borrow(a0, a1)\nextern \"C\" fn moonohos_event_each_1(id : Int64, a0 : @core.Step, a1 : Array[Int]) -> Unit = \"moonohos_event_each_1\"",
    ),
  )
  assert_true(
    generated.wrapper.contains(
      "pub fn moonohos_raw_each(text : String, visit : Int64) -> Int { let visit = fn(moonohos_arg0 : @core.Step, moonohos_arg1 : Int?) { moonohos_event_each_1(visit, moonohos_arg0, match (moonohos_arg1) { Some(x) => [x]; None => [] }) }; @core.each(text, visit) }",
    ),
  )
  assert_true(
    generated.wrapper.contains(
      "extern \"C\" fn moonohos_event_work_1(id : Int64, a0 : Int) -> Unit",
    ),
  )
  // Sync: direct invocation, failure rethrown after the gate.
  assert_true(generated.native.contains("EventChannel events(env, false);"))
  assert_true(
    generated.native.contains(
      "ReadCallback(env, argv[1], events, \"each.visit\")",
    ),
  )
  assert_true(generated.native.contains("return events.Raise(env);"))
  // Async: threadsafe function opened on the JS thread, settled after events.
  assert_true(
    generated.native.contains(
      "task->events = std::make_shared<EventChannel>(env, true);",
    ),
  )
  assert_true(generated.native.contains("FinishTask(env,"))
  assert_true(
    generated.native.contains(
      "extern \"C\" void moonohos_event_work_1(int64_t id, int32_t a0)",
    ),
  )
  let plan = p.generation_plan()
  guard plan is { "calls": [{ "callbacks": [String(first)], .. }, ..], .. } else {
    fail("callbacks missing from the plan")
  }
  assert_eq(first, "visit")
}

///|
test "callback extern names cannot collide with exports" {
  let collision = try {
    callback_project(
      (
        #|{"name":"f","params":[{"name":"cb","type":"() -> Unit"}],"return":"Unit"},
        #|{"name":"event_f_0","params":[],"return":"Unit"}
      ),
    ).generate()
    |> ignore
    false
  } catch {
    Invalid(message) => message.contains("colliding callback symbol")
  }
  assert_true(collision)
}
