// Generates a MoonBit package (MoonBit API, C stub, native descriptor and a
// coverage report) from a CHeaderModel. Every value crosses the C boundary as
// a scalar or through a buffer MoonBit allocated (FixedArray / Bytes), so the
// generated C never allocates or releases MoonBit objects.

///|
pub struct BindgenSpec {
  /// Mooncakes package, e.g. `shop1111/moonohos_ohos/sys/battery`.
  package_name : String
  /// File stem of the generated sources, e.g. `battery`.
  name : String
  /// Headers relative to `usr/include`; only their functions are bound.
  headers : Array[String]
  /// Function name prefixes to bind (all functions when empty); the matched
  /// prefix is removed from the MoonBit name.
  prefixes : Array[String]
  exclude : Array[String]
  /// Capacity used for `char *` outputs and `const char *` results.
  string_buffer : Int32
}

///|
pub fn parse_bindgen_spec(text : String) -> BindgenSpec raise ConfigError {
  let json = @json.parse(text) catch {
    _ => raise Invalid("bindgen: spec is not JSON")
  }
  let strings = fn(
    key : String,
    required : Bool,
  ) -> Array[String] raise ConfigError {
    match json_field(json, key) {
      Some(Array(items)) =>
        items.map(item => {
          match item {
            String(s) => s
            _ => ""
          }
        })
      None if !required => []
      _ => raise Invalid("bindgen: " + key + " must be an array of strings")
    }
  }
  match json_text(Some(json), "schema") {
    Some("moonohos-bindgen-v1") => ()
    _ => raise Invalid("bindgen: schema must be moonohos-bindgen-v1")
  }
  let package_name = json_text(Some(json), "package").unwrap_or("")
  let name = json_text(Some(json), "name").unwrap_or("")
  if !package_name.contains("/") || !identifier(name) {
    raise Invalid("bindgen: package and name are required")
  }
  let headers = strings("headers", true)
  if headers.is_empty() || headers.any(h => h == "" || h.contains("..")) {
    raise Invalid("bindgen: headers must name SDK headers under usr/include")
  }
  let string_buffer = match json_field(json, "stringBuffer") {
    Some(Number(n, ..)) if n >= 16.0 && n <= 65536.0 => n.to_int()
    None => 256
    _ => raise Invalid("bindgen: stringBuffer must be 16..65536")
  }
  {
    package_name,
    name,
    headers,
    prefixes: strings("prefixes", false),
    exclude: strings("exclude", false),
    string_buffer,
  }
}

///|
priv enum Scalar {
  SInt
  SUInt
  SInt64
  SUInt64
  SFloat
  SDouble
  SBool
  SEnum(String)
}

///|
priv enum FieldPlan {
  FScalar(String, String, Scalar) // C field, MoonBit field, kind
  FText(String, String, Int32) // char[N] <-> String
  FBytes(String, String, Int32) // uint8_t[N] <-> Bytes
}

///|
priv enum ParamPlan {
  InValue(String, Scalar, String) // MoonBit name, kind, C spelling
  InString(String)
  InBytes(String, String, String) // name, pointer spelling, length spelling
  OutValue(String, Scalar, String) // name, kind, pointee spelling
  OutString(String, String, Bool) // name, length spelling, length by pointer
  InStruct(String, String, Bool) // name, record, passed by pointer
  InOutStruct(String, String)
  /// Non-const struct pointer of a getter: filled by C, not read.
  OutStruct(String, String)
}

///|
priv enum ResultPlan {
  RVoid
  RValue(Scalar, String)
  RCheck(String) // error-code enum
  RStruct(String)
  RCString
}

///|
priv struct Binding {
  function : CFunction
  moon_name : String
  params : Array[ParamPlan]
  result : ResultPlan
  library : String
}

///|
priv struct Generator {
  spec : BindgenSpec
  model : CHeaderModel
  enums_used : Map[String, Bool]
  records_used : Map[String, Bool]
}

///|
let moon_keywords : Array[String] = [
  "as", "async", "break", "catch", "const", "continue", "else", "enum", "extern",
  "false", "fn", "for", "guard", "if", "impl", "import", "in", "is", "let", "loop",
  "match", "mut", "priv", "pub", "raise", "return", "struct", "test", "trait", "true",
  "try", "type", "typealias", "while", "with", "lexmatch", "defer", "noraise", "local",
  "readonly", "enumview", "using", "extenum",
]

