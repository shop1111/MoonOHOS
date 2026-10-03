///|
test "array backend generates accessor ABI and balanced owners" {
  let p = @moonohos.parse_project(
    (
      #|{"version":1,"module":"core","package":"a/core","nativeModule":"demo","functions":[{"name":"echo","params":[{"name":"v","type":"Array[Array[String]]"}],"return":"Array[Array[String]]"}]}
    ),
  )
  let generated = p.generate_arrays()
  assert_true(generated.wrapper.contains("v.push(x)"))
  assert_true(generated.header.contains("void * moonohos_type_2_new(void)"))
  assert_true(generated.native.contains("MoonOwner<void *> returned"))
  assert_true(generated.native.contains("AncestorScope scope"))
  assert_true(generated.declarations.contains("Array<Array<string>>"))
  assert_true(!generated.embed.contains("->$"))
}
