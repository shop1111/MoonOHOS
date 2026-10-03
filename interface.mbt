///|
pub struct InterfaceFunction {
  name : String
  params : Array[TypeExpr]
  result : TypeExpr
  unsupported : String?
}

///|
pub struct InterfaceRecord {
  name : String
  fields : Array[FieldDef]
  unsupported : String?
}

///|
pub struct PackageInterface {
  functions : Array[InterfaceFunction]
  records : Array[InterfaceRecord]
}

///|
priv struct InterfaceCursor {
  tokens : Array[String]
  mut offset : Int
}

///|
fn interface_tokens(text : String) -> Array[String] {
  let tokens : Array[String] = []
  let mut word = ""
  let mut quoted = false
  let mut escaped = false
  let mut comment = false
  let mut slash = false
  for ch in text {
    if comment {
      if ch == '\n' {
        comment = false
      }
      continue
    }
    if quoted {
      if escaped {
        escaped = false
      } else if ch == '\\' {
        escaped = true
      } else if ch == '"' {
        quoted = false
        tokens.push("<string>")
      }
      continue
    }
    if slash {
      slash = false
      if ch == '/' {
        comment = true
        continue
      }
      tokens.push("/")
    }
    if (ch >= 'a' && ch <= 'z') ||
      (ch >= 'A' && ch <= 'Z') ||
      (ch >= '0' && ch <= '9') ||
      ch == '_' ||
      ch == '@' {
      word += ch.to_string()
      continue
    }
    if !word.is_empty() {
      tokens.push(word)
      word = ""
    }
    if ch == '"' {
      quoted = true
    } else if ch == '/' {
      slash = true
    } else if ch != ' ' && ch != '\t' && ch != '\n' && ch != '\r' {
      tokens.push(ch.to_string())
    }
  }
  if !word.is_empty() {
    tokens.push(word)
  }
  if slash {
    tokens.push("/")
  }
  tokens
}

///|
fn InterfaceCursor::peek(self : InterfaceCursor) -> String {
  self.tokens.get(self.offset).unwrap_or("<end>")
}

///|
fn InterfaceCursor::take(self : InterfaceCursor) -> String raise ConfigError {
  if self.offset >= self.tokens.length() {
    raise Invalid("interface: unexpected end of declaration")
  }
  let value = self.tokens[self.offset]
  self.offset += 1
  value
}

///|
fn InterfaceCursor::expect(
  self : InterfaceCursor,
  token : String,
) -> Unit raise ConfigError {
  let actual = self.take()
  if actual != token {
    raise Invalid("interface: expected " + token + ", found " + actual)
  }
}

///|
fn InterfaceCursor::kind(
  self : InterfaceCursor,
  depth : Int,
) -> TypeExpr raise ConfigError {
  if depth > 32 {
    raise Invalid("interface: type nesting exceeds 32")
  }
  let name = self.take()
  if name == "Array" {
    self.expect("[")
    let element = self.kind(depth + 1)
    self.expect("]")
    List(element)
  } else {
    let kind = parse_type_expr(name, result=true)
    if self.peek() == "[" ||
      self.peek() == "?" ||
      self.peek() == "." ||
      self.peek() == "::" {
      raise Invalid(
        "interface: unsupported generic, optional or qualified type " + name,
      )
    }
    kind
  }
}

///|
fn parse_interface_function(tokens : Array[String]) -> InterfaceFunction {
  let cursor = InterfaceCursor::{ tokens, offset: 0, }
  let mut name = ""
  let params : Array[TypeExpr] = []
  let mut result = Scalar(Void)
  let unsupported = try {
    name = cursor.take()
    if !identifier(name) {
      raise Invalid("generic functions are unsupported")
    }
    cursor.expect("(")
    if cursor.peek() != ")" {
      while true {
        params.push(cursor.kind(0))
        if cursor.peek() != "," {
          break
        }
        cursor.take() |> ignore
        if cursor.peek() == ")" {
          break
        }
        continue
      }
    }
    cursor.expect(")")
    cursor.expect("-")
    cursor.expect(">")
    result = cursor.kind(0)
    if cursor.offset != tokens.length() {
      raise Invalid("raises, labels and other signature syntax are unsupported")
    }
    None
  } catch {
    Invalid(message) => Some(message)
  }
  { name, params, result, unsupported, }
}