///|
/// `GetDefaultDisplayWidth` -> `get_default_display_width`, `canIUse` -> `can_i_use`.
pub fn snake_name(name : String) -> String {
  // Mixed-case acronyms read as one word: QoS -> qos, IDs -> ids.
  let name = name
    .replace_all(old="QoS", new="Qos")
    .replace_all(old="IDs", new="Ids")
  let chars = name.to_array()
  let out = StringBuilder()
  for i, ch in chars {
    let upper = ch >= 'A' && ch <= 'Z'
    if upper && i > 0 {
      let prev = chars[i - 1]
      let next_lower = i + 1 < chars.length() &&
        chars[i + 1] >= 'a' &&
        chars[i + 1] <= 'z'
      let prev_lower = (prev >= 'a' && prev <= 'z') ||
        (prev >= '0' && prev <= '9')
      let prev_upper = prev >= 'A' && prev <= 'Z'
      if prev_lower || (prev_upper && next_lower) {
        out.write_char('_')
      }
    }
    if upper {
      out.write_char(Int32::unsafe_to_char(ch.to_int() + 32))
    } else if (ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9') {
      out.write_char(ch)
    } else {
      out.write_char('_')
    }
  }
  let mut text = out.to_string()
  while text.contains("__") {
    text = text.replace_all(old="__", new="_")
  }
  while text.has_prefix("_") {
    text = text[1:].to_owned()
  }
  while text.has_suffix("_") {
    text = text[:text.length() - 1].to_owned()
  }
  if text == "" || (text.to_array()[0] >= '0' && text.to_array()[0] <= '9') {
    text = "v_" + text
  }
  if moon_keywords.contains(text) {
    text + "_"
  } else {
    text
  }
}

///|
/// `PLUGGED_TYPE_NONE` -> `PluggedTypeNone`.
fn constructor_name(name : String) -> String {
  let out = StringBuilder()
  for part in name.split("_") {
    let word = part.to_owned()
    if word == "" {
      continue
    }
    let chars = word.to_array()
    let all_upper = chars.all(c => !(c >= 'a' && c <= 'z'))
    for i, ch in chars {
      if i == 0 && ch >= 'a' && ch <= 'z' {
        out.write_char(Int32::unsafe_to_char(ch.to_int() - 32))
      } else if i > 0 && all_upper && ch >= 'A' && ch <= 'Z' {
        out.write_char(Int32::unsafe_to_char(ch.to_int() + 32))
      } else {
        out.write_char(ch)
      }
    }
  }
  let text = out.to_string()
  if text == "" || !(text.to_array()[0] >= 'A' && text.to_array()[0] <= 'Z') {
    "V" + text
  } else {
    text
  }
}

///|
/// MoonBit type name for a C enum or struct (the typedef name when there is
/// one); must start with an upper-case letter.
fn type_name(model : CHeaderModel, tag : String) -> String {
  let name = model.aliases.get(tag).unwrap_or(tag)
  let chars = name.to_array()
  if chars.length() > 0 && chars[0] >= 'a' && chars[0] <= 'z' {
    Int32::unsafe_to_char(chars[0].to_int() - 32).to_string() +
    name[1:].to_owned()
  } else if chars.length() > 0 && chars[0] == '_' {
    "C" + name
  } else {
    name
  }
}

///|
fn Generator::scalar(self : Generator, kind : CType) -> Scalar? {
  if kind.pointers != 0 || kind.array is Some(_) {
    return None
  }
  match kind.base {
    CBool => Some(SBool)
    CChar => Some(SInt)
    CInt(64, true) => Some(SInt64)
    CInt(64, false) => Some(SUInt64)
    CInt(32, false) => Some(SUInt)
    CInt(_, _) => Some(SInt)
    CFloat => Some(SFloat)
    CDouble => Some(SDouble)
    CEnum(name) if self.model.enums.contains(name) => Some(SEnum(name))
    _ => None
  }
}

///|
fn Generator::fields(self : Generator, record : String) -> Array[FieldPlan]? {
  guard self.model.records.get(record) is Some(def) && def.complete else {
    return None
  }
  let plans : Array[FieldPlan] = []
  let names : Map[String, Bool] = Map([])
  for field in def.fields {
    let mut moon = snake_name(field.name)
    while names.contains(moon) {
      moon = moon + "_"
    }
    names[moon] = true
    match (field.kind.base, field.kind.array, field.kind.pointers) {
      (CChar, Some(n), 0) if n > 0 => plans.push(FText(field.name, moon, n))
      (CInt(8, false), Some(n), 0) if n > 0 =>
        plans.push(FBytes(field.name, moon, n))
      _ =>
        match self.scalar(field.kind) {
          Some(kind) => plans.push(FScalar(field.name, moon, kind))
          None => return None
        }
    }
  }
  if plans.is_empty() {
    None
  } else {
    Some(plans)
  }
}

///|
/// An enum returned as an error code: its name says so and 0 is success.
fn error_enum(def : CEnumDef) -> Bool {
  let lower = def.name.to_lower()
  (lower.contains("err") || lower.contains("result")) &&
  def.constants.any(c => c.1 == 0L)
}

///|
fn is_integer(kind : CType) -> Bool {
  kind.pointers == 0 &&
  kind.array is None &&
  (kind.base is CInt(_, _) || kind.base is CChar)
}

///|
/// Pointee spelling: `QoS_Level *` -> `QoS_Level`.
fn pointee_spelling(spelling : String) -> String {
  let text = spelling.replace_all(old="restrict", new="")
  match text.rev_find("*") {
    Some(index) => text[:index].trim().to_owned()
    None => text.trim().to_owned()
  }
}

