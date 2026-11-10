///|
fn typed_project() -> @moonohos.Project raise {
  @moonohos.parse_project(
    (
      #|{"version":2,"module":"core","package":"a/core","nativeModule":"demo",
      #| "types":[{"name":"Series","fields":[{"name":"samples","type":"FixedArray[Double]"},{"name":"marks","type":"FixedArray[Int]?"}]}],
      #| "functions":[
      #|  {"name":"scale","params":[{"name":"v","type":"FixedArray[Double]"},{"name":"k","type":"Double"}],"return":"FixedArray[Double]"},
      #|  {"name":"narrow","params":[{"name":"v","type":"FixedArray[Double]"}],"return":"FixedArray[Float]"},
      #|  {"name":"counts","params":[{"name":"v","type":"FixedArray[Int32]"}],"return":"FixedArray[Int64]"},
      #|  {"name":"parts","params":[{"name":"s","type":"Series"}],"return":"Array[FixedArray[Double]]"},
      #|  {"name":"watch","params":[{"name":"on_frame","type":"(FixedArray[Float]) -> Unit"}],"return":"Unit"}]}
    ),
  )
}

///|
test "numeric FixedArrays map to ArkTS typed arrays" {
  let generated = typed_project().generate()
  let declarations = generated.declarations
  assert_true(declarations.contains("v: Float64Array, k: number"))
  assert_true(declarations.contains("=> Float32Array"))
  assert_true(declarations.contains("v: Int32Array"))
  assert_true(declarations.contains("=> BigInt64Array"))
  assert_true(declarations.contains("samples: Float64Array"))
  assert_true(declarations.contains("marks?: Int32Array"))
  assert_true(declarations.contains("Array<Float64Array>"))
  assert_true(declarations.contains("on_frame: (arg0: Float32Array) => void"))
  let native = generated.native
  assert_true(native.contains("PrepareTyped(env, value, napi_float64_array, 8"))
  assert_true(native.contains("PrepareTyped(env, value, napi_float32_array, 4"))
  assert_true(native.contains("PrepareTyped(env, value, napi_int32_array, 4"))
  assert_true(
    native.contains(
      "MakeTyped<double>(value.bytes, moonbit_make_double_array_raw)",
    ),
  )
  assert_true(
    native.contains(
      "CreateTyped(env, value.bytes, napi_bigint64_array, 8, &result)",
    ),
  )
  assert_true(generated.header.contains("double *"))
}

///|
test "FixedArray types match .mbti spellings and reject other elements" {
  let project = typed_project()
  project.verify_interface(
    (
      #|pub fn counts(FixedArray[Int32]) -> FixedArray[Int64]
      #|pub fn narrow(FixedArray[Double]) -> FixedArray[Float]
      #|pub fn parts(Series) -> Array[FixedArray[Double]]
      #|pub fn scale(FixedArray[Double], Double) -> FixedArray[Double]
      #|pub fn watch((FixedArray[Float]) -> Unit) -> Unit
      #|pub(all) struct Series {
      #|  samples : FixedArray[Double]
      #|  marks : FixedArray[Int32]?
      #|}
    ),
  )
  let mismatch = try {
    project.verify_interface(
      (
        #|pub fn counts(FixedArray[Int32]) -> FixedArray[Int64]
        #|pub fn narrow(FixedArray[Double]) -> FixedArray[Double]
        #|pub fn parts(Series) -> Array[FixedArray[Double]]
        #|pub fn scale(FixedArray[Double], Double) -> FixedArray[Double]
        #|pub fn watch((FixedArray[Float]) -> Unit) -> Unit
        #|pub(all) struct Series {
        #|  samples : FixedArray[Double]
        #|  marks : FixedArray[Int32]?
        #|}
      ),
    )
    false
  } catch {
    _ => true
  }
  assert_true(mismatch)
  for element in ["String", "Bool", "Byte", "Array[Double]", "Series"] {
    let rejected = try {
      @moonohos.parse_type_expr("FixedArray[" + element + "]") |> ignore
      false
    } catch {
      Invalid(message) => message.contains("FixedArray")
    }
    assert_true(rejected)
  }
}
