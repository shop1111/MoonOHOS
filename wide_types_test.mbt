///|
test "Int64 maps to bigint in declarations and Node-API calls" {
  let p = @moonohos.parse_project(
    (
      #|{"version":1,"module":"core","package":"a/core","nativeModule":"demo","types":[{"name":"Stamp","fields":[{"name":"id","type":"Int64"},{"name":"offsets","type":"Array[Int64]"}]}],"functions":[{"name":"shift","params":[{"name":"s","type":"Stamp"},{"name":"d","type":"Int64"}],"return":"Stamp"},{"name":"total","params":[{"name":"v","type":"Array[Int64]"}],"return":"Int64"}]}
    ),
  )
  let generated = p.generate()
  assert_true(generated.declarations.contains("id: bigint"))
  assert_true(generated.declarations.contains("offsets: Array<bigint>"))
  assert_true(generated.declarations.contains("d: bigint"))
  assert_true(generated.declarations.contains("=> bigint"))
  assert_true(
    generated.native.contains("LeafType(env, value, napi_bigint, path)"),
  )
  assert_true(generated.native.contains("napi_get_value_bigint_int64"))
  assert_true(generated.native.contains("napi_create_bigint_int64"))
  assert_true(generated.header.contains("int64_t"))
}

///|
test "Int64 is accepted in v1 manifests and .mbti interfaces" {
  let config = @moonohos.parse_config(
    (
      #|{"version":1,"module":"demo","package":"moonohos/demo","nativeModule":"wide","functions":[
      #|{"name":"add","params":[{"name":"a","type":"Int64"},{"name":"b","type":"Int64"}],"return":"Int64"}]}
    ),
  )
  @moonohos.verify_interface(config, "pub fn add(Int64, Int64) -> Int64")
  assert_true(
    @moonohos.declarations(config).contains(
      "add: (a: bigint, b: bigint) => bigint",
    ),
  )
  assert_true(
    @moonohos.native_source(config).contains("ReadBigInt(env, argv[0]"),
  )
  assert_true(
    @moonohos.native_source(config).contains(
      "napi_create_bigint_int64(env, value",
    ),
  )
}