///|
fn Generator::plan(
  self : Generator,
  function : CFunction,
  spellings : Array[String],
  result_spelling : String,
) -> Result[(Array[ParamPlan], ResultPlan), String] {
  if function.variadic {
    return Err("variadic function")
  }
  let params : Array[ParamPlan] = []
  let names : Map[String, Bool] = Map([])
  let fresh = fn(name : String) -> String {
    let mut moon = snake_name(name)
    while names.contains(moon) {
      moon = moon + "_"
    }
    names[moon] = true
    moon
  }
  let mut i = 0
  while i < function.params.length() {
    let param = function.params[i]
    let kind = param.kind
    let spelling = spellings[i]
    let next = function.params.get(i + 1)
    match (kind.pointers, kind.base) {
      (_, CUnsupported(what)) =>
        return Err("parameter " + param.name + ": unsupported type " + what)
      (0, CRecord(record)) =>
        match self.fields(record) {
          Some(_) => {
            params.push(InStruct(fresh(param.name), record, false))
            self.records_used[record] = true
          }
          None =>
            return Err(
              "parameter " + param.name + ": struct " + record + " is not flat",
            )
        }
      (0, _) =>
        match self.scalar(kind) {
          Some(scalar) => {
            params.push(InValue(fresh(param.name), scalar, spelling))
            if scalar is SEnum(name) {
              self.enums_used[name] = true
            }
          }
          None => return Err("parameter " + param.name + ": unsupported value")
        }
      (1, CChar) if kind.const_pointee =>
        params.push(InString(fresh(param.name)))
      (1, CChar) =>
        match next {
          Some(len) if is_integer(len.kind) => {
            params.push(OutString(fresh(param.name), spellings[i + 1], false))
            i += 1
          }
          Some(len) if len.kind.pointers == 1 &&
            !len.kind.const_pointee &&
            len.kind.base is CInt(_, _) => {
            params.push(
              OutString(
                fresh(param.name),
                pointee_spelling(spellings[i + 1]),
                true,
              ),
            )
            i += 1
          }
          _ =>
            return Err(
              "parameter " + param.name + ": char buffer without a length",
            )
        }
      (1, CInt(8, false)) if kind.const_pointee =>
        match next {
          Some(len) if is_integer(len.kind) => {
            params.push(InBytes(fresh(param.name), spelling, spellings[i + 1]))
            i += 1
          }
          _ =>
            return Err(
              "parameter " + param.name + ": byte input without a length",
            )
        }
      (1, CRecord(record)) =>
        match self.fields(record) {
          Some(_) => {
            self.records_used[record] = true
            if releasing_name(function.name) {
              // e.g. DestroyAvailableArea: the pointer came from the SDK;
              // passing a copy would free memory C never allocated.
              return Err(
                "parameter " +
                param.name +
                ": released by the SDK (handles are not generated yet)",
              )
            }
            if kind.const_pointee {
              params.push(InStruct(fresh(param.name), record, true))
            } else if output_name(function.name) {
              params.push(OutStruct(fresh(param.name), record))
            } else {
              params.push(InOutStruct(fresh(param.name), record))
            }
          }
          None =>
            return Err(
              "parameter " +
              param.name +
              ": " +
              record +
              " is an opaque or nested struct (handles are not generated yet)",
            )
        }
      (1, CVoid) => return Err("parameter " + param.name + ": untyped pointer")
      // Buffers, not single values: a byte pointer, or a pointer followed by
      // a length. Writing them through a one-element slot would overflow.
      (1, CInt(8, _)) if !kind.const_pointee =>
        return Err(
          "parameter " +
          param.name +
          ": output byte buffer (result length unknown)",
        )
      (1, _) if !kind.const_pointee &&
        next is Some(len) &&
        is_integer(len.kind) &&
        length_name(len.name) =>
        return Err(
          "parameter " +
          param.name +
          ": output array of " +
          len.name +
          " elements",
        )
      (1, _) if !kind.const_pointee => {
        let inner = { ..kind, pointers: 0, const_pointee: false, }
        match self.scalar(inner) {
          Some(scalar) => {
            params.push(
              OutValue(fresh(param.name), scalar, pointee_spelling(spelling)),
            )
            if scalar is SEnum(name) {
              self.enums_used[name] = true
            }
          }
          None =>
            return Err("parameter " + param.name + ": unsupported pointer")
        }
      }
      (1, _) =>
        return Err(
          "parameter " +
          param.name +
          ": pointer to const value (array length unknown)",
        )
      _ =>
        return Err(
          "parameter " +
          param.name +
          ": pointer to pointer (handles are not generated yet)",
        )
    }
    i += 1
  }
  let result = function.result
  let plan = match (result.pointers, result.base) {
    (0, CVoid) => RVoid
    (0, CRecord(record)) =>
      match self.fields(record) {
        Some(_) => {
          self.records_used[record] = true
          RStruct(record)
        }
        None => return Err("result: struct " + record + " is not flat")
      }
    (0, CEnum(name)) if self.model.enums.get(name) is Some(def) &&
      error_enum(def) => {
      self.enums_used[name] = true
      RCheck(name)
    }
    (0, _) =>
      match self.scalar(result) {
        Some(scalar) => {
          if scalar is SEnum(name) {
            self.enums_used[name] = true
          }
          RValue(scalar, result_spelling)
        }
        None => return Err("result: unsupported type")
      }
    (1, CChar) if result.const_pointee => RCString
    (1, CChar) => return Err("result: char * of unknown ownership")
    _ => return Err("result: pointer (handles are not generated yet)")
  }
  Ok((params, plan))
}

