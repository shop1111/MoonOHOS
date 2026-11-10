///|
#derive(Eq, Debug)
pub(all) enum TypeExpr {
  Scalar(ValueType)
  List(TypeExpr)
  /// `Option[T]` / `T?`; ArkTS `T | undefined`. Crosses the C boundary as a
  /// zero- or one-element array.
  Optional(TypeExpr)
  /// Enum without payloads; ArkTS string literal union of its case names.
  /// Crosses the C boundary as an `Int` tag.
  Enum(String)
  Record(String)
  /// Opaque MoonBit value owned by an ArkTS handle object with `close()`.
  Handle(String)
  /// Platform value acquired by a native adapter, e.g. `@rawfile.Manager`.
  External(String, String)
  /// ArkTS function parameter `(T1, T2) -> Unit`; crosses C as an `Int64` call
  /// id and each invocation copies its arguments to the JS thread.
  Callback(Array[TypeExpr])
}

///|
pub struct FieldDef {
  name : String
  kind : TypeExpr
}

///|
pub struct RecordDef {
  name : String
  fields : Array[FieldDef]
}

///|
pub struct Callable {
  name : String
  params : Array[FieldDef]
  result : TypeExpr
  is_async : Bool
  raises : Bool
}

///|
/// `enums` manifest entry: an enum whose cases carry no payload.
pub struct EnumDef {
  name : String
  cases : Array[String]
}

///|
/// A function exposed as a method on its first (handle) parameter.
pub struct MethodDef {
  handle : String
  function : String
}

///|
pub struct Project {
  version : Int32
  module_dir : String
  package_name : String
  native_module : String
  workspace : String?
  records : Array[RecordDef]
  handles : Array[String]
  methods : Array[MethodDef]
  enums : Array[EnumDef]
  functions : Array[Callable]
  adapters : Array[AdapterDef]
}

///|
priv struct TypeCursor {
  tokens : Array[String]
  mut position : Int32
}

///|
fn type_tokens(text : String) -> Array[String] {
  let tokens : Array[String] = []
  let mut word = ""
  for ch in text {
    if ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r' {
      if !word.is_empty() {
        tokens.push(word)
        word = ""
      }
    } else if ch == '[' ||
      ch == ']' ||
      ch == '?' ||
      ch == '(' ||
      ch == ')' ||
      ch == ',' ||
      ch == '-' ||
      ch == '>' {
      if !word.is_empty() {
        tokens.push(word)
        word = ""
      }
      tokens.push(ch.to_string())
    } else {
      word += ch.to_string()
    }
  }
  if !word.is_empty() {
    tokens.push(word)
  }
  tokens
}

///|
fn TypeCursor::take(self : TypeCursor) -> String raise ConfigError {
  if self.position >= self.tokens.length() {
    raise Invalid("type: unexpected end of expression")
  }
  let token = self.tokens[self.position]
  self.position += 1
  token
}

