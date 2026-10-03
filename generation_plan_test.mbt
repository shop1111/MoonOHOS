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