///|
fn moon_scalar(model : CHeaderModel, kind : Scalar) -> String {
  match kind {
    SInt => "Int"
    SUInt => "UInt"
    SInt64 => "Int64"
    SUInt64 => "UInt64"
    SFloat => "Float"
    SDouble => "Double"
    SBool => "Bool"
    SEnum(name) => type_name(model, name)
  }
}

///|
/// Type used at the C boundary (enums and Bool travel as Int).
fn boundary_scalar(kind : Scalar) -> String {
  match kind {
    SBool | SEnum(_) | SInt => "Int"
    SUInt => "UInt"
    SInt64 => "Int64"
    SUInt64 => "UInt64"
    SFloat => "Float"
    SDouble => "Double"
  }
}

///|
fn c_scalar(kind : Scalar) -> String {
  match kind {
    SBool | SEnum(_) | SInt => "int32_t"
    SUInt => "uint32_t"
    SInt64 => "int64_t"
    SUInt64 => "uint64_t"
    SFloat => "float"
    SDouble => "double"
  }
}

///|
fn zero_of(kind : Scalar) -> String {
  match kind {
    SFloat => "0.0"
    SDouble => "0.0"
    SInt64 => "0L"
    SUInt64 => "0UL"
    SUInt => "0U"
    _ => "0"
  }
}

///|
/// MoonBit expression converting a boundary value back to the API type.
fn lift_scalar(model : CHeaderModel, kind : Scalar, value : String) -> String {
  match kind {
    SBool => value + " != 0"
    SEnum(name) => type_name(model, name) + "::from_raw(" + value + ")"
    _ => value
  }
}

///|
/// MoonBit expression lowering an API value to its boundary type.
fn lower_scalar(kind : Scalar, value : String) -> String {
  match kind {
    SBool => "(if " + value + " { 1 } else { 0 })"
    SEnum(_) => value + ".to_raw()"
    _ => value
  }
}

///|
pub struct BindgenOutput {
  files : Array[(String, String)]
  bound : Array[String]
  /// Function name and reason.
  skipped : Array[(String, String)]
  libraries : Array[String]
}

///|
/// Emits the package for `spec`. `libraries` maps each function to the SDK
/// library exporting it (both ABIs); functions without one are skipped.
pub fn generate_bindings(
  spec : BindgenSpec,
  model : CHeaderModel,
  libraries : Map[String, String],
  sdk_api : Int32,
) -> BindgenOutput {
  let gen : Generator = {
    spec,
    model,
    enums_used: Map([]),
    records_used: Map([]),
  }
  let bindings : Array[Binding] = []
  let skipped : Array[(String, String)] = []
  let moon_names : Map[String, Bool] = Map([])
  for function in model.functions {
    let prefix = spec.prefixes.search_by(p => function.name.has_prefix(p))
    if (!spec.prefixes.is_empty() && prefix is None) ||
      spec.exclude.contains(function.name) {
      continue
    }
    guard libraries.get(function.name) is Some(library) else {
      skipped.push(
        (function.name, "not exported by any SDK library for both ABIs"),
      )
      continue
    }
    let spellings = function.params.map(p => p.spelling)
    match gen.plan(function, spellings, function.result_spelling) {
      Err(reason) => skipped.push((function.name, reason))
      Ok((params, result)) => {
        let stem = match prefix {
          Some(i) => function.name[spec.prefixes[i].length():].to_owned()
          None => function.name
        }
        let mut moon_name = snake_name(stem)
        while moon_names.contains(moon_name) {
          moon_name = moon_name + "_"
        }
        moon_names[moon_name] = true
        bindings.push({ function, moon_name, params, result, library, })
      }
    }
  }
  let libs : Array[String] = []
  for binding in bindings {
    if !libs.contains(binding.library) {
      libs.push(binding.library)
    }
  }
  libs.sort()
  let moon = gen.moon_source(bindings, sdk_api)
  let stub = gen.c_source(bindings)
  // `Float` needs no import in signatures; only UTF-8 helpers need one.
  let imports : Array[String] = []
  if moon.contains("@utf8.") {
    imports.push("  \"moonbitlang/core/encoding/utf8\",")
  }
  let package_file = (if imports.is_empty() {
      ""
    } else {
      "import {\n" + imports.join("\n") + "\n}\n\n"
    }) +
    "options(\n  \"native-stub\": [ \"" +
    spec.name +
    "_stub.c\" ],\n)\n"
  let descriptor : Json = {
    "schema": "moonohos-native-v1",
    "package": spec.package_name,
    "sources": [spec.name + "_stub.c"],
    "systemLibraries": Json(libs.map(l => Json::string(l))),
    "abis": ["arm64-v8a", "x86_64"],
  }
  let report = bindings_report(spec, bindings, skipped, libs, sdk_api, gen)
  {
    files: [
      (spec.name + ".mbt", moon),
      (spec.name + "_stub.c", stub),
      ("moon.pkg", package_file),
      ("moonohos.native.json", descriptor.stringify(indent=2) + "\n"),
      ("BINDINGS.md", report),
    ],
    bound: bindings.map(b => b.function.name),
    skipped,
    libraries: libs,
  }
}