///|
fn TypeCursor::expression(
  self : TypeCursor,
  depth : Int32,
  unit~ : Bool,
) -> TypeExpr raise ConfigError {
  if depth > 32 {
    raise Invalid("type: maximum nesting depth is 32")
  }
  let primary = match self.take() {
    "Array" | "Option" as head => {
      if self.take() != "[" {
        raise Invalid("type: " + head + " requires one type argument")
      }
      let element = self.expression(depth + 1, unit=false)
      if self.take() != "]" {
        raise Invalid("type: expected closing ]")
      }
      if head == "Array" {
        List(element)
      } else {
        Optional(element)
      }
    }
    "(" => {
      let args : Array[TypeExpr] = []
      if self.tokens.get(self.position) == Some(")") {
        self.position += 1
      } else {
        while true {
          args.push(self.expression(depth + 1, unit=false))
          match self.take() {
            "," => continue
            ")" => break
            token =>
              raise Invalid("type: expected , or ) in callback, found " + token)
          }
        }
      }
      if self.take() != "-" || self.take() != ">" {
        raise Invalid("type: callback types are written (T1, T2) -> Unit")
      }
      if self.take() != "Unit" {
        raise Invalid("type: callbacks must return Unit")
      }
      Callback(args)
    }
    // moonc >= 0.10.16 prints `Int` as `Int32` in .mbti files.
    "Int" | "Int32" => Scalar(Int32)
    "Int64" => Scalar(Int64)
    "Double" => Scalar(Float64)
    "Bool" => Scalar(Boolean)
    "String" => Scalar(Text)
    "Bytes" => Scalar(Binary)
    "Unit" if unit => Scalar(Void)
    "Unit" => raise Invalid("type: Unit is only supported as a function result")
    name if identifier(name) => Record(name)
    name if name.has_prefix("@") => {
      let parts = name[1:].split(".").map(s => s.to_owned()).to_array()
      if parts.length() != 2 || !identifier(parts[0]) || !identifier(parts[1]) {
        raise Invalid("type: platform types are written @package.Type")
      }
      External(parts[0], parts[1])
    }
    name => raise Invalid("type: unsupported expression " + name)
  }
  if self.position < self.tokens.length() && self.tokens[self.position] == "?" {
    self.position += 1
    Optional(primary)
  } else {
    primary
  }
}

///|
pub fn parse_type_expr(
  text : String,
  result~ : Bool = false,
) -> TypeExpr raise ConfigError {
  let cursor = TypeCursor::{ tokens: type_tokens(text), position: 0, }
  let kind = cursor.expression(0, unit=result)
  if cursor.position != cursor.tokens.length() {
    raise Invalid("type: trailing tokens in " + text)
  }
  kind
}

///|
pub fn TypeExpr::moon_name(self : TypeExpr) -> String {
  match self {
    Scalar(kind) => kind.moon_name()
    List(element) => "Array[" + element.moon_name() + "]"
    Optional(inner) => inner.moon_name() + "?"
    Enum(name) | Record(name) | Handle(name) => name
    External(pkg_alias, name) => "@" + pkg_alias + "." + name
    Callback(args) =>
      "(" + args.map(a => a.moon_name()).join(", ") + ") -> Unit"
  }
}

///|
pub fn TypeExpr::wrapper_name(self : TypeExpr) -> String {
  match self {
    Scalar(kind) => kind.moon_name()
    List(element) => "Array[" + element.wrapper_name() + "]"
    Optional(inner) => inner.wrapper_name() + "?"
    Enum(name) | Record(name) | Handle(name) => "@core." + name
    External(pkg_alias, name) => "@" + pkg_alias + "." + name
    Callback(args) =>
      "(" + args.map(a => a.wrapper_name()).join(", ") + ") -> Unit"
  }
}

///|
pub fn TypeExpr::c_name(self : TypeExpr) -> String {
  match self {
    Scalar(kind) => kind.c_name()
    Enum(_) => "int32_t"
    Callback(_) => "int64_t"
    List(_) | Optional(_) | Record(_) | Handle(_) | External(_, _) => "void *"
  }
}

///|
pub fn TypeExpr::ark_name(self : TypeExpr) -> String {
  match self {
    Scalar(kind) => kind.ark_name()
    List(element) => "Array<" + element.ark_name() + ">"
    Optional(inner) => inner.ark_name() + " | undefined"
    Enum(name) | Record(name) | Handle(name) | External(_, name) => name
    Callback(args) =>
      "(" +
      args
      .mapi((i, a) => "arg" + i.to_string() + ": " + a.ark_name())
      .join(", ") +
      ") => void"
  }
}

///|
/// Handles, adapters and callbacks cross the bridge by reference and are
/// never copied.
pub fn TypeExpr::is_opaque(self : TypeExpr) -> Bool {
  match self {
    Handle(_) | External(_, _) | Callback(_) => true
    List(element) | Optional(element) => element.is_opaque()
    _ => false
  }
}

