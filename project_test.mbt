///|
test "complex type grammar and compatibility" {
  let nested = @moonohos.parse_type_expr("Array [ Array [ String ] ]")
  assert_eq(nested.moon_name(), "Array[Array[String]]")
  assert_eq(nested.ark_name(), "Array<Array<string>>")
  assert_true(nested.is_reference())
  assert_eq(@moonohos.parse_type_expr("Sample").wrapper_name(), "@core.Sample")
  let old = @moonohos.parse_config(
    "{\"version\":1,\"module\":\"core\",\"package\":\"a/core\",\"nativeModule\":\"demo\",\"functions\":[{\"name\":\"ping\",\"params\":[],\"return\":\"Unit\"}]}",
  )
  assert_eq(old.to_project().functions[0].result.moon_name(), "Unit")
}

///|
test "malformed and unsupported type grammar" {
  for
    text in [
      "", "Array", "Array[]", "Array[Int,Double]", "Int?", "Array[Unit]", "Array[Int]]",
      "Int Double",
    ] {
    let rejected = try {
      @moonohos.parse_type_expr(text) |> ignore
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
}

///|
test "record schema and mixed parameters" {
  let project = @moonohos.parse_project(
    (
      #|{"version":1,"module":"core","package":"a/core","nativeModule":"demo","types":[{"name":"Sample","fields":[{"name":"label","type":"String"},{"name":"values","type":"Array[Double]"}]}],"functions":[{"name":"batch","params":[{"name":"samples","type":"Array[Sample]"},{"name":"active","type":"Bool"}],"return":"Sample"}]}
    ),
  )
  assert_eq(project.records.length(), 1)
  assert_eq(project.functions[0].params[0].kind.moon_name(), "Array[Sample]")
}