///|
fn int32_literal(value : Int64) -> String {
  // Two's-complement view of values such as 0xFFFFFFFF.
  let low = value & 0xFFFFFFFFL
  let signed = if low >= 0x80000000L { low - 0x100000000L } else { low }
  if signed < 0L {
    "(" + signed.to_string() + ")"
  } else {
    signed.to_string()
  }
}

///|
fn Generator::enum_source(self : Generator, tag : String) -> String {
  guard self.model.enums.get(tag) is Some(def) else { return "" }
  let name = type_name(self.model, tag)
  let cases : Array[(String, String, Int64)] = []
  let used : Map[String, Bool] = Map([("Other", true)])
  for constant in def.constants {
    let mut ctor = constructor_name(constant.0)
    while used.contains(ctor) {
      ctor = ctor + "_"
    }
    used[ctor] = true
    cases.push((ctor, constant.0, constant.1))
  }
  let lines : Array[String] = [
    "///|",
    "/// C `" + tag + "`. `Other` carries values this binding does not name.",
    "pub(all) enum " + name + " {",
  ]
  for case in cases {
    lines.push("  /// `" + case.1 + "` (" + case.2.to_string() + ")")
    lines.push("  " + case.0)
  }
  lines.push("  Other(Int)")
  lines.push("}")
  lines.push("")
  lines.push("///|")
  lines.push("pub fn " + name + "::to_raw(self : " + name + ") -> Int {")
  lines.push("  match self {")
  for case in cases {
    lines.push("    " + case.0 + " => " + int32_literal(case.2))
  }
  lines.push("    Other(value) => value")
  lines.push("  }")
  lines.push("}")
  lines.push("")
  lines.push("///|")
  lines.push("pub fn " + name + "::from_raw(value : Int) -> " + name + " {")
  lines.push("  match value {")
  let seen : Map[String, Bool] = Map([])
  for case in cases {
    let literal = int32_literal(case.2)
    if seen.contains(literal) {
      continue
    }
    seen[literal] = true
    lines.push(
      "    " +
      literal.replace_all(old="(", new="").replace_all(old=")", new="") +
      " => " +
      case.0,
    )
  }
  lines.push("    _ => Other(value)")
  lines.push("  }")
  lines.push("}")
  lines.push("")
  lines.push("///|")
  lines.push(
    "/// The C constant name, or `" + tag + "(<value>)` for an unnamed value.",
  )
  lines.push("pub fn " + name + "::c_name(self : " + name + ") -> String {")
  lines.push("  match self {")
  for case in cases {
    lines.push("    " + case.0 + " => \"" + case.1 + "\"")
  }
  lines.push("    Other(value) => \"" + tag + "(\" + value.to_string() + \")\"")
  lines.push("  }")
  lines.push("}")
  lines.push("")
  lines.push("///|")
  lines.push("pub impl Eq for " + name + " with equal(self, other) {")
  lines.push("  self.to_raw() == other.to_raw()")
  lines.push("}")
  lines.push("")
  lines.push("///|")
  lines.push("pub impl Show for " + name + " with output(self, logger) {")
  lines.push("  logger.write_string(self.c_name())")
  lines.push("}")
  lines.push("")
  lines.push("///|")
  lines.push("pub extend " + name + " with Eq::{equal, not_equal}")
  lines.push("")
  lines.push("///|")
  lines.push("pub extend " + name + " with Show::{to_string, output}")
  lines.join("\n") + "\n"
}

///|
fn Generator::field_type(self : Generator, field : FieldPlan) -> String {
  match field {
    FScalar(_, _, kind) => moon_scalar(self.model, kind)
    FText(_, _, _) => "String"
    FBytes(_, _, _) => "Bytes"
  }
}