///|
fn parse_interface_record(
  tokens : Array[String],
  value_type : Bool,
) -> InterfaceRecord {
  let cursor = InterfaceCursor::{ tokens, offset: 0, }
  let mut name = ""
  let fields : Array[FieldDef] = []
  let unsupported = try {
    name = cursor.take()
    if value_type {
      raise Invalid("#value structures are unsupported")
    }
    cursor.expect("{")
    while cursor.peek() != "}" {
      if cursor.peek() == "mut" {
        cursor.take() |> ignore
      }
      let field_name = cursor.take()
      if !identifier(field_name) {
        raise Invalid("private/opaque record fields are unsupported")
      }
      cursor.expect(":")
      let kind = cursor.kind(0)
      fields.push({ name: field_name, kind, })
      if cursor.peek() == "," || cursor.peek() == ";" {
        cursor.take() |> ignore
      }
    }
    cursor.expect("}")
    if cursor.offset != tokens.length() {
      raise Invalid("generic or attributed record syntax is unsupported")
    }
    None
  } catch {
    Invalid(message) => Some(message)
  }
  { name, fields, unsupported, }
}

///|
/// Parses selected declarations structurally; unrelated traits remain opaque.
pub fn parse_package_interface(text : String) -> PackageInterface {
  let tokens = interface_tokens(text)
  let functions : Array[InterfaceFunction] = []
  let records : Array[InterfaceRecord] = []
  let mut index = 0
  let mut value_type = false
  while index < tokens.length() {
    if tokens[index] == "#" && tokens.get(index + 1) == Some("value") {
      value_type = true
    }
    if tokens[index] != "pub" {
      index += 1
      continue
    }
    index += 1
    if tokens.get(index) == Some("(") {
      while index < tokens.length() && tokens[index] != ")" {
        index += 1
      }
      index += 1
    }
    let category = tokens.get(index).unwrap_or("")
    index += 1
    let start = index
    while index < tokens.length() &&
          tokens[index] != "pub" &&
          tokens[index] != "#" {
      index += 1
    }
    let declaration = tokens[start:index].to_owned()
    match category {
      "fn" => functions.push(parse_interface_function(declaration))
      "struct" => records.push(parse_interface_record(declaration, value_type))
      _ => ()
    }
    value_type = false
  }
  { functions, records, }
}

///|
pub fn Project::verify_interface(
  self : Project,
  text : String,
) -> Unit raise ConfigError {
  self.validate()
  let interface = parse_package_interface(text)
  for expected in self.functions {
    let actual = interface.functions
      .search_by(f => f.name == expected.name)
      .map(i => interface.functions[i])
    let actual = actual.unwrap_or_else(() => {
      raise Invalid("interface: missing public function " + expected.name)
    })
    if actual.unsupported is Some(reason) {
      raise Invalid("interface: " + expected.name + ": " + reason)
    }
    if actual.params != expected.params.map(p => p.kind) ||
      actual.result != expected.result {
      raise Invalid(
        "interface: signature mismatch; expected " + expected.signature(),
      )
    }
  }
  for expected in self.records {
    let actual = interface.records
      .search_by(r => r.name == expected.name)
      .map(i => interface.records[i])
    let actual = actual.unwrap_or_else(() => {
      raise Invalid("interface: missing public record " + expected.name)
    })
    if actual.unsupported is Some(reason) {
      raise Invalid("interface: " + expected.name + ": " + reason)
    }
    if actual.fields.length() != expected.fields.length() {
      raise Invalid("interface: incomplete fields for " + expected.name)
    }
    for field in expected.fields {
      let actual_field = actual.fields
        .search_by(f => f.name == field.name)
        .map(i => actual.fields[i])
      match actual_field {
        Some(actual_field) if actual_field.kind == field.kind => ()
        _ =>
          raise Invalid(
            "interface: field mismatch " + expected.name + "." + field.name,
          )
      }
    }
  }
}
