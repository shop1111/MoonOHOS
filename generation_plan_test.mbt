///|
test "stable generation plan and opaque ABI" {
  let p = @moonohos.parse_project(
    (
      #|{"version":1,"module":"core","package":"a/core","nativeModule":"demo","functions":[{"name":"echo","params":[{"name":"v","type":"Array[String]"}],"return":"Array[String]"}]}
    ),
  )
  assert_eq(p.generation_plan().stringify(), p.generation_plan().stringify())
  assert_true(p.business_header().contains("void * moonohos_echo(void * arg0)"))
  assert_true(p.business_wrapper().contains("@core.echo(v)"))
  assert_true(p.business_adapters().contains("return moonohos_raw_echo(arg0)"))
}

///|
test "internal symbol collisions rejected" {
  let p = @moonohos.parse_project(
    (
      #|{"version":1,"module":"core","package":"a/core","nativeModule":"demo","functions":[{"name":"initialize","params":[],"return":"Unit"}]}
    ),
  )
  assert_true(
    try {
      p.generation_plan() |> ignore
      false
    } catch {
      _ => true
    },
  )
}

///|
test "raw exports cannot collide with another adapter" {
  let project = @moonohos.parse_project(
    "{\"version\":1,\"module\":\".\",\"package\":\"a/core\",\"nativeModule\":\"demo\",\"functions\":[{\"name\":\"echo\",\"params\":[],\"return\":\"Int\"},{\"name\":\"raw_echo\",\"params\":[],\"return\":\"Int\"}]}",
  )
  assert_true(
    try project.generation_plan() catch {
      _ => true
    } noraise {
      _ => false
    },
  )
}
