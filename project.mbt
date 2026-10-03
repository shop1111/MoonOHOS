///|
pub(all) enum TypeExpr {
  Scalar(ValueType)
  List(TypeExpr)
  Record(String)
} derive(Eq, Debug)

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
}

///|
pub struct Project {
  module_dir : String
  package_name : String
  native_module : String
  records : Array[RecordDef]
  functions : Array[Callable]
}

///|
priv struct TypeCursor {
  tokens : Array[String]
  mut position : Int
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
    } else if ch == '[' || ch == ']' {
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
  depth : Int,
  unit~ : Bool,
) -> TypeExpr raise ConfigError {
  if depth > 32 {
    raise Invalid("type: maximum nesting depth is 32")
  }
  match self.take() {
    "Array" => {
      if self.take() != "[" {
        raise Invalid("type: Array requires one type argument")
      }
      let element = self.expression(depth + 1, unit=false)
      if self.take() != "]" {
        raise Invalid("type: expected closing ]")
      }
      List(element)
    }
    "Int" => Scalar(Int32)
    "Double" => Scalar(Float64)
    "Bool" => Scalar(Boolean)
    "String" => Scalar(Text)
    "Bytes" => Scalar(Binary)
    "Unit" if unit => Scalar(Void)
    "Unit" => raise Invalid("type: Unit is only supported as a function result")
    name if identifier(name) => Record(name)
    name => raise Invalid("type: unsupported expression " + name)
  }
}

///|
pub fn parse_type_expr(
  text : String,
  result? : Bool = false,
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
    Record(name) => name
  }
}

///|
pub fn TypeExpr::wrapper_name(self : TypeExpr) -> String {
  match self {
    Scalar(kind) => kind.moon_name()
    List(element) => "Array[" + element.wrapper_name() + "]"
    Record(name) => "@core." + name
  }
}

///|
pub fn TypeExpr::c_name(self : TypeExpr) -> String {
  match self {
    Scalar(kind) => kind.c_name()
    List(_) | Record(_) => "void *"
  }
}

///|
pub fn TypeExpr::ark_name(self : TypeExpr) -> String {
  match self {
    Scalar(kind) => kind.ark_name()
    List(element) => "Array<" + element.ark_name() + ">"
    Record(name) => name
  }
}

///|
pub fn TypeExpr::is_reference(self : TypeExpr) -> Bool {
  match self {
    Scalar(Text | Binary) | List(_) | Record(_) => true
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
pub fn parse_project(text : String) -> Project raise ConfigError {
  let json = @json.parse(text) catch {
    _ => raise Invalid("config: invalid JSON")
  }
  match field(json, "version") {
    Some(Number(1.0, ..)) => ()
    _ => raise Invalid("config: version must be 1")
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
  let entries = match field(json, "types") {
    None => []
    Some(Array(entries)) => entries
    _ => raise Invalid("config: types must be an array")
  }
  let records : Array[RecordDef] = []
  let names : Map[String, Bool] = Map([])
  for entry in entries {
    let name = checked_name(entry, "types")
    if names.contains(name) ||
      ["Int", "Double", "Bool", "String", "Bytes", "Unit", "Array"].contains(
        name,
      ) {
      raise Invalid("types: duplicate/reserved type " + name)
    }
    names[name] = true
    records.push({
      name,
      fields: parse_fields(entry, "fields", "types." + name),
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
    functions.push({
      name,
      params: parse_fields(entry, "params", "functions." + name),
      result: parse_type_expr(required_string(entry, "return"), result=true),
    })
  }
  { module_dir, package_name, native_module, records, functions, }
}

///|
pub fn Config::to_project(self : Config) -> Project {
  {
    module_dir: self.module_dir,
    package_name: self.package_name,
    native_module: self.native_module,
    records: [],
    functions: self.functions.map(f => {
      name: f.name,
      params: f.params.map(p => { name: p.name, kind: Scalar(p.kind), }),
      result: Scalar(f.result),
    }),
  }
}

///|
#deprecated
pub extend TypeExpr with Eq::{equal, not_equal}

///|
#deprecated
pub extend TypeExpr with @debug.Debug::{to_repr}