///|
fn TypeExpr::bind_handles(
  self : TypeExpr,
  handles : Array[String],
  enums~ : Array[String] = [],
) -> TypeExpr {
  match self {
    Record(name) if handles.contains(name) => Handle(name)
    Record(name) if enums.contains(name) => Enum(name)
    List(element) => List(element.bind_handles(handles, enums~))
    Optional(inner) => Optional(inner.bind_handles(handles, enums~))
    Callback(args) => Callback(args.map(a => a.bind_handles(handles, enums~)))
    other => other
  }
}

///|
pub fn TypeExpr::is_reference(self : TypeExpr) -> Bool {
  match self {
    Scalar(Text | Binary) | List(_) | Optional(_) | Record(_) => true
    _ => false
  }
}

///|
fn checked_name(value : Json, context : String) -> String raise ConfigError {
  let name = required_string(value, "name")
  if !identifier(name) {
    raise Invalid(context + ": invalid identifier " + name)
  }
  name
}

///|
fn parse_fields(
  value : Json,
  key : String,
  context : String,
) -> Array[FieldDef] raise ConfigError {
  let values = match field(value, key) {
    Some(Array(values)) => values
    _ => raise Invalid(context + ": " + key + " must be an array")
  }
  let fields : Array[FieldDef] = []
  let seen : Map[String, Bool] = Map([])
  for value in values {
    let name = checked_name(value, context)
    if seen.contains(name) {
      raise Invalid(context + ": duplicate field " + name)
    }
    seen[name] = true
    fields.push({ name, kind: parse_type_expr(required_string(value, "type")), })
  }
  fields
}

///|
fn optional_flag(
  value : Json,
  key : String,
  version : Int32,
  context : String,
) -> Bool raise ConfigError {
  match field(value, key) {
    None => false
    Some(_) if version < 2 =>
      raise Invalid(context + ": " + key + " requires version 2")
    Some(True) => true
    Some(False) => false
    _ => raise Invalid(context + ": " + key + " must be a boolean")
  }
}

