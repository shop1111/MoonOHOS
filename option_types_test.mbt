///|
test "Option crosses as T | undefined and is lowered to an array in MoonBit" {
  let p = @moonohos.parse_project(
    (
      #|{"version":1,"module":"core","package":"a/core","nativeModule":"demo","types":[{"name":"Profile","fields":[{"name":"nickname","type":"String?"},{"name":"tags","type":"Array[Option[String]]"}]}],"functions":[{"name":"greet","params":[{"name":"name","type":"String?"}],"return":"String"},{"name":"find","params":[{"name":"v","type":"Array[Int]"}],"return":"Int?"},{"name":"best","params":[],"return":"Profile?"}]}
    ),
  )
  let generated = p.generate()
  assert_true(generated.declarations.contains("nickname?: string;"))
  assert_true(
    generated.declarations.contains("tags: Array<string | undefined>;"),
  )
  assert_true(
    generated.declarations.contains("(name: string | undefined) => string"),
  )
  assert_true(generated.declarations.contains("=> number | undefined"))
  assert_true(generated.declarations.contains("=> Profile | undefined"))
  // Business export: parameters lifted from arrays, results lowered into arrays.
  assert_true(
    generated.wrapper.contains(
      "pub fn moonohos_raw_greet(name : Array[String]) -> String { let name = name.get(0); @core.greet(name) }",
    ),
  )
  assert_true(
    generated.wrapper.contains(
      "-> Array[Int] { match (@core.find(v)) { Some(x) => [x]; None => [] } }",
    ),
  )
  assert_true(
    generated.native.contains("OwnOrUndefined(env, value, \"nickname\""),
  )
  assert_true(generated.native.contains("IsAbsent(env, value, absent)"))
}

///|
test "Option grammar in manifests and interfaces" {
  @debug.debug_inspect(
    @moonohos.parse_type_expr("Option[Array[Int?]]").moon_name(),
    content="\"Array[Int?]?\"",
  )
  assert_eq(
    @moonohos.parse_type_expr("Int64?").ark_name(),
    "bigint | undefined",
  )
  let interface = @moonohos.parse_package_interface(
    "pub fn f(Int32?, Array[String?]) -> Profile?",
  )
  assert_true(interface.functions[0].unsupported is None)
  let rejected = try {
    @moonohos.parse_project(
      (
        #|{"version":1,"module":"core","package":"a/core","nativeModule":"demo","functions":[{"name":"f","params":[{"name":"x","type":"Option[Int?]"}],"return":"Int"}]}
      ),
    ).validate()
    false
  } catch {
    Invalid(message) => message.contains("nested Option")
  }
  assert_true(rejected)
}