///|
fn Generator::record_source(self : Generator, record : String) -> String {
  guard self.fields(record) is Some(fields) else { return "" }
  let name = type_name(self.model, record)
  let lines = [
    "///|",
    "/// C `" + record + "`, copied field by field.",
    "pub(all) struct " + name + " {",
  ]
  for field in fields {
    let (c_name, moon) = match field {
      FScalar(c, m, _) | FText(c, m, _) | FBytes(c, m, _) => (c, m)
    }
    let note = match field {
      FText(_, _, n) =>
        " (`char[" +
        n.to_string() +
        "]`, UTF-8, truncated to " +
        (n - 1).to_string() +
        " bytes)"
      FBytes(_, _, n) => " (`uint8_t[" + n.to_string() + "]`)"
      _ => ""
    }
    lines.push("  /// `" + c_name + "`" + note)
    lines.push("  " + moon + " : " + self.field_type(field))
  }
  lines.push("}")
  lines.join("\n") + "\n"
}

///|
/// Boundary arguments, extern parameters, C parameters, setup and teardown
/// MoonBit statements for one plan.
priv struct Lowered {
  extern_params : Array[String]
  borrowed : Array[String]
  c_params : Array[String]
  args : Array[String]
  setup : Array[String]
  outputs : Array[(String, String)] // MoonBit type, expression
}

///|
fn Generator::lower_struct_in(
  self : Generator,
  name : String,
  record : String,
  out : Lowered,
) -> Unit {
  guard self.fields(record) is Some(fields) else { return }
  for field in fields {
    match field {
      FScalar(c, m, kind) => {
        let p = name + "_" + m
        out.extern_params.push(p + " : " + boundary_scalar(kind))
        out.c_params.push(c_scalar(kind) + " " + p)
        out.args.push(lower_scalar(kind, name + "." + m))
        ignore(c)
      }
      FText(_, m, _) => {
        let p = name + "_" + m
        out.extern_params.push(p + " : Bytes")
        out.borrowed.push(p)
        out.c_params.push("const uint8_t *" + p)
        out.args.push("c_string(" + name + "." + m + ")")
      }
      FBytes(_, m, n) => {
        let p = name + "_" + m
        out.extern_params.push(p + " : Bytes")
        out.borrowed.push(p)
        out.c_params.push("const uint8_t *" + p)
        out.args.push(
          "fixed_bytes(" + name + "." + m + ", " + n.to_string() + ")",
        )
      }
    }
  }
}

///|
/// Out (and in/out) struct: one buffer per field; `input` seeds them.
fn Generator::lower_struct_out(
  self : Generator,
  name : String,
  record : String,
  input : String?,
  out : Lowered,
) -> Unit {
  guard self.fields(record) is Some(fields) else { return }
  let built : Array[String] = []
  for field in fields {
    match field {
      FScalar(_, m, kind) => {
        let p = name + "_" + m
        let init = match input {
          Some(value) => lower_scalar(kind, value + "." + m)
          None => zero_of(kind)
        }
        out.setup.push(
          "let " +
          p +
          " : FixedArray[" +
          boundary_scalar(kind) +
          "] = [" +
          init +
          "]",
        )
        out.extern_params.push(
          p + " : FixedArray[" + boundary_scalar(kind) + "]",
        )
        out.borrowed.push(p)
        out.c_params.push(c_scalar(kind) + " *" + p)
        out.args.push(p)
        built.push(m + ": " + lift_scalar(self.model, kind, p + "[0]"))
      }
      FText(_, m, n) => {
        let p = name + "_" + m
        let init = match input {
          Some(value) =>
            "text_buffer(" + value + "." + m + ", " + (n + 1).to_string() + ")"
          None => "Bytes::make(" + (n + 1).to_string() + ", b'\\x00')"
        }
        out.setup.push("let " + p + " = " + init)
        out.extern_params.push(p + " : Bytes")
        out.borrowed.push(p)
        out.c_params.push("uint8_t *" + p)
        out.args.push(p)
        built.push(m + ": c_text(" + p + ")")
      }
      FBytes(_, m, n) => {
        let p = name + "_" + m
        let init = match input {
          Some(value) =>
            "fixed_bytes(" + value + "." + m + ", " + n.to_string() + ")"
          None => "Bytes::make(" + n.to_string() + ", b'\\x00')"
        }
        out.setup.push("let " + p + " = " + init)
        out.extern_params.push(p + " : Bytes")
        out.borrowed.push(p)
        out.c_params.push("uint8_t *" + p)
        out.args.push(p)
        built.push(m + ": " + p)
      }
    }
  }
  out.outputs.push(
    (type_name(self.model, record), "{ " + built.join(", ") + " }"),
  )
}

