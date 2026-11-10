///|
#derive(Eq, Debug)
pub(all) enum ValueType {
  Int32
  /// MoonBit `Int64`, ArkTS `bigint` (lossless, signed 64-bit).
  Int64
  Float64
  Boolean
  Text
  Binary
  /// `FixedArray[Double]` ↔ `Float64Array` (0.7). The four typed arrays copy
  /// element storage in one block; elements are not range- or finiteness-checked.
  Float64Array
  /// `FixedArray[Float]` ↔ `Float32Array`.
  Float32Array
  /// `FixedArray[Int]` ↔ `Int32Array`.
  Int32Array
  /// `FixedArray[Int64]` ↔ `BigInt64Array`.
  BigInt64Array
  Void
}

///|
/// Element layout of a typed-array value type: Node-API array type, C element
/// type, element width in bytes and the MoonBit runtime constructor.
pub struct TypedLayout {
  napi_type : String
  element : String
  width : Int32
  maker : String
  ark : String
}

///|
pub fn ValueType::typed_layout(self : ValueType) -> TypedLayout? {
  match self {
    Float64Array =>
      Some({
        napi_type: "napi_float64_array",
        element: "double",
        width: 8,
        maker: "moonbit_make_double_array_raw",
        ark: "Float64Array",
      })
    Float32Array =>
      Some({
        napi_type: "napi_float32_array",
        element: "float",
        width: 4,
        maker: "moonbit_make_float_array_raw",
        ark: "Float32Array",
      })
    Int32Array =>
      Some({
        napi_type: "napi_int32_array",
        element: "int32_t",
        width: 4,
        maker: "moonbit_make_int32_array_raw",
        ark: "Int32Array",
      })
    BigInt64Array =>
      Some({
        napi_type: "napi_bigint64_array",
        element: "int64_t",
        width: 8,
        maker: "moonbit_make_int64_array_raw",
        ark: "BigInt64Array",
      })
    _ => None
  }
}

///|
pub struct Parameter {
  name : String
  kind : ValueType
}

///|
pub struct Function {
  name : String
  params : Array[Parameter]
  result : ValueType
}

///|
pub struct Config {
  module_dir : String
  package_name : String
  native_module : String
  functions : Array[Function]
}

///|
#derive(Debug)
pub(all) suberror ConfigError {
  Invalid(String)
}

///|
fn field(value : Json, key : String) -> Json? {
  match value {
    Object(obj) => obj.get(key)
    _ => None
  }
}

///|
fn required_string(value : Json, key : String) -> String raise ConfigError {
  match field(value, key) {
    Some(String(text)) if text != "" => text
    _ => raise Invalid("missing/non-string field: " + key)
  }
}

///|
pub fn identifier(name : String) -> Bool {
  if name.is_empty() {
    return false
  }
  for index, ch in name {
    if !(ch >= 'a' && ch <= 'z') &&
      !(ch >= 'A' && ch <= 'Z') &&
      ch != '_' &&
      !(index > 0 && ch >= '0' && ch <= '9') {
      return false
    }
  }
  !name.has_prefix("__")
}

///|
fn parse_type(name : String, result~ : Bool) -> ValueType raise ConfigError {
  match name {
    // moonc >= 0.10.16 prints `Int` as `Int32` in .mbti files.
    "Int" | "Int32" => Int32
    "Int64" => Int64
    "Double" => Float64
    "Bool" => Boolean
    "String" => Text
    "Bytes" => Binary
    "Unit" if result => Void
    _ => raise Invalid("unsupported type: " + name)
  }
}

///|
pub fn parse_config(text : String) -> Config raise ConfigError {
  let json = @json.parse(text) catch { _ => raise Invalid("invalid JSON") }
  match field(json, "version") {
    Some(Number(1.0, ..)) => ()
    _ => raise Invalid("version must be 1")
  }
  let module_dir = required_string(json, "module")
  let package_name = required_string(json, "package")
  if package_name.contains("\"") ||
    package_name.contains("\\") ||
    package_name.contains("..") ||
    package_name.contains("\n") ||
    package_name.contains(" ") ||
    !package_name.contains("/") {
    raise Invalid("invalid package name")
  }
  let native_module = required_string(json, "nativeModule")
  if !identifier(native_module) {
    raise Invalid("invalid nativeModule")
  }
  let values = match field(json, "functions") {
    Some(Array(values)) if !values.is_empty() => values
    _ => raise Invalid("functions must be a non-empty array")
  }
  let functions : Array[Function] = []
  let names : Map[String, Bool] = Map([])
  for value in values {
    let name = required_string(value, "name")
    if !identifier(name) || names.contains(name) {
      raise Invalid("invalid/duplicate function: " + name)
    }
    names[name] = true
    let entries = match field(value, "params") {
      Some(Array(entries)) => entries
      _ => raise Invalid("params must be an array: " + name)
    }
    let params : Array[Parameter] = []
    let parameters : Map[String, Bool] = Map([])
    for entry in entries {
      let pname = required_string(entry, "name")
      if !identifier(pname) || parameters.contains(pname) {
        raise Invalid("invalid/duplicate parameter: " + pname)
      }
      parameters[pname] = true
      params.push({
        name: pname,
        kind: parse_type(required_string(entry, "type"), result=false),
      })
    }
    functions.push({
      name,
      params,
      result: parse_type(required_string(value, "return"), result=true),
    })
  }
  { module_dir, package_name, native_module, functions, }
}

///|
pub fn ValueType::moon_name(self : ValueType) -> String {
  match self {
    Int32 => "Int"
    Int64 => "Int64"
    Float64 => "Double"
    Boolean => "Bool"
    Text => "String"
    Binary => "Bytes"
    Float64Array => "FixedArray[Double]"
    Float32Array => "FixedArray[Float]"
    Int32Array => "FixedArray[Int]"
    BigInt64Array => "FixedArray[Int64]"
    Void => "Unit"
  }
}

///|
pub fn ValueType::c_name(self : ValueType) -> String {
  match self {
    Int32 | Boolean => "int32_t"
    Int64 => "int64_t"
    Float64 => "double"
    Text => "moonbit_string_t"
    Binary => "moonbit_bytes_t"
    Float64Array => "double *"
    Float32Array => "float *"
    Int32Array => "int32_t *"
    BigInt64Array => "int64_t *"
    Void => "void"
  }
}

///|
pub fn ValueType::ark_name(self : ValueType) -> String {
  match self {
    Int32 | Float64 => "number"
    Int64 => "bigint"
    Boolean => "boolean"
    Text => "string"
    Binary => "Uint8Array"
    Float64Array => "Float64Array"
    Float32Array => "Float32Array"
    Int32Array => "Int32Array"
    BigInt64Array => "BigInt64Array"
    Void => "void"
  }
}

///|
#deprecated
pub extend ValueType with Eq::{equal, not_equal}

///|
#deprecated
pub extend ValueType with @debug.Debug::{to_repr}

///|
#deprecated
pub extend ConfigError with @debug.Debug::{to_repr}
