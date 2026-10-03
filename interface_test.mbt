///|
test "interface parser accepts multiline arrays and records" {
  let interface = @moonohos.parse_package_interface(
    (
      #|package "a/core"
      #|pub fn echo(
      #|  Array[Array[Double]],
      #|  String,
      #|) -> Sample
      #|pub(all) struct Sample {
      #|  values : Array[Double]
      #|  mut label : String
      #|}
    ),
  )
  assert_eq(
    interface.functions[0].params[0].moon_name(),
    "Array[Array[Double]]",
  )
  assert_eq(interface.records[0].fields.length(), 2)
  assert_true(interface.functions[0].unsupported is None)
}

///|
test "unsupported signature syntax is diagnosed" {
  for
    declaration in [
      "pub fn f(Int) -> Int raise Error", "pub fn f(x~ : Int) -> Int", "pub fn f(Int?) -> Int",
    ] {
    assert_true(
      @moonohos.parse_package_interface(declaration).functions[0].unsupported
      is Some(_),
    )
  }
  assert_true(
    @moonohos.parse_package_interface("#value\npub struct S { x : Int }").records[0].unsupported
    is Some(_),
  )
}

///|
test "semantic interface matching ignores layout order" {
  let p = @moonohos.parse_project(
    (
      #|{"version":1,"module":"core","package":"a/core","nativeModule":"demo","types":[{"name":"Sample","fields":[{"name":"label","type":"String"},{"name":"values","type":"Array[Double]"}]}],"functions":[{"name":"echo","params":[{"name":"v","type":"Sample"}],"return":"Sample"}]}
    ),
  )
  p.verify_interface(
    "pub fn echo(Sample) -> Sample\npub struct Sample { values : Array[Double] label : String }",
  )
  assert_true(
    try {
      p.verify_interface(
        "pub fn echo(Sample) -> Sample\npub struct Sample { label : Int }",
      )
      false
    } catch {
      _ => true
    },
  )
}
