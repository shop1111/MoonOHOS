///|
test "nested records use field accessor ownership and interfaces" {
  let p = @moonohos.parse_project(
    (
      #|{"version":1,"module":"core","package":"a/core","nativeModule":"demo","types":[{"name":"Meta","fields":[{"name":"active","type":"Bool"}]},{"name":"Sample","fields":[{"name":"label","type":"String"},{"name":"meta","type":"Meta"},{"name":"values","type":"Array[Double]"}]}],"functions":[{"name":"echo","params":[{"name":"v","type":"Array[Sample]"}],"return":"Sample"}]}
    ),
  )
  let generated = p.generate()
  assert_true(generated.declarations.contains("export interface Meta"))
  assert_true(generated.declarations.contains("meta: Meta"))
  assert_true(generated.wrapper.contains("{label, meta, values}"))
  assert_true(generated.wrapper.contains("v.meta"))
  assert_true(generated.native.contains("napi_set_named_property"))
  assert_true(!generated.embed.contains("struct _M0"))
}