///|
pub fn parse_project(text : String) -> Project raise ConfigError {
  let json = @json.parse(text) catch {
    _ => raise Invalid("config: invalid JSON")
  }
  let version = match field(json, "version") {
    Some(Number(1.0, ..)) => 1
    Some(Number(2.0, ..)) => 2
    _ => raise Invalid("config: version must be 1 or 2")
  }
  let module_dir = required_string(json, "module")
  let package_name = required_string(json, "package")
  if package_name.contains("\"") ||
    package_name.contains("\\") ||
    package_name.contains("..") ||
    package_name.contains("\n") ||
    package_name.contains(" ") ||
    !package_name.contains("/") {
    raise Invalid("config: invalid package name")
  }
  let native_module = required_string(json, "nativeModule")
  if !identifier(native_module) {
    raise Invalid("config: invalid nativeModule")
  }
  let workspace = match field(json, "workspace") {
    None => None
    Some(_) if version < 2 =>
      raise Invalid("config: workspace requires version 2")
    Some(String(path)) if path != "" => Some(path)
    _ => raise Invalid("config: workspace must be a path")
  }
  let reserved = [
    "Int", "Int32", "Int64", "Option", "Double", "Bool", "String", "Bytes", "Unit",
    "Array",
  ]
  let names : Map[String, Bool] = Map([])
  let handles : Array[String] = []
  let methods : Array[MethodDef] = []
  match field(json, "handles") {
    None => ()
    Some(_) if version < 2 => raise Invalid("config: handles require version 2")
    Some(Array(entries)) =>
      for entry in entries {
        let name = checked_name(entry, "handles")
        if names.contains(name) || reserved.contains(name) {
          raise Invalid("handles: duplicate/reserved type " + name)
        }
        names[name] = true
        handles.push(name)
        match field(entry, "methods") {
          None => ()
          Some(Array(values)) =>
            for value in values {
              match value {
                String(function) if identifier(function) =>
                  methods.push({ handle: name, function, })
                _ =>
                  raise Invalid(
                    "handles." + name + ": methods must be function names",
                  )
              }
            }
          _ => raise Invalid("handles." + name + ": methods must be an array")
        }
      }
    _ => raise Invalid("config: handles must be an array")
  }
  let enums : Array[EnumDef] = []
  match field(json, "enums") {
    None => ()
    Some(Array(entries)) =>
      for entry in entries {
        let name = checked_name(entry, "enums")
        if names.contains(name) || reserved.contains(name) {
          raise Invalid("enums: duplicate/reserved type " + name)
        }
        names[name] = true
        let cases : Array[String] = []
        match field(entry, "cases") {
          Some(Array(values)) if !values.is_empty() && values.length() <= 1024 =>
            for value in values {
              match value {
                String(case_name) if identifier(case_name) &&
                  !cases.contains(case_name) => cases.push(case_name)
                _ =>
                  raise Invalid(
                    "enums." + name + ": cases must be unique identifiers",
                  )
              }
            }
          _ =>
            raise Invalid(
              "enums." +
              name +
              ": cases must be a non-empty array (at most 1024)",
            )
        }
        enums.push({ name, cases, })
      }
    _ => raise Invalid("config: enums must be an array")
  }
  let enum_names = enums.map(e => e.name)
  let entries = match field(json, "types") {
    None => []
    Some(Array(entries)) => entries
    _ => raise Invalid("config: types must be an array")
  }
  let records : Array[RecordDef] = []
  for entry in entries {
    let name = checked_name(entry, "types")
    if names.contains(name) || reserved.contains(name) {
      raise Invalid("types: duplicate/reserved type " + name)
    }
    names[name] = true
    records.push({
      name,
      fields: parse_fields(entry, "fields", "types." + name).map(f => {
        name: f.name,
        kind: f.kind.bind_handles(handles, enums=enum_names),
      }),
    })
  }
  let entries = match field(json, "functions") {
    Some(Array(entries)) if !entries.is_empty() => entries
    _ => raise Invalid("config: functions must be a non-empty array")
  }
  let functions : Array[Callable] = []
  let names : Map[String, Bool] = Map([])
  for entry in entries {
    let name = checked_name(entry, "functions")
    if names.contains(name) {
      raise Invalid("functions: duplicate function " + name)
    }
    names[name] = true
    let context = "functions." + name
    let result = parse_type_expr(required_string(entry, "return"), result=true)
    functions.push({
      name,
      params: parse_fields(entry, "params", context).map(p => {
        name: p.name,
        kind: p.kind.bind_handles(handles, enums=enum_names),
      }),
      result: result.bind_handles(handles, enums=enum_names),
      is_async: optional_flag(entry, "async", version, context),
      raises: optional_flag(entry, "raises", version, context),
    })
  }
  {
    version,
    module_dir,
    package_name,
    native_module,
    workspace,
    records,
    handles,
    methods,
    enums,
    functions,
    adapters: [],
  }
}

///|
pub fn Config::to_project(self : Config) -> Project {
  {
    version: 1,
    module_dir: self.module_dir,
    package_name: self.package_name,
    native_module: self.native_module,
    workspace: None,
    records: [],
    handles: [],
    methods: [],
    enums: [],
    functions: self.functions.map(f => {
      name: f.name,
      params: f.params.map(p => { name: p.name, kind: Scalar(p.kind), }),
      result: Scalar(f.result),
      is_async: false,
      raises: false,
    }),
    adapters: [],
  }
}

///|
/// Attaches platform adapters discovered from native dependency descriptors.
pub fn Project::with_adapters(
  self : Project,
  adapters : Array[AdapterDef],
) -> Project {
  { ..self, adapters, }
}

///|
#deprecated
pub extend TypeExpr with Eq::{equal, not_equal}

///|
#deprecated
pub extend TypeExpr with @debug.Debug::{to_repr}