///|
fn Generator::lower(self : Generator, binding : Binding) -> Lowered {
  let out : Lowered = {
    extern_params: [],
    borrowed: [],
    c_params: [],
    args: [],
    setup: [],
    outputs: [],
  }
  let buffer = self.spec.string_buffer.to_string()
  match binding.result {
    RStruct(record) => self.lower_struct_out("result", record, None, out)
    RCString => {
      out.setup.push("let result_text = Bytes::make(" + buffer + ", b'\\x00')")
      out.extern_params.push("result_text : Bytes")
      out.borrowed.push("result_text")
      out.extern_params.push("result_capacity : Int")
      out.c_params.push("uint8_t *result_text")
      out.c_params.push("int32_t result_capacity")
      out.args.push("result_text")
      out.args.push(buffer)
      out.outputs.push(("String", "c_text(result_text)"))
    }
    _ => ()
  }
  for param in binding.params {
    match param {
      InValue(name, kind, _) => {
        out.extern_params.push(name + " : " + boundary_scalar(kind))
        out.c_params.push(c_scalar(kind) + " " + name)
        out.args.push(lower_scalar(kind, name))
      }
      InString(name) => {
        out.extern_params.push(name + " : Bytes")
        out.borrowed.push(name)
        out.c_params.push("const uint8_t *" + name)
        out.args.push("c_string(" + name + ")")
      }
      InBytes(name, _, _) => {
        out.extern_params.push(name + " : Bytes")
        out.borrowed.push(name)
        out.extern_params.push(name + "_length : Int")
        out.c_params.push("const uint8_t *" + name)
        out.c_params.push("int32_t " + name + "_length")
        out.args.push(name)
        out.args.push(name + ".length()")
      }
      OutValue(name, kind, _) => {
        out.setup.push(
          "let " +
          name +
          " : FixedArray[" +
          boundary_scalar(kind) +
          "] = [" +
          zero_of(kind) +
          "]",
        )
        out.extern_params.push(
          name + " : FixedArray[" + boundary_scalar(kind) + "]",
        )
        out.borrowed.push(name)
        out.c_params.push(c_scalar(kind) + " *" + name)
        out.args.push(name)
        out.outputs.push(
          (
            moon_scalar(self.model, kind),
            lift_scalar(self.model, kind, name + "[0]"),
          ),
        )
      }
      OutString(name, _, _) => {
        out.setup.push(
          "let " + name + " = Bytes::make(" + buffer + ", b'\\x00')",
        )
        out.extern_params.push(name + " : Bytes")
        out.borrowed.push(name)
        out.extern_params.push(name + "_capacity : Int")
        out.c_params.push("uint8_t *" + name)
        out.c_params.push("int32_t " + name + "_capacity")
        out.args.push(name)
        out.args.push(buffer)
        out.outputs.push(("String", "c_text(" + name + ")"))
      }
      InStruct(name, record, _) => self.lower_struct_in(name, record, out)
      InOutStruct(name, record) =>
        self.lower_struct_out(name, record, Some(name), out)
      OutStruct(name, record) => self.lower_struct_out(name, record, None, out)
    }
  }
  out
}

///|
fn Generator::api_params(self : Generator, binding : Binding) -> Array[String] {
  binding.params.filter_map(p => {
    match p {
      InValue(name, kind, _) =>
        Some(name + " : " + moon_scalar(self.model, kind))
      InString(name) => Some(name + " : String")
      InBytes(name, _, _) => Some(name + " : Bytes")
      InStruct(name, record, _) | InOutStruct(name, record) =>
        Some(name + " : " + type_name(self.model, record))
      OutValue(_, _, _) | OutString(_, _, _) | OutStruct(_, _) => None
    }
  })
}

///|
fn Generator::moon_function(self : Generator, binding : Binding) -> String {
  let lowered = self.lower(binding)
  let raw = "raw_" + binding.function.name
  let raw_result = match binding.result {
    RValue(kind, _) => boundary_scalar(kind)
    RCheck(_) => "Int"
    _ => "Unit"
  }
  let lines : Array[String] = ["///|"]
  if !lowered.borrowed.is_empty() {
    lines.push("#borrow(" + lowered.borrowed.join(", ") + ")")
  }
  lines.push(
    "extern \"C\" fn " +
    raw +
    "(" +
    lowered.extern_params.join(", ") +
    ") -> " +
    raw_result +
    " = \"moonohos_sys_" +
    binding.function.name +
    "\"",
  )
  lines.push("")
  let outputs = lowered.outputs.copy()
  match binding.result {
    RValue(kind, _) =>
      outputs.insert(
        0,
        (moon_scalar(self.model, kind), lift_scalar(self.model, kind, "value")),
      )
    _ => ()
  }
  let result_type = match outputs.length() {
    0 => "Unit"
    1 => outputs[0].0
    _ => "(" + outputs.map(o => o.0).join(", ") + ")"
  }
  let raises = binding.result is RCheck(_)
  lines.push("///|")
  lines.push(
    "/// `" +
    binding.function.name +
    "` from `" +
    binding.function.header +
    "` (`" +
    binding.library +
    "`).",
  )
  if raises {
    lines.push(
      "/// Raises `SysError` when the call returns a non-zero error code.",
    )
  }
  lines.push(
    "pub fn " +
    binding.moon_name +
    "(" +
    self.api_params(binding).join(", ") +
    ") -> " +
    result_type +
    (if raises { " raise SysError" } else { "" }) +
    " {",
  )
  for statement in lowered.setup {
    lines.push("  " + statement)
  }
  let call = raw + "(" + lowered.args.join(", ") + ")"
  match binding.result {
    RValue(_, _) => lines.push("  let value = " + call)
    RCheck(name) => {
      lines.push("  let code = " + call)
      lines.push("  if code != 0 {")
      lines.push(
        "    raise Failed(\"" +
        binding.function.name +
        "\", " +
        type_name(self.model, name) +
        "::from_raw(code).c_name(), code)",
      )
      lines.push("  }")
    }
    _ => lines.push("  " + call)
  }
  match outputs.length() {
    0 => ()
    1 => lines.push("  " + outputs[0].1)
    _ => lines.push("  (" + outputs.map(o => o.1).join(", ") + ")")
  }
  lines.push("}")
  lines.join("\n") + "\n"
}

///|
/// Helper sources, each emitted only when the generated code uses it.
let moon_helpers : Array[(String, String)] = [
  (
    "SysError",
    (
      #|///|
      #|/// Raised by functions whose C result is an error-code enum.
      #|pub(all) suberror SysError {
      #|  /// C function, error constant name, raw code.
      #|  Failed(String, String, Int)
      #|}
      #|
      #|///|
      #|pub impl Show for SysError with output(self, logger) {
      #|  match self {
      #|    Failed(function, name, code) =>
      #|      logger.write_string(
      #|        function + " failed: " + name + " (" + code.to_string() + ")",
      #|      )
      #|  }
      #|}
      #|
      #|///|
      #|pub extend SysError with Show::{to_string, output}
    ),
  ),
  (
    "c_string",
    (
      #|///|
      #|/// UTF-8 bytes of `text` with a terminating NUL (C `const char *`).
      #|fn c_string(text : String) -> Bytes {
      #|  @utf8.encode(text + "\u{0}")
      #|}
    ),
  ),
  (
    "c_text",
    (
      #|///|
      #|/// Decodes a NUL-terminated (or full) UTF-8 buffer written by C.
      #|fn c_text(buffer : Bytes) -> String {
      #|  let mut end = 0
      #|  while end < buffer.length() && buffer[end] != b'\x00' {
      #|    end += 1
      #|  }
      #|  @utf8.decode_lossy(buffer[0:end])
      #|}
    ),
  ),
  (
    "text_buffer",
    (
      #|///|
      #|/// A `capacity`-byte buffer holding `text` as a NUL-terminated C string.
      #|fn text_buffer(text : String, capacity : Int) -> Bytes {
      #|  let encoded = @utf8.encode(text)
      #|  Bytes::makei(capacity, i => {
      #|    if i < encoded.length() && i < capacity - 1 { encoded[i] } else { b'\x00' }
      #|  })
      #|}
    ),
  ),
  (
    "fixed_bytes",
    (
      #|///|
      #|/// Exactly `size` bytes of `data`, zero-padded or truncated.
      #|fn fixed_bytes(data : Bytes, size : Int) -> Bytes {
      #|  Bytes::makei(size, i => if i < data.length() { data[i] } else { b'\x00' })
      #|}
    ),
  ),
]

///|
fn Generator::moon_source(
  self : Generator,
  bindings : Array[Binding],
  sdk_api : Int32,
) -> String {
  let parts : Array[String] = [
    "// Generated by `moonohos bindgen` from " +
    self.spec.headers.join(", ") +
    " (HarmonyOS SDK API " +
    sdk_api.to_string() +
    "). Do not edit; regenerate instead.\n",
  ]
  // Functions first decide which enums and structs are needed.
  let functions = bindings.map(b => self.moon_function(b))
  let used = functions.join("\n")
  for helper in moon_helpers {
    let needed = if helper.0 == "SysError" {
      used.contains("raise SysError")
    } else {
      used.contains(helper.0 + "(")
    }
    if needed {
      parts.push(helper.1)
    }
  }
  let enum_names = self.enums_used.keys().collect()
  // Enums referenced only by struct fields.
  for record in self.records_used.keys() {
    match self.fields(record) {
      Some(fields) =>
        for field in fields {
          match field {
            FScalar(_, _, SEnum(name)) if !enum_names.contains(name) =>
              enum_names.push(name)
            _ => ()
          }
        }
      None => ()
    }
  }
  enum_names.sort()
  for name in enum_names {
    parts.push(self.enum_source(name))
  }
  let records = self.records_used.keys().collect()
  records.sort()
  for record in records {
    parts.push(self.record_source(record))
  }
  for function in functions {
    parts.push(function)
  }
  parts.join("\n")
}

///|
/// Parameter names that announce the length of the preceding buffer.
fn length_name(name : String) -> Bool {
  let lower = name.to_lower()
  ["len", "size", "count", "num", "capacity"].any(word => lower.contains(word))
}

///|
/// Functions that hand memory back to the SDK.
fn releasing_name(name : String) -> Bool {
  ["Destroy", "Release", "Free", "Delete"].any(word => name.contains(word))
}

///|
/// Getters fill a struct the caller provides without reading it.
fn output_name(name : String) -> Bool {
  ["Get", "Init", "Query"].any(word => name.contains(word))
}
